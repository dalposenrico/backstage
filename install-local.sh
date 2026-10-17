#!/bin/bash
# Build, install, and relaunch the local development copy of goodvibrations HQ.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

SOURCE_APP="${SCRIPT_DIR}/goodvibrations HQ.app"
INSTALLED_APP="/Applications/goodvibrations HQ.app"
OLD_INSTALLED_APP="/Applications/Backstage.app"
PREVIOUS_BUILDS_DIR="${SCRIPT_DIR}/Previous Builds"

./build-app.sh --no-open

echo "▸ Installing goodvibrations HQ in /Applications..."
killall demos 2>/dev/null || true

# Keep every previously installed development build recoverable. Archives are
# timestamped instead of overwritten so a bad build never destroys the last
# known-good copy.
if [ -d "${INSTALLED_APP}" ]; then
    mkdir -p "${PREVIOUS_BUILDS_DIR}"
    BACKUP_STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
    BACKUP_ZIP="${PREVIOUS_BUILDS_DIR}/goodvibrations HQ ${BACKUP_STAMP}.zip"
    echo "▸ Archiving the currently installed build for rollback..."
    ditto -c -k --sequesterRsrc --keepParent "${INSTALLED_APP}" "${BACKUP_ZIP}"
    echo "  → ${BACKUP_ZIP}"
fi

if [ -w "/Applications" ] || [ -w "${INSTALLED_APP}" ]; then
    ditto "${SOURCE_APP}" "${INSTALLED_APP}"
else
    echo "  macOS needs your password to update /Applications."
    sudo ditto "${SOURCE_APP}" "${INSTALLED_APP}"
fi

if [ -f "${SCRIPT_DIR}/Assets/goodvibrations-icon.png" ]; then
    swift - "${INSTALLED_APP}" "${SCRIPT_DIR}/Assets/goodvibrations-icon.png" <<'EOF' 2>/dev/null || true
import AppKit
let appPath = CommandLine.arguments[1]
let iconPath = CommandLine.arguments[2]
if let img = NSImage(contentsOfFile: iconPath) {
    _ = NSWorkspace.shared.setIcon(img, forFile: appPath, options: [])
}
EOF
fi
touch "${INSTALLED_APP}"
killall Dock 2>/dev/null || true

if [ -d "${OLD_INSTALLED_APP}" ]; then
    OLD_TRASH_APP="${HOME}/.Trash/Backstage (previous version).app"
    echo "▸ Moving the previous Backstage app to the Trash..."
    if [ -e "${OLD_TRASH_APP}" ]; then
        OLD_TRASH_APP="${HOME}/.Trash/Backstage (previous version $(date +%s)).app"
    fi
    if [ -w "/Applications" ]; then
        mv "${OLD_INSTALLED_APP}" "${OLD_TRASH_APP}"
    else
        sudo mv "${OLD_INSTALLED_APP}" "${OLD_TRASH_APP}"
        sudo chown -R "$(id -u):$(id -g)" "${OLD_TRASH_APP}"
    fi
fi

echo "▸ Opening goodvibrations HQ..."
open -n "${INSTALLED_APP}"

echo "✓ goodvibrations HQ is installed and running."
