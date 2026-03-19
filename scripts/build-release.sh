#!/bin/bash
# Build Reeve.app release bundle and package as .dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-$(cat "$PROJECT_DIR/VERSION")}"
BUILD_DIR="$PROJECT_DIR/.build/release-bundle"
APP_DIR="$BUILD_DIR/Reeve.app/Contents"
DMG_OUTPUT="$PROJECT_DIR/.build/Reeve-${VERSION}.dmg"

echo "Building Reeve v${VERSION}..."

# Clean previous release bundle
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/MacOS"

# Build release binary
cd "$PROJECT_DIR"
swift build -c release

# Create Info.plist
cat > "$APP_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.reeve.app</string>
    <key>CFBundleName</key>
    <string>reeve</string>
    <key>CFBundleExecutable</key>
    <string>reeve</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Copy release binary
cp .build/release/reeve "$APP_DIR/MacOS/reeve"

echo "Created Reeve.app at $BUILD_DIR/Reeve.app"

# Package as DMG
echo "Creating DMG..."
rm -f "$DMG_OUTPUT"

create-dmg \
    --volname "Reeve" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Reeve.app" 175 190 \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$BUILD_DIR/Reeve.app"

echo "Created DMG at $DMG_OUTPUT"
echo "SHA256: $(shasum -a 256 "$DMG_OUTPUT" | awk '{print $1}')"
