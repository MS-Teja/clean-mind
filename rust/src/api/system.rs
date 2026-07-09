use std::path::PathBuf;
use std::process::Command;

/// A pickable scan location for the landing screen.
pub struct Location {
    pub label: String,
    pub path: String,
    /// One of: home, desktop, documents, downloads, applications, volume.
    pub kind: String,
    pub exists: bool,
}

fn push_dir(out: &mut Vec<Location>, label: &str, kind: &str, path: Option<PathBuf>) {
    if let Some(p) = path {
        out.push(Location {
            label: label.to_string(),
            exists: p.is_dir(),
            path: p.to_string_lossy().into_owned(),
            kind: kind.to_string(),
        });
    }
}

/// Standard scan locations plus mounted volumes, for the landing screen. Each
/// carries an `exists` flag so the UI can grey out ones that don't apply.
#[flutter_rust_bridge::frb(sync)]
pub fn standard_locations() -> Vec<Location> {
    let mut out = Vec::new();
    push_dir(&mut out, "Home", "home", dirs::home_dir());
    push_dir(&mut out, "Desktop", "desktop", dirs::desktop_dir());
    push_dir(&mut out, "Documents", "documents", dirs::document_dir());
    push_dir(&mut out, "Downloads", "downloads", dirs::download_dir());
    #[cfg(target_os = "macos")]
    push_dir(
        &mut out,
        "Applications",
        "applications",
        Some(PathBuf::from("/Applications")),
    );
    out.extend(mounted_volumes());
    out
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn read_volume_dir(dir: &std::path::Path) -> Vec<Location> {
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() {
                out.push(Location {
                    label: e.file_name().to_string_lossy().into_owned(),
                    path: p.to_string_lossy().into_owned(),
                    kind: "volume".to_string(),
                    exists: true,
                });
            }
        }
    }
    out
}

#[cfg(target_os = "macos")]
fn mounted_volumes() -> Vec<Location> {
    read_volume_dir(std::path::Path::new("/Volumes"))
}

#[cfg(target_os = "linux")]
fn mounted_volumes() -> Vec<Location> {
    let user = std::env::var("USER").unwrap_or_default();
    let mut out = Vec::new();
    for base in [
        format!("/run/media/{user}"),
        format!("/media/{user}"),
        "/media".to_string(),
        "/mnt".to_string(),
    ] {
        out.extend(read_volume_dir(std::path::Path::new(&base)));
    }
    out
}

#[cfg(target_os = "windows")]
fn mounted_volumes() -> Vec<Location> {
    let mut out = Vec::new();
    for c in b'A'..=b'Z' {
        let drive = format!("{}:\\", c as char);
        if std::path::Path::new(&drive).is_dir() {
            out.push(Location {
                label: format!("{}:", c as char),
                path: drive,
                kind: "volume".to_string(),
                exists: true,
            });
        }
    }
    out
}

#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
fn mounted_volumes() -> Vec<Location> {
    Vec::new()
}

/// Whether the app can read macOS TCC-protected locations (Mail, Safari,
/// Messages, …). Without Full Disk Access those directories fail with
/// permission errors and a home/disk scan silently under-reports.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FdaStatus {
    Granted,
    Denied,
    /// No probe location exists (or no home dir) — nothing to conclude.
    NotDetermined,
}

/// Probe a few TCC-protected directories instead of asking the OS: there is
/// no public API to query Full Disk Access, but a successful `read_dir` on
/// any of these proves it, and exists-but-unreadable proves its absence.
#[flutter_rust_bridge::frb(sync)]
pub fn full_disk_access_status() -> FdaStatus {
    #[cfg(target_os = "macos")]
    {
        let Some(home) = dirs::home_dir() else {
            return FdaStatus::NotDetermined;
        };
        let probes = [
            "Library/Application Support/com.apple.TCC",
            "Library/Safari",
            "Library/Mail",
            "Library/Messages",
        ];
        let mut saw_denied = false;
        for probe in probes {
            let path = home.join(probe);
            if std::fs::symlink_metadata(&path).is_err() {
                continue;
            }
            if std::fs::read_dir(&path).is_ok() {
                return FdaStatus::Granted;
            }
            saw_denied = true;
        }
        if saw_denied {
            FdaStatus::Denied
        } else {
            FdaStatus::NotDetermined
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        FdaStatus::Granted
    }
}

/// Jump straight to System Settings → Privacy & Security → Full Disk Access.
/// No-op off macOS.
#[flutter_rust_bridge::frb(sync)]
pub fn open_full_disk_access_settings() {
    #[cfg(target_os = "macos")]
    {
        let _ = Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
            .spawn();
    }
}

/// Open the OS Trash / Recycle Bin so the user can restore trashed items.
#[flutter_rust_bridge::frb(sync)]
pub fn open_trash() {
    #[cfg(target_os = "macos")]
    {
        if let Some(home) = dirs::home_dir() {
            let _ = Command::new("open").arg(home.join(".Trash")).spawn();
        }
    }
    #[cfg(target_os = "windows")]
    {
        let _ = Command::new("explorer")
            .arg("shell:RecycleBinFolder")
            .spawn();
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        // `gio` understands the trash: scheme everywhere GTK runs; xdg-open
        // is the fallback when it's missing.
        if Command::new("gio")
            .args(["open", "trash:///"])
            .spawn()
            .is_err()
        {
            let _ = Command::new("xdg-open").arg("trash:///").spawn();
        }
    }
}

/// Open a web link in the default browser. Only https URLs are accepted so a
/// crafted value can never launch arbitrary local handlers.
#[flutter_rust_bridge::frb(sync)]
pub fn open_url(url: String) {
    if !url.starts_with("https://") {
        return;
    }
    #[cfg(target_os = "macos")]
    let _ = Command::new("open").arg(&url).spawn();
    #[cfg(target_os = "windows")]
    let _ = Command::new("explorer").arg(&url).spawn();
    #[cfg(all(unix, not(target_os = "macos")))]
    let _ = Command::new("xdg-open").arg(&url).spawn();
}

/// UI preferences that survive restarts (persisted in settings.json by the
/// Rust core — never scan data, never secrets).
pub struct UiPrefs {
    /// "treemap" | "list"
    pub results_view: String,
    /// "size" | "name" | "items"
    pub sort_key: String,
    pub sort_ascending: bool,
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_ui_prefs() -> UiPrefs {
    let ui = crate::config::load().ui;
    UiPrefs {
        results_view: ui.results_view,
        sort_key: ui.sort_key,
        sort_ascending: ui.sort_ascending,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_ui_prefs(prefs: UiPrefs) {
    let mut settings = crate::config::load();
    settings.ui = crate::config::UiConfig {
        results_view: prefs.results_view,
        sort_key: prefs.sort_key,
        sort_ascending: prefs.sort_ascending,
    };
    // Best-effort: a failed prefs write should never surface as an error.
    let _ = crate::config::save(&settings);
}

pub struct DiskSpace {
    /// Capacity of the volume holding the queried path, in bytes.
    pub total_bytes: i64,
    /// Bytes available to the current user on that volume.
    pub free_bytes: i64,
}

/// Capacity and free space of the volume containing `path`, or None if the
/// path doesn't resolve to a mounted filesystem.
#[flutter_rust_bridge::frb(sync)]
pub fn disk_space(path: String) -> Option<DiskSpace> {
    volume_space(std::path::Path::new(&path))
}

// statfs, not statvfs, on macOS: statvfs there reports f_bavail in f_frsize
// units inconsistently across FS types; statfs's f_bsize accounting matches
// what Finder and df report.
#[cfg(target_os = "macos")]
fn volume_space(path: &std::path::Path) -> Option<DiskSpace> {
    use std::os::unix::ffi::OsStrExt;
    let c = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut st: libc::statfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statfs(c.as_ptr(), &mut st) } != 0 {
        return None;
    }
    let bsize = st.f_bsize as u64;
    Some(DiskSpace {
        total_bytes: st.f_blocks.saturating_mul(bsize) as i64,
        free_bytes: st.f_bavail.saturating_mul(bsize) as i64,
    })
}

#[cfg(all(unix, not(target_os = "macos")))]
fn volume_space(path: &std::path::Path) -> Option<DiskSpace> {
    use std::os::unix::ffi::OsStrExt;
    let c = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c.as_ptr(), &mut st) } != 0 {
        return None;
    }
    let frsize = st.f_frsize as u64;
    Some(DiskSpace {
        total_bytes: (st.f_blocks as u64).saturating_mul(frsize) as i64,
        free_bytes: (st.f_bavail as u64).saturating_mul(frsize) as i64,
    })
}

#[cfg(windows)]
fn volume_space(path: &std::path::Path) -> Option<DiskSpace> {
    use std::os::windows::ffi::OsStrExt;
    let wide: Vec<u16> = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let mut avail: u64 = 0;
    let mut total: u64 = 0;
    let mut free: u64 = 0;
    let ok = unsafe {
        windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW(
            wide.as_ptr(),
            &mut avail,
            &mut total,
            &mut free,
        )
    };
    if ok == 0 {
        return None;
    }
    Some(DiskSpace {
        total_bytes: total as i64,
        free_bytes: avail as i64,
    })
}

pub struct UpdateCheck {
    pub current: String,
    pub latest: String,
    pub update_available: bool,
    pub release_url: String,
}

/// Ask GitHub for the latest published release. Only ever called from an
/// explicit "Check for updates" action — nothing phones home on its own.
pub async fn check_for_update(current_version: String) -> Result<UpdateCheck, String> {
    flutter_rust_bridge::spawn_blocking_with(
        move || fetch_latest_release(&current_version),
        crate::frb_generated::FLUTTER_RUST_BRIDGE_HANDLER.thread_pool(),
    )
    .await
    .expect("update-check worker panicked")
}

const RELEASES_PAGE: &str = "https://github.com/MS-Teja/clean-mind/releases";

fn fetch_latest_release(current: &str) -> Result<UpdateCheck, String> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| e.to_string())?;
    let response = client
        .get("https://api.github.com/repos/MS-Teja/clean-mind/releases/latest")
        .header(reqwest::header::USER_AGENT, "clean-mind")
        .send()
        .map_err(|e| format!("Could not reach GitHub: {e}"))?;
    if response.status() == reqwest::StatusCode::NOT_FOUND {
        // No release published yet.
        return Ok(UpdateCheck {
            current: current.to_string(),
            latest: current.to_string(),
            update_available: false,
            release_url: RELEASES_PAGE.to_string(),
        });
    }
    if !response.status().is_success() {
        return Err(format!("GitHub answered {}", response.status()));
    }
    let body: serde_json::Value = response.json().map_err(|e| e.to_string())?;
    let tag = body["tag_name"].as_str().unwrap_or_default();
    let latest = tag.strip_prefix('v').unwrap_or(tag).to_string();
    if latest.is_empty() {
        return Err("GitHub release had no tag name.".into());
    }
    let release_url = body["html_url"]
        .as_str()
        .unwrap_or(RELEASES_PAGE)
        .to_string();
    Ok(UpdateCheck {
        current: current.to_string(),
        update_available: is_newer(&latest, current),
        latest,
        release_url,
    })
}

/// Compare dotted release versions numerically; build/pre-release suffixes
/// (`+N`, `-rc1`) are ignored, missing or non-numeric segments count as 0.
fn is_newer(candidate: &str, current: &str) -> bool {
    fn segments(v: &str) -> Vec<u64> {
        let core = v.split(['+', '-']).next().unwrap_or(v);
        core.split('.')
            .map(|s| s.parse::<u64>().unwrap_or(0))
            .collect()
    }
    let (a, b) = (segments(candidate), segments(current));
    let len = a.len().max(b.len());
    for i in 0..len {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        if x != y {
            return x > y;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::is_newer;

    #[test]
    fn disk_space_reports_sane_numbers() {
        let home = dirs::home_dir().expect("home dir");
        let ds = super::volume_space(&home).expect("home volume resolves");
        assert!(ds.total_bytes > 0);
        assert!(ds.free_bytes >= 0);
        assert!(ds.free_bytes <= ds.total_bytes);
    }

    #[test]
    fn version_comparison() {
        assert!(is_newer("1.0.1", "1.0.0"));
        assert!(!is_newer("1.0.0", "1.0.0"));
        assert!(!is_newer("0.9.9", "1.0.0"));
        assert!(is_newer("1.10.0", "1.9.0"));
        assert!(!is_newer("1.0.0", "1.0.0+1"));
        assert!(is_newer("2.0", "1.9.9"));
    }
}
