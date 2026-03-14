#!/bin/bash
# release.sh — Build, package, and publish a GitHub release.
#
# Usage:
#   bash release.sh              # auto-version (YY.MM.DD)
#   bash release.sh 26.03.14     # explicit version
#
# Requirements: gh CLI authenticated, build_app.sh succeeds.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-$(date '+%y.%m.%d')}"
TAG="v${VERSION}"

echo "=== Boomi SRE Release: ${TAG} ==="

# Build and create DMG
bash "$SCRIPT_DIR/build_app.sh"

# Find the DMG (build_app.sh names it Boomi-SRE-VERSION-TIMESTAMP.dmg)
DMG_PATH=$(ls -t "$SCRIPT_DIR/dist/Boomi-SRE-${VERSION}"*.dmg 2>/dev/null | head -1)
if [[ -z "$DMG_PATH" ]]; then
    echo "ERROR: No DMG found in dist/ for version ${VERSION}"
    exit 1
fi

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
