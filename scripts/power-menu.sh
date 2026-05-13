#!/usr/bin/env bash
# power-menu — fuzzel-based borderless overlay for sign-out / reboot / power-off.
set -Eeuo pipefail

choice="$(printf '%s\n' \
    "  Lock" \
    "  Sign out" \
    "  Reboot" \
    "  Power off" \
    "  Suspend" \
  | fuzzel --dmenu --prompt 'Power  ' --lines 5 --width 26)"

case "$choice" in
    *Lock*)       exec swaylock ;;
    *Sign\ out*)  exec niri msg action quit --skip-confirmation ;;
    *Reboot*)     exec systemctl reboot ;;
    *Power\ off*) exec systemctl poweroff ;;
    *Suspend*)    exec systemctl suspend ;;
esac
