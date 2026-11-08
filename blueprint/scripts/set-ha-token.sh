#!/bin/bash
# Stores a Home Assistant long-lived access token for the blueprint dashboard, from the clipboard, without showing it.
# 1. In Home Assistant, sign in as the non-admin user made for this dashboard, open Profile > Security, create a
#    long-lived access token and copy it.
# 2. Run this script. It writes ~/.config/house-blueprint/ha-token (readable only by you) and clears the clipboard.
set -euo pipefail
umask 077
dir="$HOME/.config/house-blueprint"
mkdir -p "$dir"
token="$(pbpaste | tr -d '[:space:]')"
if [[ ! "$token" =~ ^[A-Za-z0-9._-]{100,}$ ]]; then
  echo "The clipboard doesn't hold a Home Assistant token. Copy the token and run this again." >&2
  exit 1
fi
printf '%s\n' "$token" > "$dir/ha-token"
chmod 600 "$dir/ha-token"
printf '' | pbcopy
echo "Saved to $dir/ha-token (only you can read it). Restart the dashboard's dev server to connect."
