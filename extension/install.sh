#!/usr/bin/env bash
# Install RooTerm GNOME Shell extension into the user extensions dir.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UUID="rooterm@roojs.com"
SRC="$ROOT/extension/$UUID"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
SCHEMA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/glib-2.0/schemas"

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -a "$SRC" "$DEST"
glib-compile-schemas "$DEST/schemas"

mkdir -p "$SCHEMA_DIR"
cp "$DEST/schemas/"*.xml "$SCHEMA_DIR/"
glib-compile-schemas "$SCHEMA_DIR"

gnome-extensions enable "$UUID" || true

echo "Installed $DEST"
