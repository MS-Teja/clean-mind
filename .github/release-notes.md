# What's new in 1.2.2

- **Correct storage figures on Windows and Linux:** sizes now follow each platform's own convention — 1024-based GB on Windows (matching File Explorer and Settings → Storage) and GiB on Linux (matching `df` and `du`) — instead of the decimal units that only line up with macOS. Free-space readouts and item sizes no longer read slightly high next to the numbers the OS reports itself. macOS is unchanged (decimal, matching Finder).
- **Simpler Linux install:** a one-line installer now does the work — `curl -fsSL https://ms-teja.github.io/clean-mind/install.sh | sh` detects your CPU and installs the `.deb` on Debian/Ubuntu/Kali/Mint, or a per-user build on other distros. The manual `.deb` and tarball options remain.

The scanning engine and everything else are unchanged since [1.2.1](https://github.com/MS-Teja/clean-mind/releases/tag/v1.2.1).
