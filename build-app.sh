#!/bin/bash
# Builds Backstage.app — drag it to /Applications or zip it to share with friends.
# Requires macOS 14 (Sonoma) or later.
# First launch: right-click > Open to clear the Gatekeeper warning (ad-hoc signed).

set -e

APP_NAME="demos"
DISPLAY_NAME="Backstage"
BUILD_DIR=".build/release"
APP_BUNDLE="${DISPLAY_NAME}.app"
ICONSET="AppIcon.iconset"
ICNS="AppIcon.icns"

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "▸ Building release binary..."
swift build -c release

# ── 2. Generate icon ──────────────────────────────────────────────────────────
echo "▸ Generating icon..."
rm -rf "${ICONSET}" "${ICNS}"
swift make-icon.swift "${ICONSET}"
iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${ICONSET}"

# ── 3. Assemble .app bundle ───────────────────────────────────────────────────
echo "▸ Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}"     "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Sources/demos/Info.plist"     "${APP_BUNDLE}/Contents/Info.plist"
cp "${ICNS}"                      "${APP_BUNDLE}/Contents/Resources/${ICNS}"

# ── 4. Ad-hoc sign ────────────────────────────────────────────────────────────
echo "▸ Signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✓ ${APP_BUNDLE} is ready."
echo "  → Drag to /Applications to install."
echo "  → Zip to share (friends right-click > Open on first launch)."
echo ""
open .
