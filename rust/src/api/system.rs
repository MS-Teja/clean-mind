use std::process::Command;

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
    fn version_comparison() {
        assert!(is_newer("1.0.1", "1.0.0"));
        assert!(!is_newer("1.0.0", "1.0.0"));
        assert!(!is_newer("0.9.9", "1.0.0"));
        assert!(is_newer("1.10.0", "1.9.0"));
        assert!(!is_newer("1.0.0", "1.0.0+1"));
        assert!(is_newer("2.0", "1.9.9"));
    }
}
