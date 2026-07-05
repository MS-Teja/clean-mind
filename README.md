<div align="center">

<img src="docs/logo.png" alt="Clean Mind" width="128" />

# Clean Mind

**See what fills your disk — and understand what's safe to reclaim.**

[![CI](https://github.com/MS-Teja/clean-mind/actions/workflows/ci.yml/badge.svg)](https://github.com/MS-Teja/clean-mind/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/MS-Teja/clean-mind?include_prereleases)](https://github.com/MS-Teja/clean-mind/releases/latest)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

</div>

Clean Mind is an open-source, cross-platform (macOS · Linux · Windows) disk usage analyzer in the spirit of OmniDiskSweeper and DaisyDisk, built for developers. Beyond showing *what* takes space, it identifies developer bloat — package caches, build artifacts, stale `node_modules`, old simulators — explains *why* each item can go, and classifies everything by **regenerability**, optionally with help from an LLM you control.

> The full loop works end to end — scan → interactive treemap → tiered
> insights → move-to-Trash, with an optional bring-your-own-LLM analysis pass.
> macOS is the primary platform; Linux and Windows builds are experimental.
> See [CONTRIBUTING.md](CONTRIBUTING.md) to add cleanup rules.

## Why Clean Mind

- 🗺️ **A treemap that makes sense** — a squarified, drill-down map of your disk with breadcrumbs and tier-colored badges, so the biggest space hogs are the biggest tiles.
- 🧠 **It knows developer junk** — a deterministic rules engine recognizes `node_modules`, cargo `target/`, Xcode DerivedData, package-manager caches, build artifacts and more across six ecosystems, and tells you *how* each one regenerates.
- ✅ **Safe by construction** — a three-tier model, a hard denylist nothing can override, and Trash-first deletion. Permanent delete exists only behind a type-to-confirm gate. Nothing is ever deleted automatically.
- 🤖 **AI on your terms** — bring your own Anthropic or OpenAI-compatible key, or run a fully local model via Ollama. The AI only ever sees directory *metadata*, never file contents, and can never promote something to "safe" on its own.
- 🔒 **Private and offline by default** — no telemetry, no account, no bundled inference. Fresh scan each launch; nothing cached, nothing runs in the background.
- ⚡ **Native and fast** — a parallel Rust core (hardlink-aware, APFS-clone-aware) under a Flutter UI.

## Screenshots

<!--
Add real screenshots here — the treemap and the AI-insights panel are the two
money shots. Drop PNGs in docs/ and reference them, e.g.:

![Treemap](docs/screenshot-treemap.png)
![Insights](docs/screenshot-insights.png)

A short GIF of a scan → drill-down → reclaim flow is worth even more; keep it
under ~10 MB so GitHub renders it inline.
-->

_Screenshots coming soon._

## How it works

- **Scan** — a fast parallel Rust scanner walks your home directory (or any path you choose) and builds a size map. Fresh scan every launch; nothing is cached, nothing runs in the background.
- **Understand** — an interactive treemap shows where the space went.
- **Classify** — a deterministic rules engine recognizes known developer artifacts (`node_modules`, cargo `target/`, Xcode DerivedData, Docker images, package-manager caches, …) and marks them by how safely they regenerate.
- **Ask** — optionally, an aggregated view of your largest directories (metadata only, never file contents) is sent to an LLM *you* configure — your own Anthropic/OpenAI-compatible API key, or a fully local model via Ollama — which explains what can go and why.
- **Clean** — deletions go to the OS Trash by default and are recoverable. Permanent deletion exists only behind an explicit confirmation.

### Trust model

The LLM is never trusted on its own:

1. **Safe · regenerable** — only items *confirmed by the rules engine* (e.g. `node_modules` next to a `package.json`). One-click reclaim.
2. **Review** — LLM suggestions that no rule verifies. Always shown with reasoning, never one-click.
3. **Protected** — a hard-coded denylist (documents, photos, `.ssh`, system paths…) that neither rules nor the LLM can override.

## Install

Grab the build for your platform from the [latest release](https://github.com/MS-Teja/clean-mind/releases/latest).

**macOS** — open the DMG and drag **Clean Mind** to Applications. The app is not notarized (this is a free app with no paid Apple Developer account behind it), so the first launch needs one extra step:

- *macOS 15 and later:* open the app once (it will be blocked), then **System Settings → Privacy & Security → Open Anyway**.
- *macOS 14 and earlier:* right-click the app → **Open** → **Open**.
- Or from a terminal: `xattr -d com.apple.quarantine "/Applications/Clean Mind.app"`

On first scan, macOS will ask for access to folders like Documents and Desktop — that's the normal per-folder permission prompt. For complete results (Mail, Safari, and other protected data), grant **Full Disk Access**; the app detects when it's missing and offers a shortcut to the right settings pane.

**Linux** *(experimental)* — extract the tarball and run `clean_mind`. Requires GTK 3.

**Windows** *(experimental)* — extract the zip and run `clean_mind.exe`. If SmartScreen warns, choose **More info → Run anyway**.

The Linux and Windows builds compile and pass tests in CI but have seen less real-world use than macOS — issue reports are very welcome.

## Stack

- **Core:** Rust (`rust/`) — scanner, rules engine, LLM providers, trash operations.
- **UI:** Flutter (`lib/`) with Riverpod, bridged via [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge); `rust_builder/` contains the cargokit glue that builds the Rust core inside each platform's build.

## Building from source

Prerequisites: [Rust](https://rustup.rs), [Flutter](https://flutter.dev) (with desktop support for your platform).

```sh
flutter pub get
flutter run          # runs the app; cargokit compiles the Rust core automatically
```

Tests:

```sh
cd rust && cargo test    # core
flutter test             # UI
```

Regenerate the bridge after changing `rust/src/api/`:

```sh
cargo install flutter_rust_bridge_codegen
flutter_rust_bridge_codegen generate
```

## Privacy

- No telemetry, no accounts, no bundled inference.
- The AI layer is opt-in, and only ever sends directory **metadata** (paths, sizes, timestamps) — never file contents.
- An optional redaction mode pseudonymizes path names under your home directory before anything leaves your machine.
- API keys are stored in the operating system keychain, not in config files.

## Project status

macOS is the primary, best-tested platform. Linux and Windows build and pass the
full CI suite on every push, but have had less hands-on testing — bug reports on
those platforms are especially welcome.

On the near-term list: real screenshots and a demo GIF, more cleanup rules
(contributions welcome — see below), and surfacing restore-from-Trash in the UI.

## Contributing

Cleanup rules live in [`rules/`](rules) as declarative TOML, one file per
ecosystem (js, python, rust, jvm, apple, tools) — adding support for a new tool
is often just a few lines and no Rust. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the rule schema and how to test a new rule against a fixture project.

## License

[Apache-2.0](LICENSE)
