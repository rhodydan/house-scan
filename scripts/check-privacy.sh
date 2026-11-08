#!/bin/bash
# Checks that the app has no network code, against the source and a built app:
# no networking APIs, no third-party code, no entitlements that open a route off the device.
# Usage: scripts/check-privacy.sh [path/to/HouseScan.app]
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
fail() { echo "FAIL: $1"; status=1; }

patterns='URLSession|URLRequest|NWConnection|NWPathMonitor|NWListener|CFSocket|CFStream|WKWebView|SFSafariViewController|CloudKit|CKContainer|NSUbiquitous|FirebaseApp|Analytics|Crashlytics|Sentry|import Network|import MetricKit'
if grep -rnE "$patterns" HouseScan --include='*.swift'; then
    fail "networking, cloud or analytics API in the app source"
else
    echo "ok: no networking, cloud or analytics APIs in the source"
fi

if grep -nE '^\s*packages:|dependencies:\s*$' project.yml | grep -q packages; then
    fail "project.yml declares packages"
else
    echo "ok: no third-party packages"
fi

if grep -qE 'entitlements:' project.yml; then
    fail "project.yml declares entitlements (iCloud, push and the like need these)"
else
    echo "ok: no entitlements declared"
fi

if grep -qE 'NSAppTransportSecurity|UIFileSharingEnabled|LSSupportsOpeningDocumentsInPlace' project.yml; then
    fail "Info.plist opens the app's files or the network"
else
    echo "ok: no transport exceptions, and app files aren't exposed to the Files app"
fi

app="${1:-}"
if [ -n "$app" ]; then
    binary="$app/$(basename "$app" .app)"
    [ -f "$app/$(basename "$app" .app).debug.dylib" ] && binary="$app/$(basename "$app" .app).debug.dylib"
    if nm -u "$binary" | grep -E 'NSURLSession|URLSession|nw_connection|nw_endpoint|_socket$|_connect$|CKContainer'; then
        fail "built binary imports networking symbols"
    else
        echo "ok: built binary imports no networking symbols ($(basename "$binary"))"
    fi
fi
exit $status
