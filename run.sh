#!/bin/bash
# Build and run Reeve as a proper .app bundle (required for MenuBarExtra)
set -e

VERSION=$(cat VERSION)

swift build

APP_DIR=".build/Reeve.app/Contents"
mkdir -p "$APP_DIR/MacOS"

# Create Info.plist
cat > "$APP_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.reeve.app</string>
    <key>CFBundleName</key>
    <string>Reeve</string>
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

# Copy binary
cp .build/arm64-apple-macosx/debug/reeve "$APP_DIR/MacOS/reeve"

# Launch
open .build/Reeve.app
