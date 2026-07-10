# Clean Mind — website content source

Content reference for the marketing site in `docs/` (served via GitHub Pages).
Everything here is drawn from the app and the README so the site stays
truthful. When a feature or install path changes, this file, the README, and
`index.html` should change together.

## Brand

- **Name:** Clean Mind
- **Logo:** `docs/logo.png`
- **One-liner:** See what fills your disk — and understand what's safe to reclaim.
- **Elevator pitch:** A free, open-source, cross-platform disk analyzer built
  for developers. It doesn't just show a chart — it recognizes regenerable
  developer junk (`node_modules`, build caches, `.venv`s), explains *why* each
  item is safe to delete, and shows the exact command that rebuilds it.
- **Voice:** calm, technical, honest. No hype, no fake urgency.
- **Terminology:** always "pseudonymize folder names" (never "redact");
  tiers are "Safe · regenerable", "Review", "Protected".

## Design system ("The Lab Report")

The site is styled as a typeset engineering document: paper background
(`#fafaf7`), ink text (`#141715`), hairline rules, one mint accent
(`#0a7f5f`) reserved for safe/reclaim semantics, amber for the review tier.
Space Grotesk for display type, JetBrains Mono for all numbers, paths, and
annotations. No rounded corners, shadows, or gradients. Sections are numbered
like a document (§01–§07) and figures are captioned (`fig. 01`, `plate II`).

## Page structure

1. **Title block** — poster headline "Reclaim your disk, safely.", abstract,
   download button, and `fig. 01`: an ink-axonometric treemap of a sample scan
   (519 MB verified safe). A badge strip (version · license · platforms · no
   telemetry) closes the section.
2. **§01 The problem** — the agentic-coding-era framing: coding agents fill
   disks with regenerable artifacts; the hard part is knowing which.
3. **§02 The method** — a scroll-driven figure that acts out
   Scan → Understand → Classify → Clean. Performance claim used here: a home
   directory of ~1.2 million files scans in about 8 seconds.
4. **§03 The trust model** — three tiers as a spec table; the rules engine,
   not the AI, is the source of truth.
5. **§04 Privacy** — "Private by design, not by policy." Offline by default,
   BYO key or local Ollama, metadata only, keys in the OS keychain, and the
   pseudonymization ledger (`dir-1`, `dir-2`, … — structural names like
   `node_modules` stay readable).
6. **§05 Plates** — `demo.gif` plus the two screenshots, captioned.
7. **§06 In one line** — "The DaisyDisk idea — free, cross-platform, and it
   actually understands a developer's disk", over a ticker of recognized
   artifacts.
8. **§07 Download & install** — see below.
9. **Colophon** — license, author, project links, privacy line.

## Install (mirrors the README)

- **macOS — Homebrew (recommended):**
  `brew install --cask MS-Teja/clean-mind/clean-mind`
  Alternative: universal DMG (Apple silicon + Intel). Not notarized — on
  macOS 15+ open once, then System Settings → Privacy & Security → Open
  Anyway; earlier versions: right-click → Open. Grant Full Disk Access for
  complete results.
- **Windows — Scoop (recommended):**
  `scoop bucket add clean-mind https://github.com/MS-Teja/scoop-clean-mind`
  then `scoop install clean-mind`.
  Alternative: portable zips — x64 (Intel/AMD) or arm64 (Snapdragon X);
  extract and run `clean_mind.exe`. SmartScreen: More info → Run anyway.
- **Linux — Debian/Ubuntu/Kali/Mint:**
  `sudo apt install ./clean-mind_<version>_amd64.deb` (or `_arm64.deb`).
  Other distros: `linux-x64` / `linux-arm64` tarball with `install.sh`
  (per-user, no root) or run the binary directly. Requires GTK 3.

All platforms ship x64 and arm64. The download section resolves the latest
release (version, direct links, sizes) from the GitHub API at page load, with
the releases page as the no-JS fallback.

## Assets

- `docs/logo.png` — app icon (used in the running head, masthead, favicon)
- `docs/demo.gif` — scan → treemap → insights → move to Trash
- `docs/screenshot-treemap.png`, `docs/screenshot-insights.png`
- `docs/fonts/` — self-hosted Space Grotesk + JetBrains Mono
- `docs/vendor/three.module.js` — vendored Three.js for the §02 figure

## Build notes

- Static site, no build step; GitHub Pages serves `/docs` from `main`.
- `figure.js` draws the §02 scene (WebGL, orthographic); it falls back to the
  masthead SVG when WebGL is unavailable, and all motion respects
  `prefers-reduced-motion`.
- Claims on the page must stay true of the current app.
