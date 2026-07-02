use std::time::Duration;

use serde::Deserialize;
use serde_json::{json, Value};

use crate::config::Settings;

const SYSTEM_PROMPT: &str = "You are the analysis engine inside Clean Mind, an open-source disk \
usage analyzer for developers. You receive metadata about the largest directories on the user's \
machine: path, size in bytes, days since last modification, and a rule category when the app's \
deterministic rules engine already recognized the directory. File contents are never available.\n\
Identify directories that are likely safe to delete to reclaim space, focusing on developer \
artifacts: caches, build outputs, dependency directories of stale projects, old SDKs or toolchains. \
Skip anything marked [already identified] (the app handles those) and anything marked [protected]. \
Never suggest documents, media, source code, or credentials.\n\
Respond with ONLY a JSON array, no prose and no code fences. Each element:\n\
{\"path\": \"<exact path from the input>\", \"verdict\": \"delete\"|\"review\"|\"keep\", \
\"regenerability\": \"<how it comes back after deletion>\", \"reasoning\": \"<1-2 sentences a \
developer can act on>\", \"confidence\": <0.0-1.0>}\n\
Only include paths that appear verbatim in the input. Prefer fewer, higher-value suggestions.";

#[derive(Debug, Deserialize)]
pub struct RawRecommendation {
    pub path: String,
    pub verdict: String,
    #[serde(default)]
    pub regenerability: Option<String>,
    pub reasoning: String,
    #[serde(default)]
    pub confidence: Option<f64>,
}

/// One blocking chat call. Providers: "anthropic" (Messages API),
/// "openai" (any OpenAI-compatible /v1/chat/completions), "ollama" (native API).
pub fn chat(settings: &Settings, api_key: Option<&str>, user: &str) -> Result<String, String> {
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(180))
        .build()
        .map_err(|e| e.to_string())?;
    let base = settings.base_url.trim_end_matches('/');

    let (request, extract): (
        reqwest::blocking::RequestBuilder,
        fn(&Value) -> Option<String>,
    ) = match settings.provider.as_str() {
        "anthropic" => (
            client
                .post(format!("{base}/v1/messages"))
                .header("x-api-key", api_key.ok_or("No API key configured")?)
                .header("anthropic-version", "2023-06-01")
                .json(&json!({
                    "model": settings.model,
                    "max_tokens": 8192,
                    "system": SYSTEM_PROMPT,
                    "messages": [{"role": "user", "content": user}],
                })),
            |v| {
                v["content"].as_array().map(|blocks| {
                    blocks
                        .iter()
                        .filter(|b| b["type"] == "text")
                        .filter_map(|b| b["text"].as_str())
                        .collect::<String>()
                })
            },
        ),
        "openai" => (
            client
                .post(format!("{base}/v1/chat/completions"))
                .bearer_auth(api_key.ok_or("No API key configured")?)
                .json(&json!({
                    "model": settings.model,
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": user},
                    ],
                })),
            |v| {
                v["choices"][0]["message"]["content"]
                    .as_str()
                    .map(str::to_owned)
            },
        ),
        "ollama" => (
            client.post(format!("{base}/api/chat")).json(&json!({
                "model": settings.model,
                "stream": false,
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user},
                ],
            })),
            |v| v["message"]["content"].as_str().map(str::to_owned),
        ),
        other => return Err(format!("Unknown provider: {other}")),
    };

    let response = request.send().map_err(|e| format!("Request failed: {e}"))?;
    let status = response.status();
    let body: Value = response
        .json()
        .map_err(|e| format!("Invalid response: {e}"))?;
    if !status.is_success() {
        let detail = body["error"]["message"]
            .as_str()
            .or_else(|| body["error"].as_str())
            .unwrap_or("unknown error");
        return Err(format!("{} — {detail}", status));
    }
    extract(&body).ok_or_else(|| "Response had no text content".into())
}

/// Parse the model's reply defensively: tolerate code fences and surrounding
/// prose by extracting the outermost JSON array.
pub fn parse_recommendations(reply: &str) -> Result<Vec<RawRecommendation>, String> {
    let start = reply.find('[').ok_or("No JSON array in model response")?;
    let end = reply
        .rfind(']')
        .ok_or("Unterminated JSON array in model response")?;
    if end < start {
        return Err("Malformed model response".into());
    }
    serde_json::from_str(&reply[start..=end]).map_err(|e| format!("Could not parse response: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_plain_json_array() {
        let reply =
            r#"[{"path": "a/b", "verdict": "delete", "reasoning": "cache", "confidence": 0.9}]"#;
        let recs = parse_recommendations(reply).unwrap();
        assert_eq!(recs.len(), 1);
        assert_eq!(recs[0].path, "a/b");
        assert_eq!(recs[0].confidence, Some(0.9));
    }

    #[test]
    fn parses_fenced_and_wrapped_json() {
        let reply = "Here you go:\n```json\n[{\"path\": \"x\", \"verdict\": \"review\", \"reasoning\": \"old\"}]\n```\nHope that helps!";
        let recs = parse_recommendations(reply).unwrap();
        assert_eq!(recs.len(), 1);
        assert_eq!(recs[0].verdict, "review");
    }

    #[test]
    fn rejects_reply_without_array() {
        assert!(parse_recommendations("I cannot help with that.").is_err());
    }
}
