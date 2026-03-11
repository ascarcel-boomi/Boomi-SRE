#!/bin/bash
# Build Boomi SRE as a native macOS .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Boomi SRE"
APP_DIR="/Applications/${APP_NAME}.app"
BUNDLE_ID="com.boomi.sre-reports"

echo "Building ${APP_NAME}..."

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
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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

# Generate icon (reuse Pillow if available from the old app, otherwise skip)
PYTHON="$HOME/aws_cost_agent_env/bin/python3"
if [[ -x "$PYTHON" ]]; then
    "$PYTHON" -c "
import os
try:
    from PIL import Image, ImageDraw, ImageFont
    img = Image.new('RGBA', (1024, 1024), (30, 30, 46, 255))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, 1023, 1023], radius=200, fill=(30, 30, 46))
    draw.ellipse([252, 180, 772, 700], outline=(137, 180, 250), width=24)
    try:
        fb = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 144)
        fs = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 72)
    except: fb = fs = ImageFont.load_default()
    draw.text((512, 440), 'SRE', fill=(137, 180, 250), font=fb, anchor='mm')
    draw.text((512, 800), 'Reports', fill=(166, 173, 200), font=fs, anchor='mm')
    iconset = '/tmp/BoomiSREIcon.iconset'
    os.makedirs(iconset, exist_ok=True)
    for s in [16, 32, 128, 256, 512]:
        img.resize((s, s), Image.LANCZOS).save(f'{iconset}/icon_{s}x{s}.png')
        img.resize((s*2, s*2), Image.LANCZOS).save(f'{iconset}/icon_{s}x{s}@2x.png')
    print('Icon generated')
except ImportError:
    print('Pillow not available, skipping icon')
" 2>/dev/null
    if [[ -d /tmp/BoomiSREIcon.iconset ]]; then
        iconutil -c icns /tmp/BoomiSREIcon.iconset -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null
        rm -rf /tmp/BoomiSREIcon.iconset
    fi
fi

# Register
touch "$APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

echo ""
echo "=== Build complete ==="
echo "App: $APP_DIR"
echo "Launch: open -a 'Boomi SRE'"
