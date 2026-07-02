use std::collections::{HashMap, HashSet};

use serde::Deserialize;

/// How safely an item comes back after deletion. This drives the trust tier:
/// `regenerable`/`cache` land in Tier 1 (safe), `review` in Tier 2.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Regenerability {
    /// Rebuilt exactly by a tool from committed inputs (lockfiles, sources).
    Regenerable,
    /// Re-downloaded or re-derived on demand; deleting costs only time.
    Cache,
    /// Plausibly deletable but a human must look (archives, simulators…).
    Review,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MatchSpec {
    /// Match a directory with this exact name…
    #[serde(default)]
    pub dir_name: Option<String>,
    /// …but only when one of these files/dirs sits next to it (project marker).
    #[serde(default)]
    pub siblings: Vec<String>,
    /// Or match a fixed path relative to the user's home, `/`-separated.
    #[serde(default)]
    pub home_path: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Rule {
    pub id: String,
    pub name: String,
    pub category: String,
    pub regenerability: Regenerability,
    #[serde(default)]
    pub regenerate_with: Option<String>,
    pub explanation: String,
    /// Restrict to platforms ("macos", "linux", "windows"); absent = all.
    #[serde(default)]
    pub platforms: Option<Vec<String>>,
    #[serde(rename = "match")]
    pub matcher: MatchSpec,
}

#[derive(Deserialize)]
struct RuleFile {
    rule: Vec<Rule>,
}

/// Rule files are embedded at build time from `rules/` at the repo root so
/// the binary is self-contained; the directory stays community-editable.
const BUILTIN_RULE_FILES: &[(&str, &str)] = &[
    ("js", include_str!("../../../rules/js.toml")),
    ("python", include_str!("../../../rules/python.toml")),
    ("rust", include_str!("../../../rules/rust.toml")),
    ("jvm", include_str!("../../../rules/jvm.toml")),
    ("apple", include_str!("../../../rules/apple.toml")),
    ("tools", include_str!("../../../rules/tools.toml")),
];

pub struct RuleSet {
    pub rules: Vec<Rule>,
    by_dir_name: HashMap<String, Vec<u16>>,
}

impl RuleSet {
    pub fn builtin() -> Self {
        let mut rules = Vec::new();
        for (file, content) in BUILTIN_RULE_FILES {
            let parsed: RuleFile = toml::from_str(content)
                .unwrap_or_else(|e| panic!("invalid builtin rule file {file}.toml: {e}"));
            rules.extend(
                parsed
                    .rule
                    .into_iter()
                    .filter(|r| platform_matches(r.platforms.as_deref())),
            );
        }
        Self::from_rules(rules)
    }

    pub fn from_rules(rules: Vec<Rule>) -> Self {
        let mut by_dir_name: HashMap<String, Vec<u16>> = HashMap::new();
        for (i, rule) in rules.iter().enumerate() {
            if let Some(name) = &rule.matcher.dir_name {
                by_dir_name.entry(name.clone()).or_default().push(i as u16);
            }
        }
        Self { rules, by_dir_name }
    }

    /// Match a directory by name against its siblings (the other entries of
    /// the parent directory). Returns the first applicable rule index.
    pub fn match_dir(&self, dir_name: &str, siblings: &HashSet<String>) -> Option<u16> {
        let candidates = self.by_dir_name.get(dir_name)?;
        candidates.iter().copied().find(|&i| {
            let spec = &self.rules[i as usize].matcher;
            spec.siblings.is_empty() || spec.siblings.iter().any(|s| siblings.contains(s))
        })
    }

    pub fn home_path_rules(&self) -> impl Iterator<Item = (u16, &str)> {
        self.rules
            .iter()
            .enumerate()
            .filter_map(|(i, r)| r.matcher.home_path.as_deref().map(|p| (i as u16, p)))
    }

    pub fn get(&self, idx: u16) -> &Rule {
        &self.rules[idx as usize]
    }
}

fn platform_matches(platforms: Option<&[String]>) -> bool {
    let Some(platforms) = platforms else {
        return true;
    };
    let current = if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else {
        "linux"
    };
    platforms.iter().any(|p| p == current)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtin_rules_parse_and_index() {
        let set = RuleSet::builtin();
        assert!(
            set.rules.len() >= 10,
            "expected a meaningful launch rule set"
        );
        assert!(set.rules.iter().any(|r| r.id == "node-modules"));
        // Every rule must have exactly one matcher kind.
        for r in &set.rules {
            let kinds = r.matcher.dir_name.is_some() as u8 + r.matcher.home_path.is_some() as u8;
            assert_eq!(kinds, 1, "rule {} needs exactly one matcher", r.id);
        }
    }

    #[test]
    fn sibling_requirement_enforced() {
        let set = RuleSet::builtin();
        let with_marker: HashSet<String> =
            ["package.json".to_string(), "node_modules".to_string()].into();
        let without: HashSet<String> = ["node_modules".to_string()].into();
        assert!(set.match_dir("node_modules", &with_marker).is_some());
        assert!(set.match_dir("node_modules", &without).is_none());
        assert!(set
            .match_dir("definitely_not_a_rule_dir", &with_marker)
            .is_none());
    }
}
