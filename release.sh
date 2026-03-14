#!/bin/bash
# release.sh — Build, package, and publish a GitHub release.
#
# Usage:
#   bash release.sh              # auto-version (YY.MM.DD-HHMMSS from build)
#
# Requirements: gh CLI authenticated, build_app.sh succeeds.
#
# The tag uses the full version string from the DMG (YY.MM.DD-HHMMSS) so that
# the in-app Check for Updates lexicographic comparison works correctly.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Boomi SRE Release ==="

# Build and create DMG
bash "$SCRIPT_DIR/build_app.sh"

# Find the newest DMG — extract the full version (YY.MM.DD-HHMMSS) from its name
DMG_PATH=$(ls -t "$SCRIPT_DIR/dist/Boomi-SRE-"*.dmg 2>/dev/null | head -1)
if [[ -z "$DMG_PATH" ]]; then
    echo "ERROR: No DMG found in dist/"
    exit 1
fi

# Extract version from filename: Boomi-SRE-YY.MM.DD-HHMMSS.dmg
DMG_BASENAME="$(basename "$DMG_PATH" .dmg)"   # Boomi-SRE-YY.MM.DD-HHMMSS
VERSION="${DMG_BASENAME#Boomi-SRE-}"           # YY.MM.DD-HHMMSS
TAG="v${VERSION}"

echo ""
echo "Publishing release ${TAG}..."
gh release create "${TAG}" "${DMG_PATH}" \
    --title "Boomi SRE ${TAG}" \
    --notes "## Boomi SRE ${TAG}

### Installation
1. Download \`$(basename "$DMG_PATH")\`
2. Open the DMG and drag **Boomi SRE** to Applications
3. On first launch: right-click → Open (bypass Gatekeeper for unsigned app)

### What's New
See [commit history](https://github.com/ascarcel-boomi/Boomi-SRE/commits/main) for changes in this release.
"

echo ""
echo "Release ${TAG} published: https://github.com/ascarcel-boomi/Boomi-SRE/releases/tag/${TAG}"
echo ""
echo "Installed app version will see '${VERSION}' < this tag on next Check for Updates."
