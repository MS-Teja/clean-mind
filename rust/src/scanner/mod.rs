use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

/// Aggregate result of walking a directory tree.
#[derive(Debug, Clone, Default)]
pub struct ScanTotals {
    pub files: u64,
    pub dirs: u64,
    /// Allocated size on disk where the platform reports it (Unix); logical size otherwise.
    pub total_bytes: u64,
    /// Entries that could not be read (permissions, races). Scanning never aborts on these.
    pub errors: u64,
}

/// Walk `root` in parallel and aggregate counts and sizes.
///
/// Symlinks are counted but never followed, so a cycle cannot occur and
/// sizes are not double-counted through links.
pub fn scan_summary(root: &Path) -> ScanTotals {
    let files = AtomicU64::new(0);
    let dirs = AtomicU64::new(0);
    let total_bytes = AtomicU64::new(0);
    let errors = AtomicU64::new(0);

    for entry in jwalk::WalkDir::new(root)
        .follow_links(false)
        .skip_hidden(false)
    {
        match entry {
            Ok(entry) => {
                let file_type = entry.file_type();
                if file_type.is_dir() {
                    dirs.fetch_add(1, Ordering::Relaxed);
                } else {
                    files.fetch_add(1, Ordering::Relaxed);
                    match entry.metadata() {
                        Ok(meta) => {
                            total_bytes.fetch_add(allocated_size(&meta), Ordering::Relaxed);
                        }
                        Err(_) => {
                            errors.fetch_add(1, Ordering::Relaxed);
                        }
                    }
                }
            }
            Err(_) => {
                errors.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    ScanTotals {
        files: files.load(Ordering::Relaxed),
        dirs: dirs.load(Ordering::Relaxed),
        total_bytes: total_bytes.load(Ordering::Relaxed),
        errors: errors.load(Ordering::Relaxed),
    }
}

/// Size actually allocated on disk. On APFS, clones and sparse files make the
/// logical length misleading, so prefer the block count where available.
#[cfg(unix)]
fn allocated_size(meta: &std::fs::Metadata) -> u64 {
    use std::os::unix::fs::MetadataExt;
    meta.blocks() * 512
}

#[cfg(not(unix))]
fn allocated_size(meta: &std::fs::Metadata) -> u64 {
    meta.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn counts_files_dirs_and_bytes() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir(root.join("a")).unwrap();
        fs::create_dir(root.join("a/b")).unwrap();
        fs::write(root.join("a/one.txt"), vec![0u8; 4096]).unwrap();
        fs::write(root.join("a/b/two.txt"), vec![0u8; 4096]).unwrap();

        let summary = scan_summary(root);
        assert_eq!(summary.files, 2);
        // root + a + a/b
        assert_eq!(summary.dirs, 3);
        assert!(summary.total_bytes >= 8192);
        assert_eq!(summary.errors, 0);
    }

    #[test]
    fn does_not_follow_symlinks() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir(root.join("real")).unwrap();
        fs::write(root.join("real/data.bin"), vec![0u8; 4096]).unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(root.join("real"), root.join("link")).unwrap();

        let summary = scan_summary(root);
        // data.bin counted once; the symlink itself counts as a file entry, not a dir.
        #[cfg(unix)]
        assert_eq!(summary.files, 2);
        #[cfg(unix)]
        assert_eq!(summary.dirs, 2);
    }

    #[test]
    fn missing_root_reports_error_not_panic() {
        let summary = scan_summary(Path::new("/definitely/not/a/real/path"));
        assert_eq!(summary.files, 0);
        assert_eq!(summary.errors, 1);
    }
}
