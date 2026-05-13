#!/usr/bin/env bash
# 01-base-packages.sh — official repo packages (idempotent).
set -Eeuo pipefail

PKGS_CORE=(
    base-devel git curl wget unzip rsync man-db man-pages
    networkmanager openssh
    pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol
    bluez bluez-utils blueman
    polkit polkit-gnome xdg-user-dirs xdg-utils
    qt5-wayland qt6-wayland
    grim slurp wl-clipboard cliphist
    brightnessctl playerctl
    fastfetch htop btop fzf ripgrep fd bat eza zoxide
    foot
    ttf-jetbrains-mono-nerd ttf-firacode-nerd noto-fonts noto-fonts-emoji
    noto-fonts-cjk papirus-icon-theme
    python python-pip python-gobject
    gtk3 gtk4 libadwaita
    cava
    mako
    fuzzel
    swaybg
    seatd
)

# Conditional: GPU/CPU microcode only matters bare-metal.
PKGS_BAREMETAL=(
    intel-ucode amd-ucode
)

log "Refreshing pacman databases"
sudo pacman -Syu --noconfirm --needed

log "Installing core packages"
sudo pacman -S --needed --noconfirm "${PKGS_CORE[@]}"

if [[ "$PROFILE" == "personal" ]]; then
    log "Installing microcode (bare-metal profile)"
    sudo pacman -S --needed --noconfirm "${PKGS_BAREMETAL[@]}" || true
fi

ok "base packages installed"
