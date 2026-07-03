use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// App settings. Only configuration lives here — scan data is never persisted.
/// API keys are NOT part of this struct; they live in the OS keychain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    /// "anthropic" | "openai" (any OpenAI-compatible endpoint) | "ollama"
    pub provider: String,
    pub base_url: String,
    pub model: String,
    /// Pseudonymize path names before sending anything to a remote LLM.
    pub redact: bool,
    /// Last scan root the user picked; scan *data* is still never persisted.
    #[serde(default)]
    pub scan_root: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            provider: "anthropic".into(),
            base_url: default_base_url("anthropic").into(),
            model: "claude-opus-4-8".into(),
            redact: false,
            scan_root: None,
        }
    }
}

pub fn default_base_url(provider: &str) -> &'static str {
    match provider {
        "openai" => "https://api.openai.com",
        "ollama" => "http://localhost:11434",
        _ => "https://api.anthropic.com",
    }
}

pub fn default_model(provider: &str) -> &'static str {
    match provider {
        "openai" => "gpt-4o-mini",
        "ollama" => "llama3.2",
        _ => "claude-opus-4-8",
    }
}

fn settings_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("clean-mind").join("settings.json"))
}

pub fn load() -> Settings {
    settings_path()
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save(settings: &Settings) -> Result<(), String> {
    let path = settings_path().ok_or("no config directory on this platform")?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    fs::write(path, json).map_err(|e| e.to_string())
}

const KEYRING_SERVICE: &str = "clean-mind";

pub fn save_api_key(provider: &str, key: &str) -> Result<(), String> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, provider).map_err(|e| e.to_string())?;
    if key.is_empty() {
        let _ = entry.delete_credential();
        Ok(())
    } else {
        entry.set_password(key).map_err(|e| e.to_string())
    }
}

pub fn get_api_key(provider: &str) -> Option<String> {
    keyring::Entry::new(KEYRING_SERVICE, provider)
        .ok()?
        .get_password()
        .ok()
}
