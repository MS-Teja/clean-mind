## Install

### macOS (universal — Apple silicon + Intel)
Easiest via Homebrew (no Gatekeeper hoops):
```
brew install --cask MS-Teja/clean-mind/clean-mind
```
Or download the DMG, open it, drag **Clean Mind** to Applications. One DMG covers both Apple silicon and Intel Macs.

This free app is not notarized (there is no paid Apple Developer account behind it), so the first launch needs one extra step:
- **macOS 15 (Sequoia) and later:** open the app once (it will be blocked), then go to **System Settings → Privacy & Security**, scroll down to *"Clean Mind" was blocked*, and click **Open Anyway**.
- **macOS 14 and earlier:** right-click the app in Applications and choose **Open**, then **Open** again.
- Terminal alternative: `xattr -d com.apple.quarantine "/Applications/Clean Mind.app"`

### Linux
On Debian/Ubuntu/Kali/Pop!_OS/Mint, grab the `.deb` for your CPU — `amd64` (Intel/AMD) or `arm64` (Raspberry Pi 5, Ampere, Apple-silicon VMs) — and install it system-wide:
```
sudo apt install ./clean-mind_1.1.0_amd64.deb
```
This adds a launcher entry and a `clean-mind` command. Requires GTK 3 (pulled in automatically).

No root, or not on a Debian-based distro? Download the `linux-x64`/`linux-arm64` tarball instead, extract it, then either run `./clean-mind/clean_mind` directly or run `./clean-mind/install.sh` to install it for your user (launcher entry + icon, no root needed).

### Windows
Easiest via [Scoop](https://scoop.sh):
```
scoop bucket add clean-mind https://github.com/MS-Teja/scoop-clean-mind
scoop install clean-mind
```
Or pick the zip for your CPU — `windows-x64` (Intel/AMD) or `windows-arm64` (Snapdragon X and other Arm PCs) — extract it, and run `clean_mind.exe`. If SmartScreen warns, click **More info → Run anyway**.

Issue reports for Linux and Windows are very welcome.
