# What's new in 1.1.0

## Navigate and search your scan
- **Back / forward navigation** through the folders you visit (`Cmd+[` / `Cmd+]`, or `Ctrl` on Linux/Windows), with a breadcrumb trail.
- **Whole-scan search** — find any file or folder by name and jump straight to it in the treemap.
- **List view** as an alternative to the treemap: sortable by name, items, or size; double-click to drill in. Your view and sort choices are remembered.
- **Right-click context menu** on treemap tiles: open, reveal, copy path, focus.

## Easier scanning
- **Drag & drop** a folder anywhere on the window to scan it.
- **One calm scan card** on the landing screen: quick picks (Home, Desktop, Documents, Downloads, Applications, mounted volumes, entire disk), a recent-scans menu, and the current target in one place.
- The scanner now survives extremely deep trees, reports folders it couldn't read (instead of silently under-counting), and shows both on-disk and apparent sizes.

## A friendlier settings screen
- Redesigned two-pane settings (AI assistant / Privacy / About) — open it from anywhere with `Cmd+,` (`Ctrl+,` on Linux/Windows).
- **Opening settings no longer triggers a macOS keychain password prompt.** The key is only read when you actually run a connection test or analysis.
- Settings now say clearly whether an API key is saved, and let you remove it.
- Your model and base URL are **remembered per provider** — switching providers never wipes them. Fields are saved however you close the dialog.
- Check for updates is one click away in the settings sidebar.

## Cross-platform
- The macOS DMG is a **universal binary** (Apple silicon + Intel), enforced in CI.
- New **Linux arm64** and **Windows arm64** builds (Raspberry Pi 5, Ampere, Snapdragon X, …).
- Windows: opening files from the app now uses your default handler correctly.

## Polish
- Seamless macOS title bar and themed menus and popups throughout.
