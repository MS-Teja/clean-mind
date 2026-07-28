# winget manifest (submission in review)

This directory holds the [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
manifest (schema 1.9) for Clean Mind, kept in sync with each release but
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

## Why `ArchiveBinariesDependOnPath: true` is required

`clean-mind.exe` has load-time imports on `flutter_windows.dll`, the plugin
DLLs, and the bundled VC++ runtime — all siblings of the exe inside the zip.
winget's default portable behaviour installs a symlink into its `Links` folder
and launches the app through it; Windows resolves load-time imports against
the *launch* directory, which is `Links`, so none of those DLLs are found and
the process dies with `STATUS_DLL_NOT_FOUND` (0xC0000135) before `main` runs.
This is [winget-cli #2711](https://github.com/microsoft/winget-cli/issues/2711).

`ArchiveBinariesDependOnPath: true` suppresses the symlink and puts the real
install directory on `PATH` instead, which is the sanctioned fix. It needs
manifest schema **1.9.0 or newer** — the field does not exist in 1.6.0. One
side effect: with no symlink there is no alias, so the command on `PATH` is
`clean-mind`, taken straight from the file name.

## Filling in the installer hashes

`MS-Teja.CleanMind.installer.yaml` ships with `REPLACE_WITH_SHA256_...`
placeholders, because the hashes cannot be known until the release assets are
built. After the release is published:

```sh
VER=1.2.3
for arch in x64 arm64; do
  curl -sL -o "/tmp/cm-$arch.zip" \
    "https://github.com/MS-Teja/clean-mind/releases/download/v$VER/CleanMind-$VER-windows-$arch.zip"
  echo "$arch: $(shasum -a 256 "/tmp/cm-$arch.zip" | cut -d' ' -f1 | tr 'a-f' 'A-F')"
done
```

Or skip the manual step entirely and let `wingetcreate update` compute them
from the URLs, as in step 3 above.
