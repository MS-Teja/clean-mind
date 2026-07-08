use crate::analysis;
use crate::config;
use crate::llm;
use crate::scanner::{Tier, STORE};

pub struct LlmSettings {
    pub provider: String,
    pub base_url: String,
    pub model: String,
    pub redact: bool,
}

pub struct AiRecommendation {
    pub node_id: i64,
    pub path: String,
    pub size: i64,
    pub verdict: String,
    pub regenerability: String,
    pub reasoning: String,
    pub confidence: f64,
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_llm_settings() -> LlmSettings {
    let s = config::load();
    LlmSettings {
        provider: s.provider,
        base_url: s.base_url,
        model: s.model,
        redact: s.redact,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_llm_settings(settings: LlmSettings) -> Result<(), String> {
    // Load-and-mutate so scan_root and recent_roots survive an LLM settings save.
    let mut current = config::load();
    // Remember this provider's base URL/model so switching providers later
    // restores them instead of resetting to defaults.
    current.remember_provider(&settings.provider, &settings.base_url, &settings.model);
    current.provider = settings.provider;
    current.base_url = settings.base_url;
    current.model = settings.model;
    current.redact = settings.redact;
    config::save(&current)
}

/// Settings to show when the user picks `provider`: whatever they last saved
/// for it, or the built-in defaults if they never configured it.
#[flutter_rust_bridge::frb(sync)]
pub fn settings_for_provider(provider: String) -> LlmSettings {
    let current = config::load();
    let cfg = current.config_for(&provider);
    LlmSettings {
        base_url: cfg.base_url,
        model: cfg.model,
        provider,
        redact: current.redact,
    }
}

/// Store the key in the OS keychain — never in config files. Empty deletes.
#[flutter_rust_bridge::frb(sync)]
pub fn save_api_key(provider: String, key: String) -> Result<(), String> {
    config::save_api_key(&provider, &key)
}

/// Whether a key is saved for `provider`. Uses the non-secret settings hint, so
/// it never reads the keychain (and never triggers an OS password prompt) —
/// safe to call while rendering the settings screen.
#[flutter_rust_bridge::frb(sync)]
pub fn has_api_key(provider: String) -> bool {
    config::has_saved_key(&provider)
}

fn needs_key(provider: &str) -> bool {
    provider != "ollama"
}

/// Round-trip a trivial prompt to verify provider settings and key.
pub async fn test_llm_connection() -> Result<String, String> {
    flutter_rust_bridge::spawn_blocking_with(
        move || {
            let settings = config::load();
            let key = config::get_api_key(&settings.provider);
            if needs_key(&settings.provider) && key.is_none() {
                return Err("No API key stored for this provider.".into());
            }
            llm::chat(
                &settings,
                key.as_deref(),
                "Connection test. Reply with the single word: OK",
            )
            .map(|reply| reply.chars().take(120).collect())
        },
        crate::frb_generated::FLUTTER_RUST_BRIDGE_HANDLER.thread_pool(),
    )
    .await
    .expect("llm worker panicked")
}

/// Send the scan digest (metadata only) to the configured LLM and return
/// validated Tier-2 recommendations. The LLM can never promote anything to
/// Tier 1 and never touch protected paths — that is enforced here, not by
/// prompting.
pub async fn run_ai_analysis() -> Result<Vec<AiRecommendation>, String> {
    flutter_rust_bridge::spawn_blocking_with(
        move || {
            let settings = config::load();
            let key = config::get_api_key(&settings.provider);
            if needs_key(&settings.provider) && key.is_none() {
                return Err("No API key stored for this provider.".into());
            }

            let digest = {
                let store = STORE.read().unwrap();
                let store = store.as_ref().ok_or("No scan available — scan first.")?;
                analysis::build_digest(store, settings.redact)
            };

            let reply = llm::chat(&settings, key.as_deref(), &digest.text)?;
            let raw = llm::parse_recommendations(&reply)?;

            let store = STORE.read().unwrap();
            let store = store.as_ref().ok_or("Scan was cleared during analysis.")?;
            let mut seen = std::collections::HashSet::new();
            let mut out = Vec::new();
            for rec in raw {
                // Only paths that exist in the digest we actually sent.
                let Some(&node_id) = digest.path_to_node.get(&rec.path) else {
                    continue;
                };
                if !seen.insert(node_id) || rec.verdict == "keep" {
                    continue;
                }
                let node = &store.nodes[node_id as usize];
                // Hard safety: never surface protected paths; skip anything the
                // rules engine already verified (it's Tier 1 already).
                if node.tier == Tier::Protected || node.tier == Tier::Safe {
                    continue;
                }
                out.push(AiRecommendation {
                    node_id: node_id as i64,
                    path: store.path_of(node_id).to_string_lossy().into_owned(),
                    size: node.size as i64,
                    verdict: rec.verdict,
                    regenerability: rec.regenerability.unwrap_or_default(),
                    reasoning: rec.reasoning,
                    confidence: rec.confidence.unwrap_or(0.5).clamp(0.0, 1.0),
                });
            }
            out.sort_by_key(|r| std::cmp::Reverse(r.size));
            Ok(out)
        },
        crate::frb_generated::FLUTTER_RUST_BRIDGE_HANDLER.thread_pool(),
    )
    .await
    .expect("llm worker panicked")
}
