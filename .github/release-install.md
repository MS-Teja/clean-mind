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
Easiest via the one-line installer — it detects your CPU and installs the latest release:
```
curl -fsSL https://ms-teja.github.io/clean-mind/install.sh | sh
```
On Debian/Ubuntu/Kali/Pop!_OS/Mint that installs the `.deb` (launcher entry + a `clean-mind` command; GTK 3 pulled in automatically). On other distros it does a per-user tarball install (launcher entry + icon, no root needed).

Prefer manual? Download the `.deb` for your CPU from the assets below — `amd64` (Intel/AMD) or `arm64` (Raspberry Pi 5, Ampere, VMs on Apple-silicon Macs; not sure, run `dpkg --print-architecture`) — then, from the folder you downloaded it to (keep the `./`):
```
sudo apt install ./clean-mind_<version>_arm64.deb   # or _amd64.deb
```
Or grab the `linux-x64`/`linux-arm64` tarball, extract it, and either run `./clean-mind/clean_mind` directly or `./clean-mind/install.sh` for a per-user install.

### Windows
Easiest via [Scoop](https://scoop.sh):
```
scoop bucket add clean-mind https://github.com/MS-Teja/scoop-clean-mind
scoop install clean-mind
```
Or download the zip for your CPU from the assets below — `windows-x64` (Intel/AMD) or `windows-arm64` (Snapdragon X and other Arm PCs) — extract it, and run `clean_mind.exe`. If SmartScreen warns, click **More info → Run anyway**.

Issue reports for Linux and Windows are very welcome.
