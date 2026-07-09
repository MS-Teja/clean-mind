use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::mpsc::RecvTimeoutError;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use crate::frb_generated::StreamSink;
use crate::rules::RuleSet;
use crate::scanner::{self, NodeKind, ProgressCounters, Tier, STORE};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScanStage {
    Scanning,
    Done,
    Cancelled,
    Failed,
}

pub struct ScanProgress {
    pub stage: ScanStage,
    pub files: i64,
    pub dirs: i64,
    pub bytes: i64,
    pub errors: i64,
    pub current_path: String,
    /// Root node id, valid only when `stage == Done`.
    pub root_id: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FsKind {
    Dir,
    File,
    /// Aggregate of one directory's files below the detail threshold.
    SmallFiles,
    /// Aggregate tail of children beyond the requested limit.
    Rest,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FsTier {
    None,
    Safe,
    Review,
    Protected,
}

pub struct FsNode {
    pub id: i64,
    pub name: String,
    pub path: String,
    pub kind: FsKind,
    /// On-disk (allocated) size.
    pub size: i64,
    /// Apparent (logical) size; differs from `size` for clones/sparse files.
    pub logical_size: i64,
    pub mtime: i64,
    pub file_count: i64,
    pub dir_count: i64,
    pub item_count: i64,
    pub child_count: i64,
    pub tier: FsTier,
    pub rule_id: Option<String>,
    pub rule_name: Option<String>,
    pub category: Option<String>,
}

static CURRENT_SCAN: Mutex<Option<Arc<ProgressCounters>>> = Mutex::new(None);

fn snapshot(progress: &ProgressCounters, stage: ScanStage, root_id: i64) -> ScanProgress {
    ScanProgress {
        stage,
        files: progress.files.load(Ordering::Relaxed) as i64,
        dirs: progress.dirs.load(Ordering::Relaxed) as i64,
        bytes: progress.bytes.load(Ordering::Relaxed) as i64,
        errors: progress.errors.load(Ordering::Relaxed) as i64,
        current_path: progress
            .current
            .lock()
            .map(|s| s.clone())
            .unwrap_or_default(),
        root_id,
    }
}

/// Start a scan. Progress streams every ~120ms; the final item carries
/// `stage: Done` (with the root id) / `Cancelled` (with root id >= 0 if
/// partial results are available, -1 if this scan was superseded before it
/// could publish anything) / `Failed`.
pub fn start_scan(path: String, sink: StreamSink<ScanProgress>) -> Result<(), String> {
    let progress = Arc::new(ProgressCounters::default());
    {
        let mut current = CURRENT_SCAN.lock().unwrap();
        // Cancel any scan still running; last request wins.
        if let Some(prev) = current.as_ref() {
            prev.cancel.store(true, Ordering::Relaxed);
        }
        *current = Some(progress.clone());
    }
    *STORE.write().unwrap() = None;

    thread::spawn(move || {
        let root = PathBuf::from(&path);
        let (tx, rx) = std::sync::mpsc::channel();
        let scan_progress = progress.clone();
        let scan_thread = thread::spawn(move || {
            let result = scanner::scan(&root, RuleSet::builtin(), &scan_progress);
            let _ = tx.send(result);
        });
        loop {
            match rx.recv_timeout(Duration::from_millis(120)) {
                Ok(store) => {
                    let cancelled = progress.cancel.load(Ordering::Relaxed);
                    let root_id = store.root as i64;
                    let is_current = CURRENT_SCAN
                        .lock()
                        .unwrap()
                        .as_ref()
                        .is_some_and(|cur| Arc::ptr_eq(cur, &progress));
                    if is_current {
                        *STORE.write().unwrap() = Some(store);
                        let stage = if cancelled {
                            ScanStage::Cancelled
                        } else {
                            ScanStage::Done
                        };
                        let _ = sink.add(snapshot(&progress, stage, root_id));
                    } else {
                        // Superseded by a newer scan ("last request wins" set
                        // our cancel flag); don't clobber the newer STORE.
                        let _ = sink.add(snapshot(&progress, ScanStage::Cancelled, -1));
                    }
                    break;
                }
                Err(RecvTimeoutError::Timeout) => {
                    let _ = sink.add(snapshot(&progress, ScanStage::Scanning, -1));
                }
                Err(RecvTimeoutError::Disconnected) => {
                    let _ = sink.add(snapshot(&progress, ScanStage::Failed, -1));
                    break;
                }
            }
        }
        let _ = scan_thread.join();
    });
    Ok(())
}

pub fn cancel_scan() {
    if let Some(progress) = CURRENT_SCAN.lock().unwrap().as_ref() {
        progress.cancel.store(true, Ordering::Relaxed);
    }
}

fn to_fs_node(store: &scanner::ScanStore, id: u32) -> FsNode {
    to_fs_node_with_path(store, id, store.path_of(id).to_string_lossy().into_owned())
}

/// Like [`to_fs_node`] for callers that already know the node's path, so it
/// isn't rebuilt by walking parent links.
fn to_fs_node_with_path(store: &scanner::ScanStore, id: u32, path: String) -> FsNode {
    let node = &store.nodes[id as usize];
    let (rule_id, rule_name, category) = match node.rule {
        Some(r) => {
            let rule = store.rules.get(r);
            (
                Some(rule.id.clone()),
                Some(rule.name.clone()),
                Some(rule.category.clone()),
            )
        }
        None => (None, None, None),
    };
    FsNode {
        id: id as i64,
        name: node.name.clone(),
        path,
        kind: match node.kind {
            NodeKind::Dir => FsKind::Dir,
            NodeKind::File => FsKind::File,
            NodeKind::SmallFiles => FsKind::SmallFiles,
        },
        size: node.size as i64,
        logical_size: node.logical_size as i64,
        mtime: node.mtime,
        file_count: node.file_count as i64,
        dir_count: node.dir_count as i64,
        item_count: node.item_count as i64,
        child_count: node.children.len() as i64,
        tier: match node.tier {
            Tier::None => FsTier::None,
            Tier::Safe => FsTier::Safe,
            Tier::Review => FsTier::Review,
            Tier::Protected => FsTier::Protected,
        },
        rule_id,
        rule_name,
        category,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_node(id: i64) -> Option<FsNode> {
    let store = STORE.read().unwrap();
    let store = store.as_ref()?;
    store.node(id as u32)?;
    Some(to_fs_node(store, id as u32))
}

/// Children of `id`, largest first. At most `limit` real entries; anything
/// beyond folds into a trailing `Rest` node so the UI stays bounded.
#[flutter_rust_bridge::frb(sync)]
pub fn get_children(id: i64, limit: i64) -> Vec<FsNode> {
    let store = STORE.read().unwrap();
    let Some(store) = store.as_ref() else {
        return Vec::new();
    };
    let Some(node) = store.node(id as u32) else {
        return Vec::new();
    };
    let limit = limit.max(1) as usize;
    let mut out: Vec<FsNode> = node
        .children
        .iter()
        .take(limit)
        .map(|&c| to_fs_node(store, c))
        .collect();
    if node.children.len() > limit {
        let rest = &node.children[limit..];
        let rest_size: u64 = rest.iter().map(|&c| store.nodes[c as usize].size).sum();
        let rest_logical: u64 = rest
            .iter()
            .map(|&c| store.nodes[c as usize].logical_size)
            .sum();
        out.push(FsNode {
            id: -1,
            name: format!("{} more items", rest.len()),
            path: String::new(),
            kind: FsKind::Rest,
            size: rest_size as i64,
            logical_size: rest_logical as i64,
            mtime: 0,
            file_count: 0,
            dir_count: 0,
            item_count: rest.len() as i64,
            child_count: 0,
            tier: FsTier::None,
            rule_id: None,
            rule_name: None,
            category: None,
        });
    }
    out
}

/// How to order children in [`get_children_sorted`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortKey {
    Size,
    Name,
    Items,
}

/// Children of `id` sorted by `key` (descending unless `ascending`), for the
/// list/table view. Like [`get_children`], anything past `limit` folds into a
/// trailing `Rest` node so the UI stays bounded.
#[flutter_rust_bridge::frb(sync)]
pub fn get_children_sorted(id: i64, key: SortKey, ascending: bool, limit: i64) -> Vec<FsNode> {
    let store = STORE.read().unwrap();
    let Some(store) = store.as_ref() else {
        return Vec::new();
    };
    let Some(node) = store.node(id as u32) else {
        return Vec::new();
    };
    let ids = sorted_child_ids(store, node, key, ascending);

    let limit = limit.max(1) as usize;
    let mut out: Vec<FsNode> = ids
        .iter()
        .take(limit)
        .map(|&c| to_fs_node(store, c))
        .collect();
    if ids.len() > limit {
        let rest = &ids[limit..];
        let rest_size: u64 = rest.iter().map(|&c| store.nodes[c as usize].size).sum();
        let rest_logical: u64 = rest
            .iter()
            .map(|&c| store.nodes[c as usize].logical_size)
            .sum();
        out.push(FsNode {
            id: -1,
            name: format!("{} more items", rest.len()),
            path: String::new(),
            kind: FsKind::Rest,
            size: rest_size as i64,
            logical_size: rest_logical as i64,
            mtime: 0,
            file_count: 0,
            dir_count: 0,
            item_count: rest.len() as i64,
            child_count: 0,
            tier: FsTier::None,
            rule_id: None,
            rule_name: None,
            category: None,
        });
    }
    out
}

fn sorted_child_ids(
    store: &scanner::ScanStore,
    node: &scanner::Node,
    key: SortKey,
    ascending: bool,
) -> Vec<u32> {
    let mut ids: Vec<u32> = node.children.clone();
    if key == SortKey::Name {
        // Lowercase once per child, not twice per comparison.
        let mut keyed: Vec<(String, u32)> = ids
            .iter()
            .map(|&c| (store.nodes[c as usize].name.to_lowercase(), c))
            .collect();
        keyed.sort_by(|a, b| {
            let ord = a.0.cmp(&b.0);
            if ascending {
                ord
            } else {
                ord.reverse()
            }
        });
        ids = keyed.into_iter().map(|(_, c)| c).collect();
    } else {
        ids.sort_by(|&a, &b| {
            let (na, nb) = (&store.nodes[a as usize], &store.nodes[b as usize]);
            let ord = match key {
                SortKey::Size => na.size.cmp(&nb.size),
                SortKey::Items => {
                    (na.file_count + na.dir_count).cmp(&(nb.file_count + nb.dir_count))
                }
                SortKey::Name => unreachable!("handled above"),
            };
            if ascending {
                ord
            } else {
                ord.reverse()
            }
        });
    }
    ids
}

/// Search the whole scan for nodes whose name contains `query`
/// (case-insensitive), largest first, capped at `limit`. Linear over the flat
/// arena — cheap even for a home-directory scan. The root and the synthetic
/// "(small files)" aggregates are excluded.
#[flutter_rust_bridge::frb(sync)]
pub fn search_nodes(query: String, limit: i64) -> Vec<FsNode> {
    let store = STORE.read().unwrap();
    let Some(store) = store.as_ref() else {
        return Vec::new();
    };
    search_hits(store, &query, limit.max(1) as usize)
        .iter()
        .map(|&i| to_fs_node(store, i))
        .collect()
}

fn search_hits(store: &scanner::ScanStore, query: &str, limit: usize) -> Vec<u32> {
    let needle = query.trim().to_lowercase();
    if needle.is_empty() {
        return Vec::new();
    }
    let lower = store
        .lower_names
        .get_or_init(|| store.nodes.iter().map(|n| n.name.to_lowercase()).collect());
    let mut hits: Vec<u32> = store
        .nodes
        .iter()
        .enumerate()
        .filter(|(i, n)| {
            *i as u32 != store.root && n.kind != NodeKind::SmallFiles && lower[*i].contains(&needle)
        })
        .map(|(i, _)| i as u32)
        .collect();
    hits.sort_by_key(|&i| std::cmp::Reverse(store.nodes[i as usize].size));
    hits.truncate(limit);
    hits
}

/// Ancestry chain from the root down to `id`, inclusive (root first, `id`
/// last). Lets the UI rebuild the breadcrumb trail when jumping to an arbitrary
/// node (search hit, "largest items" tap). Empty if `id` isn't in the scan.
#[flutter_rust_bridge::frb(sync)]
pub fn node_ancestry(id: i64) -> Vec<FsNode> {
    let store = STORE.read().unwrap();
    let Some(store) = store.as_ref() else {
        return Vec::new();
    };
    if id < 0 || store.node(id as u32).is_none() {
        return Vec::new();
    }
    ancestry_nodes(store, id as u32)
}

fn ancestry_nodes(store: &scanner::ScanStore, id: u32) -> Vec<FsNode> {
    let mut chain = Vec::new();
    let mut cur = Some(id);
    while let Some(i) = cur {
        chain.push(i);
        cur = store.nodes[i as usize].parent;
    }
    chain.reverse();
    // Build each ancestor's path by extending the previous one instead of
    // re-walking parent links per element — O(depth), not O(depth²).
    let mut path = store.root_path.clone();
    chain
        .into_iter()
        .map(|i| {
            if store.nodes[i as usize].parent.is_some() {
                path.push(&store.nodes[i as usize].name);
            }
            to_fs_node_with_path(store, i, path.to_string_lossy().into_owned())
        })
        .collect()
}

/// Paths that couldn't be read during the current scan (permission denied or
/// past the depth guard), itemized and capped. Empty when nothing was skipped.
#[flutter_rust_bridge::frb(sync)]
pub fn scan_skipped_paths() -> Vec<String> {
    let store = STORE.read().unwrap();
    store
        .as_ref()
        .map(|s| s.skipped.clone())
        .unwrap_or_default()
}

/// Home directory of the current user, the fallback scan root.
#[flutter_rust_bridge::frb(sync)]
pub fn home_dir_path() -> String {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/"))
        .to_string_lossy()
        .into_owned()
}

/// Scan root for a fresh launch: the last root the user picked, if it still
/// exists, otherwise the home directory.
#[flutter_rust_bridge::frb(sync)]
pub fn default_scan_root() -> String {
    if let Some(saved) = crate::config::load().scan_root {
        if std::path::Path::new(&saved).is_dir() {
            return saved;
        }
    }
    home_dir_path()
}

/// Remember the picked scan root for the next launch, and add it to the
/// recent-scans list (paths only — never scan data).
#[flutter_rust_bridge::frb(sync)]
pub fn set_scan_root(path: String) {
    let mut settings = crate::config::load();
    settings.push_recent(&path);
    settings.scan_root = Some(path);
    let _ = crate::config::save(&settings);
}

/// Recently-scanned roots, newest first. Paths only; nothing about their
/// contents is persisted. Non-existent paths are filtered out.
#[flutter_rust_bridge::frb(sync)]
pub fn recent_scan_roots() -> Vec<String> {
    crate::config::load()
        .recent_roots
        .into_iter()
        .filter(|p| std::path::Path::new(p).is_dir())
        .collect()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;

    fn scan_dir(root: &Path) -> scanner::ScanStore {
        scanner::scan(root, RuleSet::builtin(), &ProgressCounters::default())
    }

    fn write_bytes(path: &Path, n: usize) {
        fs::write(path, vec![0u8; n]).unwrap();
    }

    fn names_of(store: &scanner::ScanStore, ids: &[u32]) -> Vec<String> {
        ids.iter()
            .map(|&i| store.nodes[i as usize].name.clone())
            .collect()
    }

    #[test]
    fn search_matches_case_insensitively_largest_first() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir(root.join("Alpha")).unwrap();
        write_bytes(&root.join("Alpha/big.bin"), 3_000_000);
        write_bytes(&root.join("alphabet.bin"), 2_000_000);

        let store = scan_dir(root);
        let hits = search_hits(&store, "ALPHA", 10);
        assert_eq!(names_of(&store, &hits), vec!["Alpha", "alphabet.bin"]);
        // Second query hits the cached lowercase index; results are identical.
        assert_eq!(search_hits(&store, "ALPHA", 10), hits);
        assert!(search_hits(&store, "  ", 10).is_empty());
    }

    #[test]
    fn name_sort_is_case_insensitive_both_ways() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        for name in ["beta.bin", "Alpha.bin", "gamma.bin"] {
            write_bytes(&root.join(name), 1_100_000);
        }

        let store = scan_dir(root);
        let node = store.node(store.root).unwrap();
        let asc = sorted_child_ids(&store, node, SortKey::Name, true);
        assert_eq!(
            names_of(&store, &asc),
            vec!["Alpha.bin", "beta.bin", "gamma.bin"]
        );
        let desc = sorted_child_ids(&store, node, SortKey::Name, false);
        assert_eq!(
            names_of(&store, &desc),
            vec!["gamma.bin", "beta.bin", "Alpha.bin"]
        );
    }

    #[test]
    fn ancestry_paths_match_path_of() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir_all(root.join("a/b/c")).unwrap();
        write_bytes(&root.join("a/b/c/big.bin"), 1_500_000);

        let store = scan_dir(root);
        let (leaf, _) = store
            .nodes
            .iter()
            .enumerate()
            .find(|(_, n)| n.name == "big.bin")
            .expect("deep file present");
        let chain = ancestry_nodes(&store, leaf as u32);
        assert_eq!(chain.len(), 5); // root, a, b, c, big.bin
        let mut cur = Some(leaf as u32);
        let mut ids = Vec::new();
        while let Some(i) = cur {
            ids.push(i);
            cur = store.nodes[i as usize].parent;
        }
        ids.reverse();
        for (fs_node, id) in chain.iter().zip(ids) {
            assert_eq!(
                fs_node.path,
                store.path_of(id).to_string_lossy().into_owned()
            );
        }
    }
}
