#!/usr/bin/env bash
# volume-status — waybar JSON for the side-bar volume module. Icon reflects
# mute state and level; scroll handlers in the waybar config change volume.
set -Eeuo pipefail

# `wpctl get-volume` prints e.g. "Volume: 0.40" or "Volume: 0.40 [MUTED]".
line="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "Volume: 0.0")"
vol="$(printf '%s' "$line" | awk '{print $2}')"
pct="$(awk -v v="${vol:-0}" 'BEGIN { printf "%d", v * 100 }')"

if printf '%s' "$line" | grep -q '\[MUTED\]'; then
    icon="󰸈"; cls="muted"
elif (( pct < 34 )); then
    icon="󰕿"; cls="low"
elif (( pct < 67 )); then
    icon="󰖀"; cls="medium"
else
    icon="󰕾"; cls="high"
fi

printf '{"text":"%s","tooltip":"Volume %s%%","class":"%s"}\n' "$icon" "$pct" "$cls"
