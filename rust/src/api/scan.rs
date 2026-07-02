use std::path::PathBuf;

use crate::scanner;

/// Aggregate result of a scan, mirrored into Dart by flutter_rust_bridge.
pub struct ScanSummary {
    pub files: u64,
    pub dirs: u64,
    pub total_bytes: u64,
    pub errors: u64,
}

impl From<scanner::ScanTotals> for ScanSummary {
    fn from(s: scanner::ScanTotals) -> Self {
        Self {
            files: s.files,
            dirs: s.dirs,
            total_bytes: s.total_bytes,
            errors: s.errors,
        }
    }
}

/// Scan a directory tree and return aggregate counts and allocated size.
/// Runs on a worker thread; the UI thread is never blocked.
pub async fn scan_summary(path: String) -> ScanSummary {
    let root = PathBuf::from(path);
    flutter_rust_bridge::spawn_blocking_with(
        move || scanner::scan_summary(&root).into(),
        crate::frb_generated::FLUTTER_RUST_BRIDGE_HANDLER.thread_pool(),
    )
    .await
    .expect("scan worker thread panicked")
}

/// Home directory of the current user, the default scan root.
#[flutter_rust_bridge::frb(sync)]
pub fn default_scan_root() -> String {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/"))
        .to_string_lossy()
        .into_owned()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
