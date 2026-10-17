#!/bin/bash
# Restore the most recently archived local development build.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREVIOUS_BUILDS_DIR="${SCRIPT_DIR}/Previous Builds"
INSTALLED_APP="/Applications/goodvibrations HQ.app"
RESTORE_DIR="$(mktemp -d)"
trap 'rm -rf "${RESTORE_DIR}"' EXIT

LATEST_BACKUP="$(find "${PREVIOUS_BUILDS_DIR}" -maxdepth 1 -name 'goodvibrations HQ *.zip' -print 2>/dev/null | sort | tail -n 1)"
if [ -z "${LATEST_BACKUP}" ]; then
    echo "No previous goodvibrations HQ build is available."
    exit 1
fi

echo "▸ Restoring $(basename "${LATEST_BACKUP}")..."
ditto -x -k "${LATEST_BACKUP}" "${RESTORE_DIR}"
killall demos 2>/dev/null || true

if [ -w "/Applications" ] || [ -w "${INSTALLED_APP}" ]; then
    ditto "${RESTORE_DIR}/goodvibrations HQ.app" "${INSTALLED_APP}"
else
    sudo ditto "${RESTORE_DIR}/goodvibrations HQ.app" "${INSTALLED_APP}"
fi

open -n "${INSTALLED_APP}"
echo "✓ Previous goodvibrations HQ build restored and running."
