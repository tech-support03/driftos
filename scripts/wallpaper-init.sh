#!/usr/bin/env bash
# wallpaper-init — start swww-daemon and pick a wallpaper from ~/Pictures/Wallpapers.
set -Eeuo pipefail

WP_DIR="$HOME/Pictures/Wallpapers"
TRANSITION_ARGS=(--transition-type grow --transition-pos 0.85,0.95 --transition-step 60 --transition-fps 60)

pgrep -x swww-daemon >/dev/null 2>&1 || swww-daemon &
sleep 0.3

mapfile -t imgs < <(find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort)
[[ ${#imgs[@]} -eq 0 ]] && exit 0

# Deterministic-on-startup but rotates across reboots: pick by day-of-year.
idx=$(( $(date +%j) % ${#imgs[@]} ))
exec swww img "${imgs[$idx]}" "${TRANSITION_ARGS[@]}"
