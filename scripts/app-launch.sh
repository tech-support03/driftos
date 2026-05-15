#!/usr/bin/env bash
# app-launch <binary> [args...] — launch an app if it's installed, otherwise
# show a desktop notification instead of failing silently. Used by the waybar
# side-bar dock so a missing app gives clear feedback.
set -Eeuo pipefail

bin="${1:-}"
[[ -n "$bin" ]] || exit 0
shift || true

if command -v "$bin" >/dev/null 2>&1; then
    exec "$bin" "$@"
fi

notify-send -a "dock" "Not installed" "$bin is not installed" 2>/dev/null || true
