use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock, RwLock};
use std::time::UNIX_EPOCH;

use rayon::prelude::*;

use crate::rules::{Regenerability, RuleSet};
use crate::safety;

/// Files smaller than this fold into one "(small files)" node per directory,
/// keeping the tree small enough to hold and ship to the UI.
pub const SMALL_FILE_THRESHOLD: u64 = 1_000_000;

/// Defensive backstop against pathological/looping directory nesting. Real
/// trees are rarely deeper than a few dozen levels; anything past this is
/// recorded as skipped rather than descended into, so the parallel walk can't
/// exhaust even a generously sized worker stack.
const MAX_WALK_DEPTH: u32 = 1000;

/// Worker-thread stack size for the scan pool. The walk is recursive over
/// directory depth; a roomy stack plus [`MAX_WALK_DEPTH`] makes deep trees
/// safe without rewriting the parallel post-order aggregation.
const SCAN_STACK_SIZE: usize = 16 * 1024 * 1024;

/// Most skipped paths we itemize; beyond this only the aggregate error count
/// grows. Keeps the surfaced list bounded on a badly-permissioned disk.
const SKIP_CAP: usize = 100;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeKind {
    Dir,
    File,
    /// Aggregate of a directory's files below [`SMALL_FILE_THRESHOLD`].
    SmallFiles,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    /// Not flagged by anything.
    None,
    /// Confirmed regenerable by the rules engine — safe to reclaim.
    Safe,
    /// Flagged, but a human should look first.
    Review,
    /// Hard denylist. Deletion is refused at every layer.
    Protected,
}

#[derive(Debug)]
pub struct Node {
    pub name: String,
    pub kind: NodeKind,
    /// Size actually allocated on disk (`st_blocks`-based on Unix).
    pub size: u64,
    /// Apparent (logical) size — `meta.len()` summed. Differs from `size` for
    /// APFS clones, sparse files, and block-rounding.
    pub logical_size: u64,
    pub mtime: i64,
    pub parent: Option<u32>,
    /// Sorted by size, descending.
    pub children: Vec<u32>,
    pub file_count: u64,
    pub dir_count: u64,
    /// For `SmallFiles`: how many files were folded in.
    pub item_count: u64,
    pub rule: Option<u16>,
    pub tier: Tier,
}

pub struct ScanStore {
    pub root_path: PathBuf,
    pub nodes: Vec<Node>,
    pub root: u32,
    pub errors: u64,
    /// Paths that couldn't be read (permission denied, or past the depth
    /// guard), capped at [`SKIP_CAP`]. Itemized so the UI can name them.
    pub skipped: Vec<String>,
    pub rules: RuleSet,
    /// Lowercased node names, built on first search (indexes match `nodes`)
    /// and dropped with the store, so search doesn't re-lowercase the whole
    /// arena on every keystroke.
    pub lower_names: OnceLock<Vec<String>>,
}

impl ScanStore {
    pub fn node(&self, id: u32) -> Option<&Node> {
        self.nodes.get(id as usize)
    }

    pub fn path_of(&self, id: u32) -> PathBuf {
        let mut names = Vec::new();
        let mut cur = Some(id);
        while let Some(i) = cur {
            let n = &self.nodes[i as usize];
            if n.parent.is_some() {
                names.push(n.name.clone());
            }
            cur = n.parent;
        }
        let mut p = self.root_path.clone();
        for name in names.iter().rev() {
            p.push(name);
        }
        p
    }

    /// Path relative to the scan root, `/`-separated, for display and LLM digests.
    pub fn rel_path_of(&self, id: u32) -> String {
        let mut names = Vec::new();
        let mut cur = Some(id);
        while let Some(i) = cur {
            let n = &self.nodes[i as usize];
            if n.parent.is_some() {
                names.push(n.name.clone());
            }
            cur = n.parent;
        }
        names.reverse();
        names.join("/")
    }
}

/// The one scan the app holds at a time. Fresh scan on every launch; nothing
/// is ever persisted to disk.
pub static STORE: RwLock<Option<ScanStore>> = RwLock::new(None);

#[derive(Default)]
pub struct ProgressCounters {
    pub files: AtomicU64,
    pub dirs: AtomicU64,
    pub bytes: AtomicU64,
    pub errors: AtomicU64,
    pub cancel: AtomicBool,
    pub current: Mutex<String>,
    /// Paths that couldn't be read, capped at [`SKIP_CAP`]. The `errors`
    /// counter still counts every failure; this only holds the first few names.
    pub skipped: Mutex<Vec<String>>,
}

impl ProgressCounters {
    fn record_skip(&self, path: &Path) {
        self.errors.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut v) = self.skipped.lock() {
            if v.len() < SKIP_CAP {
                v.push(path.to_string_lossy().into_owned());
            }
        }
    }
}

struct ScanCtx<'a> {
    rules: &'a RuleSet,
    progress: &'a ProgressCounters,
    // Hardlink dedup keys on (dev, inode), which only exist on Unix; the
    // field is unread elsewhere but kept so construction stays uniform.
    #[cfg_attr(not(unix), allow(dead_code))]
    hardlinks: Mutex<HashSet<(u64, u64)>>,
}

struct TmpNode {
    name: String,
    kind: NodeKind,
    size: u64,
    logical_size: u64,
    mtime: i64,
    file_count: u64,
    dir_count: u64,
    item_count: u64,
    rule: Option<u16>,
    children: Vec<TmpNode>,
}

impl TmpNode {
    fn dir(name: String, mtime: i64, rule: Option<u16>) -> Self {
        Self {
            name,
            kind: NodeKind::Dir,
            size: 0,
            logical_size: 0,
            mtime,
            file_count: 0,
            dir_count: 0,
            item_count: 0,
            rule,
            children: Vec::new(),
        }
    }
}

/// Walk `root` in parallel and build the scan tree. Always returns the tree
/// built so far — on cancel (`progress.cancel`), `walk` returns whatever
/// partial nodes it had accumulated, and we still flatten and finalize them
/// so the caller gets a usable (if incomplete) result. Check
/// `progress.cancel` to know whether the scan was cut short.
pub fn scan(root: &Path, rules: RuleSet, progress: &ProgressCounters) -> ScanStore {
    let ctx = ScanCtx {
        rules: &rules,
        progress,
        hardlinks: Mutex::new(HashSet::new()),
    };
    let root_mtime = fs::symlink_metadata(root)
        .map(|m| mtime_of(&m))
        .unwrap_or(0);
    let name = root
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| root.to_string_lossy().into_owned());

    // Run the parallel walk on a pool with roomy worker stacks; the walk
    // recurses over directory depth and Rayon may run children inline on the
    // same worker, so the default (small) worker stack is the overflow risk.
    let tmp = match rayon::ThreadPoolBuilder::new()
        .stack_size(SCAN_STACK_SIZE)
        .build()
    {
        Ok(pool) => pool.install(|| walk(root, name.clone(), root_mtime, None, false, 0, &ctx)),
        // If the pool can't be built, fall back to the global pool rather than
        // failing the scan outright.
        Err(_) => walk(root, name, root_mtime, None, false, 0, &ctx),
    };

    let mut nodes = Vec::new();
    let root_id = flatten(tmp, &mut nodes);
    let skipped = progress
        .skipped
        .lock()
        .map(|v| v.clone())
        .unwrap_or_default();
    let mut store = ScanStore {
        root_path: root.to_path_buf(),
        nodes,
        root: root_id,
        errors: progress.errors.load(Ordering::Relaxed),
        skipped,
        rules,
        lower_names: OnceLock::new(),
    };
    finalize(&mut store);
    store
}

/// Directories never descended into when met during a walk (scanning one
/// directly as the root still works — the check runs on children only).
///
/// On macOS the Data volume is firmlinked into `/Users`, `/Applications`,
/// `/Library`, … so also walking `/System/Volumes/Data` counts every user
/// file twice (a `/` scan then reports far more than the disk holds);
/// `/System/Volumes` additionally holds Preboot/VM/Update noise. `/Volumes`
/// mounts external disks plus the boot volume itself.
#[cfg(target_os = "macos")]
fn is_skipped_mount(path: &Path) -> bool {
    matches!(
        path.to_str(),
        Some("/System/Volumes" | "/Volumes" | "/dev" | "/cores" | "/home" | "/net")
    )
}

/// On Linux, virtual filesystems (`/proc` is effectively infinite) and
/// removable-media mount points.
#[cfg(target_os = "linux")]
fn is_skipped_mount(path: &Path) -> bool {
    matches!(
        path.to_str(),
        Some("/proc" | "/sys" | "/dev" | "/run" | "/mnt" | "/media")
    )
}

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
fn is_skipped_mount(_path: &Path) -> bool {
    false
}

fn walk(
    path: &Path,
    name: String,
    mtime: i64,
    rule: Option<u16>,
    in_matched: bool,
    depth: u32,
    ctx: &ScanCtx,
) -> TmpNode {
    let mut node = TmpNode::dir(name, mtime, rule);
    if ctx.progress.cancel.load(Ordering::Relaxed) {
        return node;
    }
    // Defensive depth backstop: stop descending past MAX_WALK_DEPTH and record
    // the path rather than risk exhausting the worker stack.
    if depth >= MAX_WALK_DEPTH {
        ctx.progress.record_skip(path);
        return node;
    }
    // try_lock: the progress text is sampled every ~120ms, so a missed update
    // is invisible — never worth serializing the workers over.
    if let Ok(mut cur) = ctx.progress.current.try_lock() {
        *cur = path.to_string_lossy().into_owned();
    }

    let read = match fs::read_dir(path) {
        Ok(r) => r,
        Err(_) => {
            ctx.progress.record_skip(path);
            return node;
        }
    };

    let mut files = Vec::new();
    let mut dirs: Vec<(String, PathBuf, i64)> = Vec::new();
    for entry in read {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => {
                ctx.progress.errors.fetch_add(1, Ordering::Relaxed);
                continue;
            }
        };
        let file_type = match entry.file_type() {
            Ok(t) => t,
            Err(_) => {
                ctx.progress.errors.fetch_add(1, Ordering::Relaxed);
                continue;
            }
        };
        let entry_name = entry.file_name().to_string_lossy().into_owned();
        if file_type.is_dir() {
            if is_skipped_mount(&entry.path()) {
                continue;
            }
            // DirEntry::metadata does not traverse symlinks, so `is_dir` here
            // means a real directory — symlinks to dirs land in the file arm.
            let m = entry.metadata().map(|m| mtime_of(&m)).unwrap_or(0);
            dirs.push((entry_name, entry.path(), m));
        } else {
            files.push((entry_name, entry));
        }
    }

    // Rule-match subdirectories before `files`/`dirs` are consumed below.
    // Sibling names are only collected (borrowed, no copies) when some subdir
    // is actually a sibling-dependent rule candidate — almost never, so the
    // common case does no set-building at all.
    let matched_here = in_matched || rule.is_some();
    let dir_rules: Vec<Option<u16>> = if matched_here {
        vec![None; dirs.len()]
    } else {
        let need_names = dirs
            .iter()
            .any(|(name, _, _)| ctx.rules.needs_sibling_check(name));
        let names: HashSet<&str> = if need_names {
            files
                .iter()
                .map(|(name, _)| name.as_str())
                .chain(dirs.iter().map(|(name, _, _)| name.as_str()))
                .collect()
        } else {
            HashSet::new()
        };
        dirs.iter()
            .map(|(name, _, _)| ctx.rules.match_dir(name, &names))
            .collect()
    };

    let mut small_sum: u64 = 0;
    let mut small_logical: u64 = 0;
    let mut small_count: u64 = 0;
    for (file_name, entry) in files {
        let meta = match entry.metadata() {
            Ok(m) => m,
            Err(_) => {
                ctx.progress.errors.fetch_add(1, Ordering::Relaxed);
                continue;
            }
        };
        // `size`/`logical` are only reassigned by the Unix-only hardlink dedup.
        #[cfg_attr(not(unix), allow(unused_mut))]
        let mut size = allocated_size(&meta);
        #[cfg_attr(not(unix), allow(unused_mut))]
        let mut logical = meta.len();
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            if meta.nlink() > 1 {
                let key = (meta.dev(), meta.ino());
                if !ctx.hardlinks.lock().unwrap().insert(key) {
                    size = 0; // already counted through another link
                    logical = 0;
                }
            }
        }
        ctx.progress.files.fetch_add(1, Ordering::Relaxed);
        ctx.progress.bytes.fetch_add(size, Ordering::Relaxed);
        node.file_count += 1;
        if size >= SMALL_FILE_THRESHOLD {
            node.children.push(TmpNode {
                name: file_name,
                kind: NodeKind::File,
                size,
                logical_size: logical,
                mtime: mtime_of(&meta),
                file_count: 1,
                dir_count: 0,
                item_count: 0,
                rule: None,
                children: Vec::new(),
            });
        } else {
            small_sum += size;
            small_logical += logical;
            small_count += 1;
        }
    }
    if small_count > 0 {
        node.children.push(TmpNode {
            name: String::from("(small files)"),
            kind: NodeKind::SmallFiles,
            size: small_sum,
            logical_size: small_logical,
            mtime: 0,
            file_count: small_count,
            dir_count: 0,
            item_count: small_count,
            rule: None,
            children: Vec::new(),
        });
    }

    let mut sub: Vec<TmpNode> = dirs
        .into_par_iter()
        .zip(dir_rules.into_par_iter())
        .map(|((dir_name, dir_path, dir_mtime), r)| {
            walk(
                &dir_path,
                dir_name,
                dir_mtime,
                r,
                matched_here || r.is_some(),
                depth + 1,
                ctx,
            )
        })
        .collect();
    for s in &sub {
        node.dir_count += 1 + s.dir_count;
        node.file_count += s.file_count;
    }
    node.children.append(&mut sub);
    node.size = node.children.iter().map(|c| c.size).sum();
    node.logical_size = node.children.iter().map(|c| c.logical_size).sum();
    ctx.progress.dirs.fetch_add(1, Ordering::Relaxed);
    node
}

/// Flatten the temporary tree into the id-indexed arena. Iterative (explicit
/// heap stack) so a deep tree can't overflow the native stack — the recursive
/// version was the most likely overflow site. Produces the same DFS pre-order
/// ids and size-descending child ordering as before: each node's whole subtree
/// is numbered before its next sibling, largest child first. Returns the root
/// id (always 0, since the root is pushed first).
fn flatten(root: TmpNode, nodes: &mut Vec<Node>) -> u32 {
    let mut root_id = 0;
    // (node, parent id). Children are pushed largest-last so the largest is
    // popped (and numbered) first — matching the old recursive order.
    let mut stack: Vec<(TmpNode, Option<u32>)> = vec![(root, None)];
    while let Some((mut tmp, parent)) = stack.pop() {
        let id = nodes.len() as u32;
        tmp.children.sort_by_key(|c| std::cmp::Reverse(c.size));
        nodes.push(Node {
            name: tmp.name,
            kind: tmp.kind,
            size: tmp.size,
            logical_size: tmp.logical_size,
            mtime: tmp.mtime,
            parent,
            children: Vec::new(),
            file_count: tmp.file_count,
            dir_count: tmp.dir_count,
            item_count: tmp.item_count,
            rule: tmp.rule,
            tier: Tier::None,
        });
        match parent {
            Some(p) => nodes[p as usize].children.push(id),
            None => root_id = id,
        }
        let children = std::mem::take(&mut tmp.children);
        for child in children.into_iter().rev() {
            stack.push((child, Some(id)));
        }
    }
    root_id
}

/// Post-passes that need full paths: home-relative rule matching, tier
/// assignment, and the protected denylist (which overrides everything).
fn finalize(store: &mut ScanStore) {
    let home = dirs::home_dir();

    // Home-relative rules (caches at fixed locations).
    if let Some(home) = &home {
        let rules: Vec<(u16, String)> = store
            .rules
            .home_path_rules()
            .map(|(i, p)| (i, p.to_string()))
            .collect();
        for (rule_idx, rel) in rules {
            let target = home.join(rel.replace('/', std::path::MAIN_SEPARATOR_STR));
            if let Ok(remainder) = target.strip_prefix(&store.root_path) {
                let mut cur = store.root;
                let mut found = true;
                for comp in remainder.components() {
                    let want = comp.as_os_str().to_string_lossy();
                    let next = store.nodes[cur as usize]
                        .children
                        .iter()
                        .copied()
                        .find(|&c| store.nodes[c as usize].name == want);
                    match next {
                        Some(n) => cur = n,
                        None => {
                            found = false;
                            break;
                        }
                    }
                }
                if found && cur != store.root && store.nodes[cur as usize].rule.is_none() {
                    store.nodes[cur as usize].rule = Some(rule_idx);
                }
            }
        }
    }

    // Tier from rules, then protected pass (DFS with path building).
    for i in 0..store.nodes.len() {
        if let Some(r) = store.nodes[i].rule {
            store.nodes[i].tier = match store.rules.rules[r as usize].regenerability {
                Regenerability::Regenerable | Regenerability::Cache => Tier::Safe,
                Regenerability::Review => Tier::Review,
            };
        }
    }
    let mut stack: Vec<(u32, PathBuf, bool)> = vec![(store.root, store.root_path.clone(), false)];
    while let Some((id, path, parent_protected)) = stack.pop() {
        let is_protected =
            parent_protected || safety::protected_reason(&path, home.as_deref()).is_some();
        if is_protected {
            store.nodes[id as usize].tier = Tier::Protected;
        }
        // Index-based so the children list isn't cloned per node just to
        // appease the borrow checker while child tiers are written.
        for ci in 0..store.nodes[id as usize].children.len() {
            let c = store.nodes[id as usize].children[ci];
            let child = &store.nodes[c as usize];
            if child.kind == NodeKind::Dir {
                let child_path = path.join(&child.name);
                stack.push((c, child_path, is_protected));
            } else if is_protected {
                store.nodes[c as usize].tier = Tier::Protected;
            }
        }
    }
}

fn mtime_of(meta: &fs::Metadata) -> i64 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Size actually allocated on disk. On APFS, clones and sparse files make the
/// logical length misleading, so prefer the block count where available.
#[cfg(unix)]
fn allocated_size(meta: &fs::Metadata) -> u64 {
    use std::os::unix::fs::MetadataExt;
    meta.blocks() * 512
}

#[cfg(not(unix))]
fn allocated_size(meta: &fs::Metadata) -> u64 {
    meta.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn scan_fixture(root: &Path) -> ScanStore {
        let progress = ProgressCounters::default();
        scan(root, RuleSet::builtin(), &progress)
    }

    fn write_bytes(path: &Path, n: usize) {
        fs::write(path, vec![0u8; n]).unwrap();
    }

    #[test]
    fn builds_tree_with_folded_small_files() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir(root.join("big")).unwrap();
        write_bytes(&root.join("big/large.bin"), 2_000_000);
        write_bytes(&root.join("big/tiny1.txt"), 10);
        write_bytes(&root.join("big/tiny2.txt"), 10);

        let store = scan_fixture(root);
        let root_node = store.node(store.root).unwrap();
        assert_eq!(root_node.kind, NodeKind::Dir);
        assert_eq!(root_node.file_count, 3);

        let big = *root_node.children.first().unwrap();
        let big_node = store.node(big).unwrap();
        assert_eq!(big_node.name, "big");
        // children: large.bin + (small files); sorted by size desc
        assert_eq!(big_node.children.len(), 2);
        let first = store.node(big_node.children[0]).unwrap();
        assert_eq!(first.name, "large.bin");
        assert!(first.size >= 2_000_000);
        let small = store.node(big_node.children[1]).unwrap();
        assert_eq!(small.kind, NodeKind::SmallFiles);
        assert_eq!(small.item_count, 2);
        assert_eq!(
            store.path_of(big_node.children[0]),
            root.join("big/large.bin")
        );
    }

    #[test]
    fn matches_node_modules_rule_and_suppresses_nested() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        let proj = root.join("myapp");
        fs::create_dir_all(proj.join("node_modules/dep/node_modules/inner")).unwrap();
        fs::write(proj.join("package.json"), "{}").unwrap();
        fs::write(proj.join("node_modules/dep/package.json"), "{}").unwrap();
        write_bytes(&proj.join("node_modules/dep/big.js"), 1_500_000);

        let store = scan_fixture(root);
        let matched: Vec<&Node> = store.nodes.iter().filter(|n| n.rule.is_some()).collect();
        assert_eq!(
            matched.len(),
            1,
            "nested node_modules must not double-match"
        );
        assert_eq!(matched[0].name, "node_modules");
        assert_eq!(matched[0].tier, Tier::Safe);
    }

    /// Wall-time probe against a real tree; not part of the normal suite.
    /// Run: SCAN_BENCH_ROOT=$HOME cargo test --release -- --ignored --nocapture scan_bench
    #[test]
    #[ignore]
    fn scan_bench() {
        let root = std::env::var("SCAN_BENCH_ROOT").expect("set SCAN_BENCH_ROOT to a directory");
        let start = std::time::Instant::now();
        let store = scan(
            Path::new(&root),
            RuleSet::builtin(),
            &ProgressCounters::default(),
        );
        let elapsed = start.elapsed();
        let root_node = &store.nodes[store.root as usize];
        println!(
            "scanned {} files / {} dirs -> {} nodes in {:?}",
            root_node.file_count,
            root_node.dir_count,
            store.nodes.len(),
            elapsed
        );
    }

    #[test]
    fn directory_named_sibling_marker_still_matches() {
        // Sibling markers can be directories, not just files; the lazily
        // built sibling set must include both.
        use crate::rules::{MatchSpec, Regenerability, Rule, RuleSet};
        let rule = Rule {
            id: "test-dir-sibling".into(),
            name: "Test".into(),
            category: "test".into(),
            regenerability: Regenerability::Cache,
            regenerate_with: None,
            explanation: "test".into(),
            platforms: None,
            matcher: MatchSpec {
                dir_name: Some("cachedir".into()),
                siblings: vec!["marker.d".into()],
                home_path: None,
            },
        };
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir_all(root.join("proj/cachedir")).unwrap();
        fs::create_dir_all(root.join("proj/marker.d")).unwrap();
        write_bytes(&root.join("proj/cachedir/blob.bin"), 1_200_000);
        fs::create_dir_all(root.join("other/cachedir")).unwrap();
        write_bytes(&root.join("other/cachedir/blob.bin"), 1_200_000);

        let store = scan(
            root,
            RuleSet::from_rules(vec![rule]),
            &ProgressCounters::default(),
        );
        let matched: Vec<&Node> = store.nodes.iter().filter(|n| n.rule.is_some()).collect();
        assert_eq!(matched.len(), 1, "only the marked sibling may match");
        assert_eq!(
            store.path_of(store.nodes.iter().position(|n| n.rule.is_some()).unwrap() as u32),
            root.join("proj/cachedir")
        );
    }

    #[test]
    fn target_without_cargo_toml_not_matched() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir_all(root.join("photos/target")).unwrap();
        write_bytes(&root.join("photos/target/img.raw"), 1_200_000);

        let store = scan_fixture(root);
        assert!(store.nodes.iter().all(|n| n.rule.is_none()));
    }

    #[test]
    fn cancel_returns_partial_tree() {
        let tmp = tempfile::tempdir().unwrap();
        let progress = ProgressCounters::default();
        progress.cancel.store(true, Ordering::Relaxed);
        let store = scan(tmp.path(), RuleSet::builtin(), &progress);
        // Cancelled before any work happened: still get a usable (empty) root.
        let root_node = store.node(store.root).unwrap();
        assert_eq!(root_node.kind, NodeKind::Dir);
    }

    #[test]
    #[cfg(unix)]
    fn hardlinks_counted_once() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        write_bytes(&root.join("a.bin"), 3_000_000);
        fs::hard_link(root.join("a.bin"), root.join("b.bin")).unwrap();

        let store = scan_fixture(root);
        let root_node = store.node(store.root).unwrap();
        assert!(root_node.size < 6_000_000, "hardlinked file double-counted");
    }

    #[test]
    fn logical_size_tracked_alongside_allocated() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        write_bytes(&root.join("big.bin"), 2_000_000);
        let store = scan_fixture(root);
        let big = store
            .nodes
            .iter()
            .find(|n| n.name == "big.bin")
            .expect("big file present");
        // Logical is exactly the bytes written; allocated is block-rounded and
        // at least as large. Both must be populated (non-zero).
        assert_eq!(big.logical_size, 2_000_000);
        assert!(big.size >= big.logical_size);
        let root_node = store.node(store.root).unwrap();
        assert!(root_node.logical_size >= 2_000_000);
    }

    #[test]
    fn flatten_handles_deep_tree_without_overflow() {
        // A 50k-deep chain would blow a recursive flatten's native stack; the
        // iterative flatten must handle it. (The filesystem's own PATH_MAX caps
        // how deep a *real* scanned tree can get, so this exercises the arena
        // builder directly with a synthetic tree.)
        const DEPTH: usize = 50_000;
        let mut node = TmpNode::dir("leaf".into(), 0, None);
        node.size = 1_500_000;
        node.logical_size = 1_400_000;
        for i in 0..DEPTH {
            let mut parent = TmpNode::dir(format!("d{i}"), 0, None);
            parent.size = node.size;
            parent.logical_size = node.logical_size;
            parent.children.push(node);
            node = parent;
        }

        let mut nodes = Vec::new();
        let root_id = flatten(node, &mut nodes);
        assert_eq!(root_id, 0);
        assert_eq!(nodes.len(), DEPTH + 1);
        assert_eq!(nodes[0].size, 1_500_000);
        assert_eq!(nodes[0].logical_size, 1_400_000);
        // The last node has no children; every other has exactly one.
        assert!(nodes.last().unwrap().children.is_empty());
        assert_eq!(nodes[0].children.len(), 1);
    }

    #[test]
    #[cfg(unix)]
    fn unreadable_dir_is_itemized_as_skipped() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        let locked = root.join("secret");
        fs::create_dir(&locked).unwrap();
        write_bytes(&locked.join("x.bin"), 1_500_000);
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o000)).unwrap();

        let store = scan_fixture(root);
        // Restore perms so tempdir cleanup works regardless of the assertions.
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).unwrap();

        assert!(store.errors >= 1);
        assert!(
            store.skipped.iter().any(|p| p.ends_with("secret")),
            "unreadable dir must be named in skipped, got {:?}",
            store.skipped
        );
    }
}
