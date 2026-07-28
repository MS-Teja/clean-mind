# What's new in 1.2.3

- **Windows: install via winget.** Getting the package accepted needed a change on both sides. The manifest now tells winget to put the install directory on `PATH` rather than launching Clean Mind through a symlink, which is what lets the app find the runtime libraries shipped alongside it. Separately, the app no longer assumes it was started from its own install directory, so it locates its bundled assets correctly when something launches it indirectly.
- **Windows: the executable is now `clean-mind.exe`** (previously `clean_mind.exe`), so the command on your `PATH` is `clean-mind` — the same name Linux already uses. If you pinned a shortcut, wrote a script, or made a scheduled task pointing at the old file name, update it after upgrading. Nothing changes on macOS or Linux.

The scanning engine and everything else are unchanged since [1.2.2](https://github.com/MS-Teja/clean-mind/releases/tag/v1.2.2).
