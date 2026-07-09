# winget manifest (not yet submitted)

This directory holds the [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
manifest (schema 1.6) for Clean Mind, kept in sync with each release but
**not submitted automatically**.

Submission goes to Microsoft's community repo,
[microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs), via PR —
there is no way to publish a package without their review. Do this manually
after cutting a release:

1. Update the three files here (version bump, new `InstallerUrl`s, new
   `InstallerSha256`s) to match the new release's Windows assets.
2. Install [`wingetcreate`](https://github.com/microsoft/winget-create) if
   you don't have it: `winget install wingetcreate`.
3. Run `wingetcreate update MS-Teja.CleanMind --version <version> --urls <windows-x64-zip-url> <windows-arm64-zip-url> --submit`,
   or pass `--urls` alone and let it compute the hashes, or hand it these
   files directly with `wingetcreate submit <path-to-this-dir>`.
4. `wingetcreate` opens a PR against `microsoft/winget-pkgs` under
   `manifests/m/MS-Teja/CleanMind/<version>/`. Address any automated
   validation feedback there.

Unsigned portable zips (`InstallerType: zip` + `NestedInstallerType: portable`)
are accepted by winget-pkgs — there is no code-signing requirement, though
unsigned installers do show an extra confirmation prompt at install time.
