#!/usr/bin/env bash
# fastfetch-popup — open a borderless translucent foot terminal running fastfetch.
set -Eeuo pipefail

exec foot \
    --app-id="fastfetch-popup" \
    --title="System Summary" \
    -W 78x22 \
    -e sh -c 'fastfetch; printf "\nPress any key to close..."; read -n1'
