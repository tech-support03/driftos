#!/usr/bin/env bash
# 04-niri-stack.sh — make sure niri session, xdg-desktop-portal stack are present.
set -Eeuo pipefail

PORTAL_PKGS=(
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    xdg-desktop-portal-gnome
)

log "Installing xdg-desktop-portal stack"
sudo pacman -S --needed --noconfirm "${PORTAL_PKGS[@]}"

# xdg-desktop-portal-wlr is recommended for screencasting in wlroots-based compositors.
yay -S --needed --noconfirm --sudoloop xdg-desktop-portal-wlr || true

log "Registering niri.desktop session for greetd/SDDM/GDM"
sudo install -Dm644 /dev/stdin /usr/share/wayland-sessions/niri.desktop <<'EOF'
[Desktop Entry]
Name=Niri
Comment=Scrollable-tiling Wayland compositor
Exec=niri-session
Type=Application
EOF

ok "niri stack ready"
