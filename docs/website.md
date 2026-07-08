# Clean Mind — website content

Copy and structure for a one-page marketing site (e.g. GitHub Pages under
`/docs`, or any static host). This file is **content, not code** — hand it to
whoever builds the site. Everything here is drawn from the app and README so it
stays truthful.

## Brand

- **Name:** Clean Mind
- **Logo:** `docs/logo.png`
- **One-liner:** See what fills your disk — and understand what's safe to reclaim.
- **Elevator pitch:** A free, open-source, cross-platform disk analyzer built for
  developers. It doesn't just show you a pretty chart — it recognizes regenerable
  developer junk (`node_modules`, build caches, `.venv`s), tells you *why* each is
  safe to delete, and shows the exact command that rebuilds it.
- **Voice:** calm, technical, honest. No hype, no fake urgency.
- **Look:** dark, near-black background with a single emerald accent (match the
  app — the "safe to reclaim" green, roughly `#3DDC97`). Monospace for
  sizes/commands, a clean geometric sans for headings. Reuse the app's feel:
  rounded cards, soft borders, lots of breathing room.

## Assets (already in the repo)

- Hero: `docs/demo.gif` (scan → treemap → insights → move to Trash)
- `docs/screenshot-treemap.png`, `docs/screenshot-insights.png`
- `docs/logo.png`

## Page structure (top to bottom)

### 1. Hero
- **Headline:** Reclaim your disk, safely.
- **Subhead:** Clean Mind is a free, open-source disk analyzer for developers. It
  finds regenerable junk, tells you why it's safe to delete, and shows the command
  to get it back.
- **Primary CTA:** `brew install --cask MS-Teja/clean-mind/clean-mind` (copy
  button) — with a "Download for macOS / Linux / Windows" link to the latest
  release.
- **Secondary CTA:** View on GitHub.
- **Visual:** `docs/demo.gif`, large.
- Badge strip: Apache-2.0 · macOS · Linux · Windows · No telemetry.

### 2. The problem (rotate the framing, don't over-rely on one)
- Lead line: *Storage fills up quietly — and the agentic-coding era made it
  worse.* Spin up throwaway repos with an AI agent all day and you drown in
  `node_modules`, build caches, and `.venv`s. Most of it is regenerable; the hard
  part is knowing which.
- Supporting line: Every "cleaner" shows you *where* the space went and leaves you
  to guess whether deleting a folder will wreck a project. Clean Mind actually
  understands your disk.

### 3. How it works (4 steps, icons)
1. **Scan** — a fast parallel Rust scanner walks any folder (or drag one in).
2. **Understand** — an interactive treemap, or a sortable list, shows where it went.
3. **Classify** — a rules engine flags known developer artifacts by how safely
   they regenerate.
4. **Clean** — one-click reclaim to the Trash; nothing is ever deleted automatically.

### 4. Feature grid (6 cards — pull from README "Why Clean Mind")
- 🗺️ A treemap that makes sense
- 🧠 It knows developer junk (with the regenerate command)
- ✅ Safe by construction (three tiers + hard denylist + Trash-first)
- 🤖 AI on your terms (BYO key or local Ollama; metadata only)
- 🔒 Private and offline by default
- ⚡ Native and fast (parallel Rust, seconds, low memory, no Electron)

### 5. The trust model (short, builds confidence)
Three tiers: **Safe · regenerable** (rules-verified, one-click) → **Review**
(LLM suggestions, never one-click) → **Protected** (hard denylist nothing can
override). The rules engine, not the AI, is the source of truth.

### 6. Performance strip
Parallel Rust core across every core · a home directory in seconds · true on-disk
sizes (hardlink- & APFS-clone-aware) · native binary, no background daemon.

### 7. Cross-platform strip
One native app on macOS, Linux, and Windows — each using the right OS conventions
(Trash vs Recycle Bin, per-platform volumes, long paths on Windows).

### 8. Install
- macOS (Homebrew, recommended): `brew install --cask MS-Teja/clean-mind/clean-mind`
- macOS (universal DMG — Apple silicon + Intel), Linux (x64 + arm64 tarballs +
  `install.sh`), Windows (x64 + arm64 zips) — link to the release.
- Note the unsigned-app first-launch step for the DMG (right-click → Open).

### 9. Open source / footer
- Apache-2.0, built by Siva Teja Mutyala.
- Links: GitHub repo, latest release, license, contributing (add a cleanup rule).
- Small privacy reassurance line: no telemetry, no account, no bundled inference.

## Build notes (for whoever implements it)
- Single static page is enough; GitHub Pages from `/docs` works and matches where
  the assets already live.
- Keep it self-contained and fast (no heavy frameworks needed). Inline the CSS,
  lazy-load the GIF.
- Make the install command one-click-copy.
- Respect `prefers-color-scheme`, but the app's identity is dark-first.
- Don't invent claims — everything above is true of the current app; if a feature
  changes, update this file and the README together.
