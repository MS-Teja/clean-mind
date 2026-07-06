#!/bin/sh
# Install Clean Mind for the current user (no root needed).
# Copies the bundle to ~/.local/opt/clean-mind, links the binary into
# ~/.local/bin, and registers the desktop entry + icon so the app shows up
# in your launcher. Run from the extracted tarball directory.
#
#   ./install.sh            install / upgrade
#   ./install.sh --uninstall  remove everything it installed
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
opt="${HOME}/.local/opt/clean-mind"
bin="${HOME}/.local/bin"
apps="${HOME}/.local/share/applications"
icons="${HOME}/.local/share/icons/hicolor/512x512/apps"
desktop_id="io.github.msteja.cleanmind"

if [ "${1:-}" = "--uninstall" ]; then
    rm -rf "$opt"
    rm -f "$bin/clean-mind" "$apps/$desktop_id.desktop" "$icons/$desktop_id.png"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" || true
    echo "Clean Mind uninstalled."
    exit 0
fi

if [ ! -x "$here/clean_mind" ]; then
    echo "error: run this from the extracted clean-mind directory (clean_mind binary not found)" >&2
    exit 1
fi

mkdir -p "$opt" "$bin" "$apps" "$icons"

# Copy the whole bundle (binary, lib/, data/) but not the packaging files.
cp -R "$here/." "$opt/"
rm -f "$opt/install.sh" "$opt/$desktop_id.desktop" "$opt/$desktop_id.png"

ln -sf "$opt/clean_mind" "$bin/clean-mind"
cp "$here/$desktop_id.png" "$icons/$desktop_id.png"

# Desktop entries need an absolute Exec, so rewrite it on install.
sed "s|^Exec=.*|Exec=$opt/clean_mind|" "$here/$desktop_id.desktop" > "$apps/$desktop_id.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" || true

echo "Installed to $opt"
echo "Launch \"Clean Mind\" from your app launcher, or run: $bin/clean-mind"
case ":$PATH:" in
    *":$bin:"*) ;;
    *) echo "note: $bin is not on your PATH" ;;
esac
