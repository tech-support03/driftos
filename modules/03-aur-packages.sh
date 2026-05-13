#!/usr/bin/env bash
# 03-aur-packages.sh — AUR packages via yay.
set -Eeuo pipefail

# yay invokes gpg as the calling user to import maintainer signing keys.
# If $HOME is not writable or .gnupg is missing, the import dies with
# "can't create directory '$HOME/.gnupg': Permission denied". Heal that
# before yay touches anything.
if [[ ! -O "$HOME" ]] || [[ ! -w "$HOME" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME"
fi
install -d -m 0700 "$HOME/.gnupg"
# A fresh gpg agent socket dir avoids stale socket errors after a chroot install.
install -d -m 0700 "${XDG_RUNTIME_DIR:-/tmp}/gnupg" 2>/dev/null || true

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
    xwayland-satellite
    # Graphical greeter stack: regreet (GTK4) inside a cage kiosk compositor,
    # both wired up through greetd. Replaces tuigreet so the login screen
    # actually matches the rest of the rice.
    greetd
    regreet
    cage
)

log "Installing AUR packages with yay (this may take a while)"
yay -S --needed --noconfirm --sudoloop "${AUR_PKGS[@]}"

ok "AUR packages installed"
