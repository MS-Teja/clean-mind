use std::collections::{HashMap, HashSet};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::scanner::{NodeKind, ScanStore, Tier};

/// Maximum directory lines sent to the LLM. Metadata only — file contents
/// never leave the machine.
const MAX_ENTRIES: usize = 150;
const MAX_DEPTH: usize = 6;

pub struct Digest {
    pub text: String,
    /// Maps the path string as it appears in the digest (possibly redacted)
    /// back to the node id, so LLM responses can be validated and resolved.
    pub path_to_node: HashMap<String, u32>,
}

/// Well-known directory names that carry no personal information and stay
/// readable under redaction, so the LLM keeps its structural cues.
fn known_names() -> HashSet<&'static str> {
    [
        "node_modules",
        "target",
        "build",
        "dist",
        ".next",
        ".venv",
        "venv",
        "__pycache__",
        ".git",
        ".cache",
        "Library",
        "Caches",
        "Developer",
        "Xcode",
        "DerivedData",
        "Archives",
        "CoreSimulator",
        "Devices",
        "Application Support",
        "Containers",
        "Applications",
        "Development",
        "Projects",
        "src",
        "go",
        "pkg",
        "mod",
        ".cargo",
        "registry",
        ".npm",
        "_cacache",
        ".gradle",
        "caches",
        ".m2",
        "repository",
        ".pub-cache",
        ".bun",
        "install",
        "cache",
        "Homebrew",
        "JetBrains",
        "CocoaPods",
        "pip",
        "uv",
        "Yarn",
        "pnpm",
        "store",
        "Downloads",
        "Desktop",
        "Documents",
        "(small files)",
    ]
    .into()
}

/// Serialize the biggest directories as compact metadata lines:
/// `path | size_bytes | age_days | category-or--`
pub fn build_digest(store: &ScanStore, redact: bool) -> Digest {
    let total = store.node(store.root).map(|n| n.size).unwrap_or(0);
    let threshold = (total / 1000).max(10_000_000); // ≥0.1% of scan or 10MB
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let known = known_names();
    let mut pseudonyms: HashMap<String, String> = HashMap::new();

    // Collect candidate dirs (DFS, parents before children), then keep top-N.
    let mut candidates: Vec<(u32, usize)> = Vec::new();
    let mut stack: Vec<(u32, usize)> = vec![(store.root, 0)];
    while let Some((id, depth)) = stack.pop() {
        let node = &store.nodes[id as usize];
        if node.kind != NodeKind::Dir || node.size < threshold || depth > MAX_DEPTH {
            continue;
        }
        if id != store.root {
            candidates.push((id, depth));
        }
        for &c in &node.children {
            stack.push((c, depth + 1));
        }
    }
    candidates.sort_by_key(|&(id, _)| std::cmp::Reverse(store.nodes[id as usize].size));
    candidates.truncate(MAX_ENTRIES);
    // Restore hierarchical reading order.
    let keep: HashSet<u32> = candidates.iter().map(|&(id, _)| id).collect();

    let mut lines = Vec::new();
    let mut path_to_node = HashMap::new();
    // DFS emitting kept nodes with display paths built top-down. `parts` is
    // one shared stack, pushed/popped around recursion, so ancestor names
    // aren't cloned once per directory in the tree.
    #[allow(clippy::too_many_arguments)]
    fn visit(
        store: &ScanStore,
        id: u32,
        parts: &mut Vec<String>,
        keep: &HashSet<u32>,
        known: &HashSet<&'static str>,
        redact: bool,
        pseudonyms: &mut HashMap<String, String>,
        now: i64,
        lines: &mut Vec<String>,
        path_to_node: &mut HashMap<String, u32>,
    ) {
        let node = &store.nodes[id as usize];
        let pushed = id != store.root;
        if pushed {
            let display_name = if redact && !known.contains(node.name.as_str()) {
                let next = pseudonyms.len() + 1;
                pseudonyms
                    .entry(node.name.clone())
                    .or_insert_with(|| format!("dir-{next}"))
                    .clone()
            } else {
                node.name.clone()
            };
            parts.push(display_name);
            if keep.contains(&id) {
                let path = parts.join("/");
                let age_days = if node.mtime > 0 {
                    (now - node.mtime).max(0) / 86_400
                } else {
                    -1
                };
                let category = node
                    .rule
                    .map(|r| store.rules.get(r).category.as_str())
                    .unwrap_or("-");
                let tier = match node.tier {
                    Tier::Safe => " [already identified: safe to reclaim]",
                    Tier::Review => " [already identified: review]",
                    Tier::Protected => " [protected]",
                    Tier::None => "",
                };
                lines.push(format!(
                    "{path} | {} | {age_days}d | {category}{tier}",
                    node.size
                ));
                path_to_node.insert(path, id);
            }
        }
        for &c in &node.children {
            if store.nodes[c as usize].kind == NodeKind::Dir {
                visit(
                    store,
                    c,
                    parts,
                    keep,
                    known,
                    redact,
                    pseudonyms,
                    now,
                    lines,
                    path_to_node,
                );
            }
        }
        if pushed {
            parts.pop();
        }
    }
    visit(
        store,
        store.root,
        &mut Vec::new(),
        &keep,
        &known,
        redact,
        &mut pseudonyms,
        now,
        &mut lines,
        &mut path_to_node,
    );

    let platform = if cfg!(target_os = "macos") {
        "macOS"
    } else if cfg!(target_os = "windows") {
        "Windows"
    } else {
        "Linux"
    };
    let text = format!(
        "Platform: {platform}\nScan root: <root>\nTotal allocated: {total} bytes\n\
         Directories (path | size bytes | days since modified | rule category):\n{}",
        lines.join("\n")
    );
    Digest { text, path_to_node }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::RuleSet;
    use crate::scanner::{scan, ProgressCounters};
    use std::fs;

    fn fixture_store() -> (tempfile::TempDir, ScanStore) {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir_all(root.join("my-secret-project/node_modules/dep")).unwrap();
        fs::write(root.join("my-secret-project/package.json"), "{}").unwrap();
        fs::write(
            root.join("my-secret-project/node_modules/dep/big.js"),
            vec![0u8; 12_000_000],
        )
        .unwrap();
        let progress = ProgressCounters::default();
        let store = scan(root, RuleSet::builtin(), &progress);
        (tmp, store)
    }

    #[test]
    fn digest_lists_large_dirs_and_maps_back() {
        let (_tmp, store) = fixture_store();
        let digest = build_digest(&store, false);
        assert!(digest.text.contains("my-secret-project/node_modules"));
        let id = digest.path_to_node["my-secret-project/node_modules"];
        assert_eq!(store.nodes[id as usize].name, "node_modules");
    }

    #[test]
    fn redaction_hides_project_names_but_keeps_known_dirs() {
        let (_tmp, store) = fixture_store();
        let digest = build_digest(&store, true);
        assert!(!digest.text.contains("my-secret-project"));
        assert!(digest.text.contains("node_modules"));
        // The redacted path still resolves back to the same node.
        let redacted_path = digest
            .path_to_node
            .keys()
            .find(|p| p.ends_with("/node_modules"))
            .unwrap();
        let id = digest.path_to_node[redacted_path];
        assert_eq!(store.nodes[id as usize].name, "node_modules");
    }
}
