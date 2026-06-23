#!/usr/bin/env bash
# wallpaper-next — advance to the next wallpaper in ~/Pictures/Wallpapers/.
# Persists the current index in ~/.cache/wallpaper-index so cycles survive
# across invocations without repeating.
set -Eeuo pipefail

WP_DIR="$HOME/Pictures/Wallpapers"
CACHE="$HOME/.cache/wallpaper-index"
TRANSITION_ARGS=(--transition-type grow --transition-pos 0.85,0.95 --transition-step 60 --transition-fps 60)

mapfile -t imgs < <(find "$WP_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort)
[[ ${#imgs[@]} -eq 0 ]] && exit 0

if [[ -f "$CACHE" ]]; then
    idx=$(<"$CACHE")
    idx=$(( (idx + 1) % ${#imgs[@]} ))
else
    idx=0
fi
echo "$idx" > "$CACHE"

if command -v awww >/dev/null 2>&1; then
    awww img "${imgs[$idx]}" "${TRANSITION_ARGS[@]}"
elif command -v swww >/dev/null 2>&1; then
    swww img "${imgs[$idx]}" "${TRANSITION_ARGS[@]}"
elif command -v swaybg >/dev/null 2>&1; then
    pkill -x swaybg 2>/dev/null || true
    swaybg -i "${imgs[$idx]}" -m fill &
    disown
else
    exit 0
fi
# Pre-blurred copy for hyprlock's lock background (kept in sync with wallpaper).
if command -v magick >/dev/null 2>&1; then
    magick "${imgs[$idx]}" -resize 2560x1440^ -gravity center -extent 2560x1440 \
        -blur 0x16 -modulate 72 "$HOME/.cache/lockscreen-bg.jpg" || true
fi
