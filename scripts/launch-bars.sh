#!/usr/bin/env bash
# launch-bars — restart both waybar instances cleanly. Useful after editing CSS.
set -Eeuo pipefail

pkill -x waybar || true
sleep 0.2
waybar -c "$HOME/.config/waybar-top/config.jsonc"  -s "$HOME/.config/waybar-top/style.css"  >/dev/null 2>&1 &
disown
waybar -c "$HOME/.config/waybar-side/config.jsonc" -s "$HOME/.config/waybar-side/style.css" >/dev/null 2>&1 &
disown
