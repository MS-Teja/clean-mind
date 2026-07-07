use std::path::PathBuf;

use crate::ops::{self, DeleteMode};
use crate::scanner::STORE;

pub struct OpOutcome {
    pub path: String,
    pub ok: bool,
    pub message: Option<String>,
}

fn resolve_paths(node_ids: &[i64]) -> Vec<PathBuf> {
    let store = STORE.read().unwrap();
    let Some(store) = store.as_ref() else {
        return Vec::new();
    };
    node_ids
        .iter()
        .filter_map(|&id| {
            if id < 0 {
                return None;
            }
            store.node(id as u32)?;
            Some(store.path_of(id as u32))
        })
        .collect()
}

fn run_delete(node_ids: Vec<i64>, mode: DeleteMode) -> Vec<OpOutcome> {
    let paths = resolve_paths(&node_ids);
    let refs: Vec<&std::path::Path> = paths.iter().map(|p| p.as_path()).collect();
    ops::delete_paths(&refs, mode)
        .into_iter()
        .map(|o| OpOutcome {
            path: o.path,
            ok: o.ok,
            message: o.message,
        })
        .collect()
}

/// Default deletion: recoverable, straight to the OS Trash / Recycle Bin.
pub async fn move_to_trash(node_ids: Vec<i64>) -> Vec<OpOutcome> {
    flutter_rust_bridge::spawn_blocking_with(
        move || run_delete(node_ids, DeleteMode::Trash),
        crate::frb_generated::FLUTTER_RUST_BRIDGE_HANDLER.thread_pool(),
    )
    .await
    .expect("trash worker panicked")
}

/// Irreversible. The UI must gate this behind an explicit type-to-confirm
/// dialog; `confirmed` is re-checked here so no code path skips it.
pub async fn delete_permanently(
    node_ids: Vec<i64>,
    confirmed: bool,
) -> Result<Vec<OpOutcome>, String> {
    if !confirmed {
        return Err("Permanent deletion requires explicit confirmation.".into());
    }
    Ok(flutter_rust_bridge::spawn_blocking_with(
        move || run_delete(node_ids, DeleteMode::Permanent),
        crate::frb_generated::FLUTTER_RUST_BRIDGE_HANDLER.thread_pool(),
    )
    .await
    .expect("delete worker panicked"))
}

/// Show the item in Finder / Explorer / the file manager.
#[flutter_rust_bridge::frb(sync)]
pub fn reveal_in_file_manager(node_id: i64) -> Result<(), String> {
    let paths = resolve_paths(&[node_id]);
    let path = paths.first().ok_or("Item not found in current scan")?;
    ops::reveal(path)
}

/// Open the item with the OS default handler (file → default app,
/// directory → file manager).
#[flutter_rust_bridge::frb(sync)]
pub fn open_item(node_id: i64) -> Result<(), String> {
    let paths = resolve_paths(&[node_id]);
    let path = paths.first().ok_or("Item not found in current scan")?;
    ops::open(path)
}
