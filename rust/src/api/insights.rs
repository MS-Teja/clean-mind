use super::scan::FsTier;
use crate::scanner::{Tier, STORE};

pub struct Insight {
    pub node_id: i64,
    pub path: String,
    pub size: i64,
    pub tier: FsTier,
    pub rule_id: String,
    pub rule_name: String,
    pub category: String,
    pub regenerability: String,
    pub regenerate_with: Option<String>,
    pub explanation: String,
    /// Days since the containing project (or the item itself) was touched;
    /// -1 when unknown.
    pub stale_days: i64,
}

/// Everything the rules engine flagged, largest first. Nested matches under
/// an already-flagged directory are excluded so sizes never double count.
#[flutter_rust_bridge::frb(sync)]
pub fn get_insights() -> Vec<Insight> {
    let store = STORE.read().unwrap();
    let Some(store) = store.as_ref() else {
        return Vec::new();
    };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let mut out = Vec::new();
    let mut stack = vec![store.root];
    while let Some(id) = stack.pop() {
        let node = &store.nodes[id as usize];
        if node.tier == Tier::Protected {
            continue;
        }
        if let Some(r) = node.rule {
            let rule = store.rules.get(r);
            // Staleness: project mtime for dir-name rules (the parent is the
            // project); the item's own mtime for fixed-location caches.
            let mtime = if rule.matcher.dir_name.is_some() {
                node.parent
                    .map(|p| store.nodes[p as usize].mtime)
                    .unwrap_or(node.mtime)
            } else {
                node.mtime
            };
            out.push(Insight {
                node_id: id as i64,
                path: store.path_of(id).to_string_lossy().into_owned(),
                size: node.size as i64,
                tier: match node.tier {
                    Tier::Safe => FsTier::Safe,
                    Tier::Review => FsTier::Review,
                    _ => FsTier::None,
                },
                rule_id: rule.id.clone(),
                rule_name: rule.name.clone(),
                category: rule.category.clone(),
                regenerability: format!("{:?}", rule.regenerability).to_lowercase(),
                regenerate_with: rule.regenerate_with.clone(),
                explanation: rule.explanation.clone(),
                stale_days: if mtime > 0 {
                    (now - mtime).max(0) / 86_400
                } else {
                    -1
                },
            });
            continue; // don't descend into a flagged subtree
        }
        stack.extend(node.children.iter().copied());
    }
    out.sort_by_key(|i| std::cmp::Reverse(i.size));
    out
}
