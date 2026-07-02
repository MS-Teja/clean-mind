use std::path::Path;

/// Home-relative locations that are never suggested and never deletable
/// through this app, regardless of what any rule or LLM says.
const PROTECTED_HOME_DIRS: &[&str] = &[
    "Documents",
    "Desktop",
    "Pictures",
    "Movies",
    "Music",
    "Photos",
    ".ssh",
    ".gnupg",
    "OneDrive",
    "iCloud Drive (Archive)",
];

const PROTECTED_HOME_SUBPATHS: &[&[&str]] = &[
    &["Library", "Keychains"],
    &["Library", "Mail"],
    &["Library", "Messages"],
    &["Library", "Application Support", "MobileSync"],
    &["AppData", "Roaming", "Microsoft", "Credentials"],
];

/// Absolute prefixes that are OS or application territory.
#[cfg(target_os = "macos")]
const PROTECTED_SYSTEM_PREFIXES: &[&str] = &[
    "/System",
    "/Library",
    "/Applications",
    "/usr",
    "/bin",
    "/sbin",
    "/private/etc",
    "/private/var/db",
    "/etc",
];

#[cfg(target_os = "linux")]
const PROTECTED_SYSTEM_PREFIXES: &[&str] = &[
    "/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/boot", "/opt", "/var/lib", "/snap",
];

#[cfg(target_os = "windows")]
const PROTECTED_SYSTEM_PREFIXES: &[&str] = &[
    "c:\\windows",
    "c:\\program files",
    "c:\\program files (x86)",
    "c:\\programdata\\microsoft",
];

/// Why `path` must not be deleted, or `None` if it is fair game.
/// This is the single choke point: the scanner uses it to tier nodes and the
/// ops layer re-checks it on every deletion request.
pub fn protected_reason(path: &Path, home: Option<&Path>) -> Option<String> {
    if let Some(home) = home {
        if path == home || home.starts_with(path) {
            return Some("This contains your entire home directory.".into());
        }
        if let Ok(rel) = path.strip_prefix(home) {
            let comps: Vec<String> = rel
                .components()
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect();
            if let Some(first) = comps.first() {
                if PROTECTED_HOME_DIRS.iter().any(|d| d == first) {
                    return Some(format!(
                        "~/{first} holds personal data Clean Mind never touches."
                    ));
                }
            }
            for sub in PROTECTED_HOME_SUBPATHS {
                if comps.len() >= sub.len() && comps.iter().zip(sub.iter()).all(|(a, b)| a == b) {
                    return Some(format!(
                        "~/{} holds keys, messages, or backups.",
                        sub.join("/")
                    ));
                }
            }
        }
    }

    // Photo libraries and app bundles, wherever they live.
    let name = path.file_name().map(|n| n.to_string_lossy().to_lowercase());
    if let Some(name) = &name {
        if name.ends_with(".photoslibrary") {
            return Some("This is a Photos library.".into());
        }
        if name.ends_with(".app") {
            return Some("This is an installed application bundle.".into());
        }
    }

    let display = path.to_string_lossy();
    #[cfg(target_os = "windows")]
    let display = display.to_lowercase();
    for prefix in PROTECTED_SYSTEM_PREFIXES {
        if display.starts_with(prefix)
            && (display.len() == prefix.len()
                || display.as_bytes()[prefix.len()] == std::path::MAIN_SEPARATOR as u8)
        {
            return Some("This is operating-system or application territory.".into());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn home() -> PathBuf {
        if cfg!(windows) {
            PathBuf::from("C:\\Users\\tester")
        } else {
            PathBuf::from("/Users/tester")
        }
    }

    #[test]
    fn home_and_ancestors_protected() {
        let h = home();
        assert!(protected_reason(&h, Some(&h)).is_some());
        assert!(protected_reason(h.parent().unwrap(), Some(&h)).is_some());
    }

    #[test]
    fn personal_dirs_protected() {
        let h = home();
        assert!(protected_reason(&h.join("Documents"), Some(&h)).is_some());
        assert!(protected_reason(&h.join("Documents/taxes/2025"), Some(&h)).is_some());
        assert!(protected_reason(&h.join(".ssh"), Some(&h)).is_some());
        assert!(protected_reason(&h.join("Pictures/wedding"), Some(&h)).is_some());
    }

    #[test]
    fn dev_dirs_not_protected() {
        let h = home();
        assert!(protected_reason(&h.join("Development/app/node_modules"), Some(&h)).is_none());
        assert!(protected_reason(&h.join(".npm/_cacache"), Some(&h)).is_none());
        assert!(protected_reason(&h.join("Library/Caches/Homebrew"), Some(&h)).is_none());
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn system_paths_protected() {
        let h = home();
        assert!(protected_reason(Path::new("/System/Library"), Some(&h)).is_some());
        assert!(protected_reason(Path::new("/Applications/Safari.app"), Some(&h)).is_some());
        // ...but a similarly-named user dir is fine.
        assert!(protected_reason(&h.join("Systematics"), Some(&h)).is_none());
    }

    #[test]
    fn photo_library_and_app_bundles_protected_anywhere() {
        let h = home();
        assert!(protected_reason(&h.join("Backups/old.photoslibrary"), Some(&h)).is_some());
        assert!(protected_reason(&h.join("tools/MyTool.app"), Some(&h)).is_some());
    }
}
