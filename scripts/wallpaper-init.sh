#!/usr/bin/env bash
# wallpaper-init — start the wallpaper daemon and pick a wallpaper from
# ~/Pictures/Wallpapers. The `swww` AUR package now ships its binaries as
# `awww`/`awww-daemon`, so resolve whichever name exists.
set -Eeuo pipefail

WP_DIR="$HOME/Pictures/Wallpapers"
TRANSITION_ARGS=(--transition-type grow --transition-pos 0.85,0.95 --transition-step 60 --transition-fps 60)

if command -v awww >/dev/null 2>&1; then
    WP_CLI=awww; WP_DAEMON=awww-daemon
elif command -v swww >/dev/null 2>&1; then
    WP_CLI=swww; WP_DAEMON=swww-daemon
else
    exit 0
fi

if ! pgrep -x "$WP_DAEMON" >/dev/null 2>&1; then
    # A stale socket from an unclean exit makes the new daemon refuse to start.
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/wayland-*-"$WP_DAEMON".sock 2>/dev/null || true
    "$WP_DAEMON" &
    disown
fi

# Wait for the daemon's IPC socket to come up instead of guessing with a fixed
# sleep — cold-boot startup can take well over a second.
for _ in $(seq 1 50); do
    "$WP_CLI" query >/dev/null 2>&1 && break
    sleep 0.1
done

mapfile -t imgs < <(find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort)
[[ ${#imgs[@]} -eq 0 ]] && exit 0

# Deterministic-on-startup but rotates across reboots: pick by day-of-year.
idx=$(( $(date +%j) % ${#imgs[@]} ))
"$WP_CLI" img "${imgs[$idx]}" "${TRANSITION_ARGS[@]}"
# Pre-blurred copy for gtklock's lock background (kept in sync with wallpaper).
if command -v magick >/dev/null 2>&1; then
    magick "${imgs[$idx]}" -resize 2560x1440^ -gravity center -extent 2560x1440 \
        -blur 0x16 -modulate 72 "$HOME/.cache/lockscreen-bg.jpg" || true
fi
