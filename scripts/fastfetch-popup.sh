#!/usr/bin/env bash
# fastfetch-popup — small floating alacritty window running fastfetch.
set -Eeuo pipefail

exec alacritty \
    --class fastfetch-popup \
    --title "System Summary" \
    -o "window.dimensions.columns=64" \
    -o "window.dimensions.lines=20" \
    -o "window.padding.x=14" \
    -o "window.padding.y=12" \
    -e sh -c 'fastfetch; printf "\nPress any key to close..."; read -n1'
