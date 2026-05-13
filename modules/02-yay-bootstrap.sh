#!/usr/bin/env bash
# 02-yay-bootstrap.sh — bootstrap `yay` AUR helper.
set -Eeuo pipefail

if command -v yay >/dev/null 2>&1; then
    ok "yay already installed ($(yay --version | head -n1))"
    exit 0
fi

log "Bootstrapping yay from AUR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
(
    cd "$tmp/yay-bin"
    makepkg -si --noconfirm --needed
)

ok "yay installed"
