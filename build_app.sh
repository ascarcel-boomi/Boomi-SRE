#!/bin/bash
# Build Boomi SRE as a native macOS .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Boomi SRE"
APP_DIR="/Applications/${APP_NAME}.app"
BUNDLE_ID="com.boomi.sre-reports"

# Version format: YY.MM.DD-HHMMSS  (e.g. 26.03.13-235518)
# Build format:   YYYYMMDDHHMMSS    (numeric, for CFBundleVersion)
VERSION="$(date '+%y.%m.%d-%H%M%S')"
BUILD="$(date '+%Y%m%d%H%M%S')"

echo "Building ${APP_NAME} v${VERSION}..."

# Build release binary
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | tail -3

BINARY="$SCRIPT_DIR/.build/release/BoomiSRE"
if [[ ! -f "$BINARY" ]]; then
    echo "Build failed — binary not found"
    exit 1
fi

# Create .app bundle
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/BoomiSRE"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>BoomiSRE</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

# Use pre-built Boomi logo icon if available, otherwise generate a placeholder
if [[ -f "$SCRIPT_DIR/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "Boomi logo icon installed"
fi

# Generate AUTHORS from git commit history (one name per line, sorted by commit count)
git -C "$SCRIPT_DIR" shortlog -sn --no-merges HEAD \
    | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' \
    > "$APP_DIR/Contents/Resources/AUTHORS"
echo "Authors: $(wc -l < "$APP_DIR/Contents/Resources/AUTHORS" | tr -d ' ') contributor(s) listed"

# Register
touch "$APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

echo ""
echo "=== Build complete ==="
echo "Version: ${VERSION}"
echo "Build:   ${BUILD}"
echo "App: $APP_DIR"
echo "Launch: open -a 'Boomi SRE'"
