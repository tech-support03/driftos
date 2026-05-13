#!/usr/bin/env bash
# waveform — long-running cava stream → waybar JSON.
# Emits an EMPTY "text" field when no MPRIS player is playing, which makes the
# waveform widget collapse to zero width in the top bar.
set -Eeuo pipefail

mapfile -t BLOCKS < <(printf '%s\n' "▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")

CFG="$HOME/.config/cava/config"
[[ -f "$CFG" ]] || { echo '{"text":""}'; exit 0; }

# Track playback state with a background watcher updating a tmpfile, so the
# cava loop can read it cheaply.
STATE_FILE="$(mktemp -u "${XDG_RUNTIME_DIR:-/tmp}/waveform.state.XXXXXX")"
echo "Stopped" > "$STATE_FILE"
trap 'rm -f "$STATE_FILE"' EXIT

(
    playerctl --follow status 2>/dev/null | while IFS= read -r status; do
        printf '%s' "$status" > "$STATE_FILE"
    done
) &

cava -p "$CFG" 2>/dev/null | while IFS= read -r line; do
    state="$(cat "$STATE_FILE" 2>/dev/null || echo Stopped)"
    if [[ "$state" != "Playing" ]]; then
        printf '{"text":"","class":"idle"}\n'
        continue
    fi
    out=""
    for ((i=0;i<${#line};i++)); do
        ch="${line:i:1}"
        if [[ "$ch" =~ [0-7] ]]; then
            out+="${BLOCKS[$ch]}"
        fi
    done
    # waybar expects each update on its own line; escape for JSON safely.
    esc="${out//\\/\\\\}"; esc="${esc//\"/\\\"}"
    printf '{"text":"%s","class":"playing"}\n' "$esc"
done
