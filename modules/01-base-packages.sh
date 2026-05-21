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
    alacritty
    ttf-jetbrains-mono-nerd ttf-firacode-nerd noto-fonts noto-fonts-emoji
    noto-fonts-cjk papirus-icon-theme adw-gtk-theme
    python python-pip python-gobject
    gtk3 gtk4 libadwaita
    cava
    mako
    fuzzel
    swaybg
    # Quickshell — QtQuick-based shell; drives the Caelestia-style top bar.
    quickshell
    # Side-bar dock apps that live in the official repos. spotify is AUR (see
    # 03-aur-packages.sh); WhatsApp runs as a Chromium web app (see
    # scripts/whatsapp-web.sh); steam needs the multilib repo enabled, so it is
    # intentionally left out of the installer.
    chromium discord
    seatd
    # Login manager.
    ly
    # GPU stack — required for Niri to find a working EGL renderer.
    # In a VMware/QEMU VM you ALSO need to enable 3D acceleration in the
    # hypervisor settings; the packages alone aren't enough.
    # mesa-demos provides BOTH glxinfo and eglinfo on Arch (the package
    # names mesa-utils / egl-utils are Debian, not Arch).
    mesa mesa-demos vulkan-icd-loader vulkan-swrast
    xorg-xwayland
    # ImageMagick — pre-blurs the lock-screen background at install time so
    # swaylock doesn't need live GL effects to look riced.
    imagemagick
)

# Detect VM hypervisor and pull in guest tools for clipboard/resolution/3D.
case "$(systemd-detect-virt 2>/dev/null)" in
    vmware) PKGS_CORE+=( open-vm-tools gtkmm3 ) ;;
    kvm|qemu) PKGS_CORE+=( qemu-guest-agent spice-vdagent ) ;;
    oracle) PKGS_CORE+=( virtualbox-guest-utils ) ;;
esac

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
