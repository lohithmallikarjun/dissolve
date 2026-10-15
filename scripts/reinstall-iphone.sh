#!/usr/bin/env bash
# Rebuilds Dissolve and reinstalls it on your iPhone over Wi-Fi, renewing the free account's
# 7-day signature. Reinstalling over the old app keeps all data.
#
# One-time setup: see "Weekly reinstall" in README.md.
# Usage: scripts/reinstall-iphone.sh
set -euo pipefail
cd "$(dirname "$0")/.."

log() { echo "[$(date '+%Y-%m-%d %H:%M')] $*"; }

config=scripts/device.local
if [ ! -f "$config" ]; then
  echo "Missing $config. Run: xcrun devicectl list devices"
  echo "then: echo 'DEVICE_ID=<the iPhone Identifier>' > $config"
  exit 1
fi
# shellcheck source=/dev/null
source "$config"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
log "Pulling latest code"
git pull --ff-only || log "git pull skipped (local changes?)"

log "Generating project"
xcodegen generate --quiet

log "Building for device $DEVICE_ID"
xcodebuild -project Dissolve.xcodeproj -scheme Dissolve -configuration Debug \
  -destination "generic/platform=iOS" -derivedDataPath build/reinstall \
  -allowProvisioningUpdates build -quiet

APP=build/reinstall/Build/Products/Debug-iphoneos/Dissolve.app
log "Installing $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
log "Done. Dissolve is signed for another 7 days."
