#!/bin/bash
# Builds for your iPhone and installs it, or runs the on-device tests. The phone must be unlocked and connected.
# Reads the signing team from HOUSE_SCAN_TEAM or ~/.config/house-scan/team, and the phone's name (as Xcode lists it)
# from HOUSE_SCAN_PHONE or ~/.config/house-scan/phone.
# Usage: scripts/phone.sh install | test
set -euo pipefail
cd "$(dirname "$0")/.."
export HOUSE_SCAN_TEAM="${HOUSE_SCAN_TEAM:-$(cat ~/.config/house-scan/team 2>/dev/null)}"
PHONE="${HOUSE_SCAN_PHONE:-$(cat ~/.config/house-scan/phone 2>/dev/null)}"
[[ -n "$HOUSE_SCAN_TEAM" && -n "$PHONE" ]] || { echo "Set HOUSE_SCAN_TEAM and HOUSE_SCAN_PHONE (or ~/.config/house-scan/team and phone)." >&2; exit 2; }
xcodegen >/dev/null

phone_udid() { xcrun xctrace list devices 2>/dev/null | grep -F "$PHONE (" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\)$/\1/'; }

case "${1:-}" in
install)
    xcodebuild build -project HouseScan.xcodeproj -scheme HouseScan -destination 'generic/platform=iOS' \
        -derivedDataPath build-device -allowProvisioningUpdates -quiet
    xcrun devicectl device install app --device "$(phone_udid)" build-device/Build/Products/Debug-iphoneos/HouseScan.app
    ;;
test)
    xcodebuild test -project HouseScan.xcodeproj -scheme HouseScan -destination "id=$(phone_udid)" \
        -derivedDataPath build-device -allowProvisioningUpdates -only-testing:HouseScanTests 2>&1 |
        grep -E 'DEVICE |error:|Executed|\*\* TEST'
    ;;
*)
    echo "Usage: scripts/phone.sh install | test" >&2
    exit 2
    ;;
esac
