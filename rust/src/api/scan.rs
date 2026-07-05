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
    pub size: i64,
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
        path: store.path_of(id).to_string_lossy().into_owned(),
        kind: match node.kind {
            NodeKind::Dir => FsKind::Dir,
            NodeKind::File => FsKind::File,
            NodeKind::SmallFiles => FsKind::SmallFiles,
        },
        size: node.size as i64,
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
        out.push(FsNode {
            id: -1,
            name: format!("{} more items", rest.len()),
            path: String::new(),
            kind: FsKind::Rest,
            size: rest_size as i64,
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

/// Remember the picked scan root for the next launch.
#[flutter_rust_bridge::frb(sync)]
pub fn set_scan_root(path: String) {
    let mut settings = crate::config::load();
    settings.scan_root = Some(path);
    let _ = crate::config::save(&settings);
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
