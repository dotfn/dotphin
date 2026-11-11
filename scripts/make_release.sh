#!/bin/zsh
# Arma Dotphin-<versión>.zip para un release de GitHub y muestra el sha256
# que va en el cask de dotfn/homebrew-tap.
#
#   scripts/make_release.sh 0.1.0-beta
set -euo pipefail

VERSION="${1:?Uso: scripts/make_release.sh <versión>  (ej. 0.1.0-beta)}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/dist"
APP_PATH="$DIST_DIR/Dotphin.app"
ZIP_PATH="$DIST_DIR/Dotphin-${VERSION}.zip"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# El bundle lleva la parte numérica ("0.1.0-beta" → "0.1.0").
APP_VERSION="${VERSION%%-*}" "$ROOT_DIR/scripts/build_app_bundle.sh" "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"

# ditto conserva symlinks y metadatos; Archive Utility/zip pueden romper la firma.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "Zip:    $ZIP_PATH"
echo "sha256: $(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)"
