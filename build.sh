#!/bin/sh
# Build ClaudePace.app (menu-bar only, no Dock icon) into ./build.
set -eu
cd "$(dirname "$0")"

swift build -c release --build-system native --product ClaudePace
BIN="$(swift build -c release --build-system native --show-bin-path)/ClaudePace"
APP=build/ClaudePace.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudePace"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClaudePace</string>
    <key>CFBundleIdentifier</key><string>dev.meain.claudepace</string>
    <key>CFBundleExecutable</key><string>ClaudePace</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP"
