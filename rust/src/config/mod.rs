use std::collections::BTreeMap;
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
    /// Most-recently-scanned roots (paths only — never scan data), newest
    /// first, capped at [`RECENT_ROOTS_CAP`]. Powers the landing "recent scans".
    #[serde(default)]
    pub recent_roots: Vec<String>,
    /// Providers that have a key saved in the keychain. A **non-secret** hint
    /// so the UI can say "a key is stored" without reading the keychain (which
    /// triggers an OS password prompt). The secret itself never lives here.
    #[serde(default)]
    pub key_providers: Vec<String>,
    /// Per-provider base URL / model, remembered so switching providers in
    /// settings never wipes a customized model name.
    #[serde(default)]
    pub provider_configs: BTreeMap<String, ProviderConfig>,
    /// Small UI preferences (view mode, sort) that should survive restarts.
    #[serde(default)]
    pub ui: UiConfig,
}

/// Saved base URL + model for one provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConfig {
    pub base_url: String,
    pub model: String,
}

/// Non-critical UI preferences persisted alongside settings.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UiConfig {
    /// "treemap" | "list"
    pub results_view: String,
    /// "size" | "name" | "items"
    pub sort_key: String,
    pub sort_ascending: bool,
}

impl Default for UiConfig {
    fn default() -> Self {
        Self {
            results_view: "treemap".into(),
            sort_key: "size".into(),
            sort_ascending: false,
        }
    }
}

/// How many recent scan roots to remember.
pub const RECENT_ROOTS_CAP: usize = 8;

impl Default for Settings {
    fn default() -> Self {
        Self {
            provider: "anthropic".into(),
            base_url: default_base_url("anthropic").into(),
            model: "claude-opus-4-8".into(),
            redact: false,
            scan_root: None,
            recent_roots: Vec::new(),
            key_providers: Vec::new(),
            provider_configs: BTreeMap::new(),
            ui: UiConfig::default(),
        }
    }
}

impl Settings {
    /// Record `path` as the newest recent root (dedup, MRU-ordered, capped).
    pub fn push_recent(&mut self, path: &str) {
        self.recent_roots.retain(|p| p != path);
        self.recent_roots.insert(0, path.to_string());
        self.recent_roots.truncate(RECENT_ROOTS_CAP);
    }

    /// Saved base URL + model for `provider`, falling back to the built-in
    /// defaults — so switching providers restores what the user configured.
    pub fn config_for(&self, provider: &str) -> ProviderConfig {
        self.provider_configs
            .get(provider)
            .cloned()
            .unwrap_or_else(|| ProviderConfig {
                base_url: default_base_url(provider).into(),
                model: default_model(provider).into(),
            })
    }

    /// Remember `base_url`/`model` as the saved config for `provider`.
    pub fn remember_provider(&mut self, provider: &str, base_url: &str, model: &str) {
        self.provider_configs.insert(
            provider.to_string(),
            ProviderConfig {
                base_url: base_url.to_string(),
                model: model.to_string(),
            },
        );
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
    let mut settings = load();
    if key.is_empty() {
        let _ = entry.delete_credential();
        settings.key_providers.retain(|p| p != provider);
    } else {
        entry.set_password(key).map_err(|e| e.to_string())?;
        if !settings.key_providers.iter().any(|p| p == provider) {
            settings.key_providers.push(provider.to_string());
        }
    }
    // Persist the non-secret "has a key" hint so the UI never has to read the
    // keychain (and trigger an OS prompt) just to render settings.
    let _ = save(&settings);
    Ok(())
}

/// Whether a key is saved for `provider`, checked via the non-secret settings
/// hint — does NOT touch the keychain, so it never prompts.
pub fn has_saved_key(provider: &str) -> bool {
    load().key_providers.iter().any(|p| p == provider)
}

/// Read the actual secret from the keychain. This CAN trigger an OS password
/// prompt, so only call it when making a real API request (test / analysis) —
/// never just to render the UI.
pub fn get_api_key(provider: &str) -> Option<String> {
    keyring::Entry::new(KEYRING_SERVICE, provider)
        .ok()?
        .get_password()
        .ok()
}
