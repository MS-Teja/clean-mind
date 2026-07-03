# Contributing to Clean Mind

Thanks for helping out. Clean Mind is a Rust core (`rust/`) behind a Flutter UI
(`lib/`), bridged with [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge).

## Setup

Prerequisites: [Rust](https://rustup.rs), [Flutter](https://flutter.dev) with
desktop support for your platform.

```sh
flutter pub get
flutter run            # cargokit compiles the Rust core automatically
```

If you change anything in `rust/src/api/`, regenerate the Dart bindings:

```sh
cargo install flutter_rust_bridge_codegen   # once
flutter_rust_bridge_codegen generate
```

## Checks before opening a PR

```sh
cd rust && cargo fmt --check && cargo clippy -- -D warnings && cargo test
flutter analyze && flutter test
```

The end-to-end integration test (`integration_test/app_test.dart`) drives the
real app against a fixture dev tree; run it on a machine with a display:

```sh
flutter test integration_test -d macos   # or -d linux / -d windows
```

## Adding a cleanup rule (the most useful contribution)

Rules live in `rules/*.toml`, one file per ecosystem, and are embedded into the
binary at build time. They're plain data — no Rust needed. A rule either matches
a directory **by name** (confirmed by a sibling project marker) or a **fixed path
relative to the user's home**.

```toml
[[rule]]
id = "turbo-cache"                       # unique, kebab-case
name = "Turborepo cache"                 # shown in the UI
category = "Package manager caches"      # groups items in Insights
regenerability = "cache"                 # regenerable | cache | review
regenerate_with = "refills on the next turbo run"   # optional
explanation = "Task outputs Turborepo re-derives on demand."
platforms = ["macos", "linux"]           # optional; omit for all platforms

[rule.match]
dir_name = ".turbo"
siblings = ["turbo.json"]                # at least one must sit next to it
# — or, instead of dir_name/siblings, a fixed cache location:
# home_path = "Library/Caches/turbo"     # /-separated, relative to $HOME
```

Guidelines:

- **`regenerability` drives the trust tier.** `regenerable` and `cache` become
  Tier 1 (one-click reclaim), `review` becomes Tier 2 (shown with a warning).
  If deleting could lose work a tool can't rebuild, it's `review` — not `cache`.
- **Require a marker.** A bare `dir_name = "target"` would match a photographer's
  `target/` folder. The `siblings` list is what makes the match trustworthy.
- **Never match personal data.** The protected denylist in `rust/src/safety/`
  overrides every rule, but don't write rules that lean on it.
- **Add a fixture test** in `rust/src/scanner/mod.rs` if the match is non-obvious
  (nested directories, ambiguous markers).

Run `cargo test` — `builtin_rules_parse_and_index` validates that every rule has
exactly one matcher and parses cleanly.

## Code style

Match the surrounding code. Rust is `cargo fmt` default; Dart is `flutter format`
default. Keep comments to constraints the code can't express on its own.

By contributing you agree your work is licensed under Apache-2.0.
