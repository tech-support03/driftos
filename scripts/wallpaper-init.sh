#!/usr/bin/env bash
# wallpaper-init — start the wallpaper daemon and pick a wallpaper from
# ~/Pictures/Wallpapers. The `swww` AUR package now ships its binaries as
# `awww`/`awww-daemon`, so resolve whichever name exists.
set -Eeuo pipefail

WP_DIR="$HOME/Pictures/Wallpapers"
TRANSITION_ARGS=(--transition-type grow --transition-pos 0.85,0.95 --transition-step 60 --transition-fps 60)

mapfile -t imgs < <(find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort)
[[ ${#imgs[@]} -eq 0 ]] && exit 0

# Deterministic-on-startup but rotates across reboots: pick by day-of-year.
idx=$(( $(date +%j) % ${#imgs[@]} ))

if command -v awww >/dev/null 2>&1; then
    WP_CLI=awww; WP_DAEMON=awww-daemon
elif command -v swww >/dev/null 2>&1; then
    WP_CLI=swww; WP_DAEMON=swww-daemon
else
    WP_CLI=""
fi

if [[ -n "$WP_CLI" ]]; then
    WP_DAEMON="${WP_CLI}-daemon"
    if ! pgrep -x "$WP_DAEMON" >/dev/null 2>&1; then
        rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/wayland-*-"$WP_DAEMON".sock 2>/dev/null || true
        "$WP_DAEMON" &
        disown
    fi
    for _ in $(seq 1 50); do
        "$WP_CLI" query >/dev/null 2>&1 && break
        sleep 0.1
    done
    "$WP_CLI" img "${imgs[$idx]}" "${TRANSITION_ARGS[@]}"
elif command -v swaybg >/dev/null 2>&1; then
    pkill -x swaybg 2>/dev/null || true
    swaybg -i "${imgs[$idx]}" -m fill &
    disown
else
    exit 0
fi
# Pre-blurred copy for gtklock's lock background (kept in sync with wallpaper).
if command -v magick >/dev/null 2>&1; then
    magick "${imgs[$idx]}" -resize 2560x1440^ -gravity center -extent 2560x1440 \
        -blur 0x16 -modulate 72 "$HOME/.cache/lockscreen-bg.jpg" || true
fi
