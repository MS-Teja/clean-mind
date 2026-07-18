#!/bin/sh
# Clean Mind installer for Linux.
#
#   curl -fsSL https://ms-teja.github.io/clean-mind/install.sh | sh
#
# Detects your CPU, downloads the latest release from GitHub, and installs
# the .deb on Debian-family systems (apt asks for sudo) or a per-user
# tarball install everywhere else (no root needed).
#
# Uninstall:  sudo apt remove clean-mind          (deb install)
#             ~/.local/opt/clean-mind + launcher entry are removed by
#             the bundled install.sh --uninstall  (tarball install)
set -eu

REPO="MS-Teja/clean-mind"

err() { echo "install: $*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] ||
    err "this installer is Linux-only; macOS and Windows installs: https://github.com/$REPO#install"
command -v curl >/dev/null 2>&1 || err "curl is required"

case "$(uname -m)" in
    x86_64 | amd64) deb_arch=amd64 tar_arch=x64 ;;
    aarch64 | arm64) deb_arch=arm64 tar_arch=arm64 ;;
    *) err "unsupported CPU architecture: $(uname -m)" ;;
esac

# Resolve the latest release tag (e.g. v1.2.1) from the GitHub API.
tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
    grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
[ -n "$tag" ] || err "could not determine the latest release"
version=${tag#v}
base="https://github.com/$REPO/releases/download/$tag"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

if command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    deb="clean-mind_${version}_${deb_arch}.deb"
    echo "Downloading $deb ($tag)..."
    curl -fL --progress-bar -o "$tmp/$deb" "$base/$deb"
    echo "Installing with apt..."
    if [ "$(id -u)" -eq 0 ]; then
        apt-get install -y "$tmp/$deb"
    else
        command -v sudo >/dev/null 2>&1 || err "sudo is required to install the .deb"
        sudo apt-get install -y "$tmp/$deb"
    fi
else
    tarball="CleanMind-${version}-linux-${tar_arch}.tar.gz"
    echo "Downloading $tarball ($tag)..."
    curl -fL --progress-bar -o "$tmp/$tarball" "$base/$tarball"
    tar -xzf "$tmp/$tarball" -C "$tmp"
    "$tmp/clean-mind/install.sh"
fi

echo
echo 'Done. Launch "Clean Mind" from your app launcher, or run: clean-mind'
