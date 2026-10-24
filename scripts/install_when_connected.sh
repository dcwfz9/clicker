#!/bin/zsh
# Waits for the iPhone to become reachable from this Mac (cable or Wi‑Fi debugging), then builds,
# installs and launches Clicker on it. Logs to the path in $1 (default: /tmp/clicker-install.log).
# Usage: scripts/install_when_connected.sh [logfile] [max_minutes]
set -u
cd "$(dirname "$0")/.."
LOG=${1:-/tmp/clicker-install.log}
MAX_MIN=${2:-180}
# The first iPhone that is connected or available; set UDID=... to pin one.
UDID=${UDID:-}
APP=build/DerivedDataDevice/Build/Products/Debug-iphoneos/Clicker.app
log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

log "waiting for the iPhone (up to $MAX_MIN min)"
end=$(( $(date +%s) + MAX_MIN * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
  line=$(xcrun devicectl list devices 2>/dev/null | grep -i iphone | grep -E "[0-9A-F-]{36} +(connected|available)" | { [ -n "$UDID" ] && grep "$UDID" || cat; } | head -1)
  state=$(echo "$line" | grep -oE "(connected|available)[^ ]*" | head -1)
  found=$(echo "$line" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)
  if [ -n "$found" ]; then
    UDID=$found
    log "iPhone is $state; building for device"
    if xcodebuild -project Clicker.xcodeproj -scheme Clicker -destination "id=$UDID" \
         -derivedDataPath build/DerivedDataDevice -allowProvisioningUpdates -quiet build >> "$LOG" 2>&1; then
      log "build ok; installing"
      if xcrun devicectl device install app --device "$UDID" "$APP" >> "$LOG" 2>&1; then
        log "installed; launching"
        xcrun devicectl device process launch --device "$UDID" derekwelty.clicker >> "$LOG" 2>&1 && log "LAUNCHED on the iPhone" || log "launch failed (installed anyway)"
        exit 0
      else
        log "install failed"; exit 1
      fi
    else
      log "device build failed"; exit 1
    fi
  fi
  sleep 20
done
log "gave up: iPhone never became reachable"
exit 2
