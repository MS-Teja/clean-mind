# Clean Mind

**See what fills your disk — and understand what is safe to reclaim.**

Clean Mind is an open-source, cross-platform (macOS · Linux · Windows) disk usage analyzer in the spirit of OmniDiskSweeper and DaisyDisk, built for developers. Beyond showing *what* takes space, it identifies developer bloat — package caches, build artifacts, stale `node_modules`, old simulators — explains *why* each item can go, and classifies everything by **regenerability**, optionally with help from an LLM you control.

> ⚠️ Early development. Not yet ready for daily use.

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

## License

[Apache-2.0](LICENSE)
