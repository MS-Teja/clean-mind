use std::fs;
use std::path::Path;

use crate::safety;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeleteMode {
    /// Recoverable: OS Trash / Recycle Bin. The default everywhere.
    Trash,
    /// Irreversible. Only reachable through an explicit confirmation flow.
    Permanent,
}

#[derive(Debug)]
pub struct Outcome {
    pub path: String,
    pub ok: bool,
    pub message: Option<String>,
}

/// Delete `paths`, re-checking the protected denylist per item. One item
/// failing never aborts the rest.
pub fn delete_paths(paths: &[&Path], mode: DeleteMode) -> Vec<Outcome> {
    let home = dirs::home_dir();
    paths
        .iter()
        .map(|path| {
            let display = path.to_string_lossy().into_owned();
            if let Some(reason) = safety::deletion_blocked_reason(path, home.as_deref()) {
                return Outcome {
                    path: display,
                    ok: false,
                    message: Some(format!("Refused: {reason}")),
                };
            }
            if !path.exists() && fs::symlink_metadata(path).is_err() {
                return Outcome {
                    path: display,
                    ok: false,
                    message: Some("No longer exists.".into()),
                };
            }
            let result = match mode {
                DeleteMode::Trash => trash::delete(path).map_err(|e| e.to_string()),
                DeleteMode::Permanent => {
                    let meta = fs::symlink_metadata(path).map_err(|e| e.to_string());
                    meta.and_then(|m| {
                        if m.is_dir() {
                            fs::remove_dir_all(path).map_err(|e| e.to_string())
                        } else {
                            fs::remove_file(path).map_err(|e| e.to_string())
                        }
                    })
                }
            };
            match result {
                Ok(()) => Outcome {
                    path: display,
                    ok: true,
                    message: None,
                },
                Err(e) => Outcome {
                    path: display,
                    ok: false,
                    message: Some(e),
                },
            }
        })
        .collect()
}

/// Show the item in Finder / Files / Explorer.
pub fn reveal(path: &Path) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let mut cmd = {
        let mut c = std::process::Command::new("open");
        c.arg("-R").arg(path);
        c
    };
    #[cfg(target_os = "windows")]
    let mut cmd = {
        let mut c = std::process::Command::new("explorer");
        c.arg(format!("/select,{}", path.display()));
        c
    };
    #[cfg(all(unix, not(target_os = "macos")))]
    let mut cmd = {
        let mut c = std::process::Command::new("xdg-open");
        c.arg(path.parent().unwrap_or(path));
        c
    };
    cmd.spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_protected_paths_in_both_modes() {
        let home = dirs::home_dir().unwrap();
        let docs = home.join("Documents");
        for mode in [DeleteMode::Trash, DeleteMode::Permanent] {
            let out = delete_paths(&[docs.as_path()], mode);
            assert!(!out[0].ok);
            assert!(out[0].message.as_ref().unwrap().starts_with("Refused"));
        }
    }

    #[test]
    fn reports_missing_paths() {
        let out = delete_paths(
            &[Path::new("/definitely/not/real/xyz")],
            DeleteMode::Permanent,
        );
        assert!(!out[0].ok);
    }

    #[test]
    fn permanent_delete_removes_fixture() {
        let tmp = tempfile::tempdir().unwrap();
        let victim = tmp.path().join("junk");
        fs::create_dir(&victim).unwrap();
        fs::write(victim.join("f.txt"), "x").unwrap();
        let out = delete_paths(&[victim.as_path()], DeleteMode::Permanent);
        assert!(out[0].ok, "{:?}", out[0].message);
        assert!(!victim.exists());
    }

    #[test]
    #[ignore = "moves a real file to the OS trash; run manually"]
    fn trash_roundtrip() {
        let tmp = tempfile::tempdir().unwrap();
        let victim = tmp.path().join("trash-me.txt");
        fs::write(&victim, "x").unwrap();
        let out = delete_paths(&[victim.as_path()], DeleteMode::Trash);
        assert!(out[0].ok, "{:?}", out[0].message);
        assert!(!victim.exists());
    }
}
