#!/usr/bin/env bash
# media-status — single-shot waybar JSON describing the active MPRIS player.
set -Eeuo pipefail

status="$(playerctl status 2>/dev/null || echo "")"
case "$status" in
    Playing) glyph="" ;;
    Paused)  glyph="" ;;
    *)       printf '{"text":""}\n'; exit 0 ;;
esac

artist="$(playerctl metadata artist 2>/dev/null || echo "")"
title="$(playerctl metadata title 2>/dev/null || echo "")"
[[ -n "$title$artist" ]] || { printf '{"text":""}\n'; exit 0; }

txt="$glyph  ${artist:+$artist — }$title"
esc="${txt//\\/\\\\}"; esc="${esc//\"/\\\"}"
printf '{"text":"%s","tooltip":"%s"}\n' "$esc" "$esc"
