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

### Linux (experimental)
Pick the tarball for your CPU — `linux-x64` (Intel/AMD) or `linux-arm64` (Raspberry Pi 5, Ampere, Apple-silicon VMs). Extract it, then either run `./clean-mind/clean_mind` directly or run `./clean-mind/install.sh` to install it for your user (launcher entry + icon, no root needed). Requires GTK 3.

### Windows (experimental)
Pick the zip for your CPU — `windows-x64` (Intel/AMD) or `windows-arm64` (Snapdragon X and other Arm PCs). Extract it and run `clean_mind.exe`. If SmartScreen warns, click **More info → Run anyway**.

Linux and Windows builds compile and pass tests in CI but have had less real-world testing than macOS — issue reports are very welcome.
