# What's new in 1.2.0

## Windows and Linux, first-class
- **22 new cleanup rules** close the platform gap: NuGet, Poetry, node-gyp, Electron, ccache, Composer, and vcpkg caches, plus Windows locations for Yarn, pnpm, uv, Go, and JetBrains caches. Docker's disk images are recognized too — flagged review-only, with `docker system prune` guidance instead of a delete button.
- The **safety denylist** now also protects `Videos`, `Contacts`, Windows credential stores (DPAPI), and GNOME keyrings — nothing, including the AI, can suggest deleting them.
- **Easier installs**: Windows via Scoop (`scoop bucket add clean-mind https://github.com/MS-Teja/scoop-clean-mind`, then `scoop install clean-mind`), and `.deb` packages for Debian/Ubuntu/Kali/Mint alongside the tarballs.

## A clearer landing screen
- The scan-target card was rebuilt: a friendly target name over the path, a **free-space meter for the target's disk**, and four tidy quick picks (Home, Downloads, Applications, Entire disk). Anything else is one Change click — or a drag-and-drop — away.

## Faster and lighter
- Whole-scan **search is indexed and debounced** — it no longer rescans every name on every keystroke.
- The scanner sheds millions of avoidable allocations per scan, and progress reporting no longer serializes worker threads — the biggest wins land on modest 4-core machines.
- The app is **~18% smaller** on disk and uses **~40% less memory** after a large scan (link-time optimization, stripped symbols, and the UI now releases per-folder caches it no longer needs).
