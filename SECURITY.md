# Security policy

## Supported versions

Only the [latest release](https://github.com/MS-Teja/clean-mind/releases/latest) receives fixes.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: [report a vulnerability](https://github.com/MS-Teja/clean-mind/security/advisories/new). Please don't open a public issue for security problems — reports are handled privately and credited in the fix release unless you prefer otherwise.

## What counts

Clean Mind runs entirely on your machine — no server, no telemetry, no account — so the sensitive surfaces are local:

- **Deletion safety.** Any way to make the app suggest or perform deletion of a protected path (the denylist in `rust/src/safety/`), or to escalate a *Review*-tier item to one-click deletion.
- **Data leaving the machine.** The optional BYO-LLM analysis should only ever send directory metadata (names, sizes, ages) — and with pseudonymization on, not even real folder names. Anything beyond that is a bug.
- **API key handling.** Keys belong in the OS keychain, never in files or logs.

Reports in those areas are especially valuable, but anything security-relevant is welcome.
