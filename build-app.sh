#!/bin/bash
# Builds goodvibrations HQ.app — drag it to /Applications or zip it to share with friends.
# Requires macOS 14 (Sonoma) or later.
# First launch: right-click > Open to clear the Gatekeeper warning (ad-hoc signed).

set -e

OPEN_WHEN_DONE=true
if [ "${1:-}" = "--no-open" ]; then
    OPEN_WHEN_DONE=false
fi

APP_NAME="demos"
DISPLAY_NAME="goodvibrations HQ"
BUILD_DIR=".build/release"
APP_BUNDLE="${DISPLAY_NAME}.app"
ICONSET="AppIcon.iconset"
ICNS="AppIcon.icns"
ICON_SOURCE="Assets/goodvibrations-icon.png"

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "▸ Building release binary..."
swift build -c release

# ── 2. Generate icon ──────────────────────────────────────────────────────────
echo "▸ Generating icon..."
rm -rf "${ICONSET}" "${ICNS}"
if [ -f "${ICON_SOURCE}" ]; then
    mkdir -p "${ICONSET}"
    while read -r size filename; do
        sips -z "${size}" "${size}" "${ICON_SOURCE}" --out "${ICONSET}/${filename}" >/dev/null
        echo "  ✓ ${filename}"
    done <<'ICON_SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
ICON_SIZES
else
    swift make-icon.swift "${ICONSET}"
fi
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
cp "Scripts/ableton_version_export.py" "${APP_BUNDLE}/Contents/Resources/ableton_version_export.py"

# ── 4. Bundle Ableton Crash Analyzer ─────────────────────────────────────────
ANALYZER_APP="${APP_BUNDLE}/Contents/Applications/Ableton Crash Analyzer.app"
mkdir -p "${ANALYZER_APP}/Contents/MacOS"
cp "${BUILD_DIR}/AbletonCrashAnalyzer" "${ANALYZER_APP}/Contents/MacOS/AbletonCrashAnalyzer"
cp "Sources/AbletonCrashAnalyzer/Info.plist" "${ANALYZER_APP}/Contents/Info.plist"

# ── 5. Bundle widget extension ────────────────────────────────────────────────
echo "▸ Bundling widget extension..."
WIDGET_APPEX="${APP_BUNDLE}/Contents/PlugIns/BackstageWidget.appex"
mkdir -p "${WIDGET_APPEX}/Contents/MacOS"

cp "${BUILD_DIR}/BackstageWidget"              "${WIDGET_APPEX}/Contents/MacOS/BackstageWidget"
cp "Sources/BackstageWidget/Info.plist"        "${WIDGET_APPEX}/Contents/Info.plist"

# ── 6. Strip debug symbols ────────────────────────────────────────────────────
# Swift release builds keep local symbols by default. Removing them before
# signing takes the app from ~14 MB to ~6 MB and must happen before codesign.
echo "▸ Stripping debug symbols..."
strip -x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
strip -x "${ANALYZER_APP}/Contents/MacOS/AbletonCrashAnalyzer"
strip -x "${WIDGET_APPEX}/Contents/MacOS/BackstageWidget"

# ── 7. Ad-hoc sign ────────────────────────────────────────────────────────────
echo "▸ Signing..."
WIDGET_REQUIREMENT='=designated => identifier "com.enricodalpos.goodvibrationshq.widget"'
ANALYZER_REQUIREMENT='=designated => identifier "com.enricodalpos.ableton-crash-analyzer"'
APP_REQUIREMENT='=designated => identifier "com.enricodalpos.goodvibrationshq"'
codesign --force --sign - --requirements "${WIDGET_REQUIREMENT}" "${WIDGET_APPEX}"
codesign --force --sign - --requirements "${ANALYZER_REQUIREMENT}" "${ANALYZER_APP}"
codesign --force --sign - --requirements "${APP_REQUIREMENT}" "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

# ── 8. Install to /Applications ───────────────────────────────────────────────
INSTALLED_APP="/Applications/${APP_BUNDLE}"
if [ -d "${INSTALLED_APP}" ] || [ -w "/Applications" ]; then
    echo "▸ Updating ${INSTALLED_APP}..."
    ditto "${APP_BUNDLE}" "${INSTALLED_APP}"
    if [ -f "${ICON_SOURCE}" ]; then
        swift - "${INSTALLED_APP}" "${ICON_SOURCE}" <<'EOF' 2>/dev/null || true
import AppKit
let appPath = CommandLine.arguments[1]
let iconPath = CommandLine.arguments[2]
if let img = NSImage(contentsOfFile: iconPath) {
    _ = NSWorkspace.shared.setIcon(img, forFile: appPath, options: [])
}
EOF
    fi
    touch "${INSTALLED_APP}"
    echo "✓ Updated ${INSTALLED_APP}"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✓ ${APP_BUNDLE} is ready and updated in /Applications."
echo "  → Zip to share (friends right-click > Open on first launch)."
echo ""
if [ "${OPEN_WHEN_DONE}" = true ]; then
    open .
fi

