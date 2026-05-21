#!/usr/bin/env bash
# whatsapp-web.sh — open WhatsApp Web as a standalone Chromium app window.
#
# Replaces the whatsapp-for-linux AUR package, which is slow to build/download
# and frequently lags upstream. Chromium app mode with a dedicated profile gives
# a persistent login (scan the QR once) and its own window with a clean app-id
# (whatsapp-web) so window rules and the dock can target it.
set -Eeuo pipefail

URL="https://web.whatsapp.com/"
PROFILE_DIR="$HOME/.local/share/whatsapp-web"

# chromium ships in the base packages; fall back to common alternates in case
# the user swapped browsers.
browser=""
for b in chromium chromium-browser google-chrome-stable google-chrome brave brave-browser; do
    if command -v "$b" >/dev/null 2>&1; then
        browser="$b"
        break
    fi
done

if [[ -z "$browser" ]]; then
    notify-send -a "dock" "WhatsApp Web" "No Chromium-family browser found" 2>/dev/null || true
    exit 1
fi

mkdir -p "$PROFILE_DIR"

# --class sets the Wayland app_id so niri window rules / the dock can match it.
# --ozone-platform-hint=auto lets chromium pick the Wayland backend natively.
exec "$browser" \
    --app="$URL" \
    --user-data-dir="$PROFILE_DIR" \
    --class=whatsapp-web \
    --ozone-platform-hint=auto \
    "$@"
