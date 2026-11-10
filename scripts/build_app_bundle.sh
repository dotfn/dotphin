#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Dotphin"
BUNDLE_DIR="${1:-$ROOT_DIR/.build/${APP_NAME}.app}"

echo "Compilando Dotphin (release)..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE="$BIN_PATH/Dotphin"
RESOURCE_BUNDLE="$BIN_PATH/Dotphin_Dotphin.bundle"

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$EXECUTABLE" "$BUNDLE_DIR/Contents/MacOS/Dotphin"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$BUNDLE_DIR/Contents/Resources/"
fi
if [ -f "$ROOT_DIR/Sources/Dotphin/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Sources/Dotphin/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleExecutable</key>
    <string>Dotphin</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.dotphin.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Dotphin</string>
    <key>CFBundleDisplayName</key>
    <string>Dotphin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 ●fn</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$BUNDLE_DIR" 2>/dev/null || true
echo "App bundle generado en: $BUNDLE_DIR"
