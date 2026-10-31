#!/usr/bin/env bash
# Installs the project toolchain (Rojo, luau-lsp + Roblox type definitions, Lune) into .tools/bin.
# Usage: tools/setup.sh            then: FR_BIN=.tools/bin tools/check.sh  (check.sh finds .tools/bin by itself)
# Works on Linux x86_64 and macOS (arm64/x86_64). Needs curl and unzip.
set -euo pipefail
cd "$(dirname "$0")/.."

ROJO_VERSION="7.4.4"
LUAU_LSP_VERSION="1.54.0"
LUNE_VERSION="0.10.4"

DEST="${FR_BIN:-.tools/bin}"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

os="$(uname -s)"; arch="$(uname -m)"
case "$os-$arch" in
  Linux-x86_64)  rojo_asset="rojo-${ROJO_VERSION}-linux-x86_64.zip"; lsp_asset="luau-lsp-linux-x86_64.zip"; lune_asset="lune-${LUNE_VERSION}-linux-x86_64.zip" ;;
  Linux-aarch64) rojo_asset="rojo-${ROJO_VERSION}-linux-aarch64.zip"; lsp_asset="luau-lsp-linux-arm64.zip"; lune_asset="lune-${LUNE_VERSION}-linux-aarch64.zip" ;;
  Darwin-arm64)  rojo_asset="rojo-${ROJO_VERSION}-macos-aarch64.zip"; lsp_asset="luau-lsp-macos.zip"; lune_asset="lune-${LUNE_VERSION}-macos-aarch64.zip" ;;
  Darwin-x86_64) rojo_asset="rojo-${ROJO_VERSION}-macos-x86_64.zip"; lsp_asset="luau-lsp-macos.zip"; lune_asset="lune-${LUNE_VERSION}-macos-x86_64.zip" ;;
  *) echo "unsupported platform: $os-$arch" >&2; exit 1 ;;
esac

fetch() { # url zipname
  echo "downloading $2"
  curl -fsSL -o "$TMP/$2" "$1"
  unzip -o -q "$TMP/$2" -d "$DEST"
}

fetch "https://github.com/rojo-rbx/rojo/releases/download/v${ROJO_VERSION}/${rojo_asset}" rojo.zip
fetch "https://github.com/JohnnyMorganz/luau-lsp/releases/download/${LUAU_LSP_VERSION}/${lsp_asset}" lsp.zip
fetch "https://github.com/lune-org/lune/releases/download/v${LUNE_VERSION}/${lune_asset}" lune.zip
echo "downloading Roblox type definitions"
# Current Roblox API surface (the code targets the live engine API, e.g. Player:LoadCharacterAsync).
curl -fsSL -o "$DEST/globalTypes.d.luau" \
  "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
chmod +x "$DEST"/rojo "$DEST"/luau-lsp "$DEST"/lune

"$DEST/rojo" --version
"$DEST/lune" --version
echo "luau-lsp $("$DEST/luau-lsp" --version)"
echo "tools installed in $DEST"
