#!/usr/bin/env bash
# 03-aur-packages.sh — AUR packages via yay.
set -Eeuo pipefail

AUR_PKGS=(
    niri
    waybar
    swaylock-effects
    swayidle
    wlogout
    nwg-displays
    wdisplays
    kanshi
    swww
    grimblast-git
    hyprpicker
    wlr-randr
    greetd
    greetd-tuigreet
)

log "Installing AUR packages with yay (this may take a while)"
yay -S --needed --noconfirm --sudoloop "${AUR_PKGS[@]}"

ok "AUR packages installed"
