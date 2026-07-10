## What & why

<!-- What does this change, and what problem does it solve? -->

## Checklist

- [ ] `cargo fmt --check && cargo clippy -- -D warnings && cargo test` pass (if `rust/` changed)
- [ ] `flutter analyze && flutter test` pass (if `lib/` changed)
- [ ] New cleanup rules: regeneration command verified, and follow the conventions in the existing `rules/*.toml` files (never `regenerable` unless a sibling marker proves the context)
