#!/usr/bin/env bash
# 07-services.sh — enable system + user services. Idempotent.
set -Eeuo pipefail

log "Enabling system services"
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now seatd.service
sudo usermod -aG seat,video,input,audio,wheel "$USER" || true

log "Configuring greetd (tuigreet → niri)"
sudo install -Dm644 /dev/stdin /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --user-menu --cmd niri-session"
user = "greeter"
EOF
sudo systemctl enable greetd.service

log "Enabling user services"
systemctl --user daemon-reload
for unit in pipewire pipewire-pulse wireplumber; do
    systemctl --user enable --now "${unit}.service" 2>/dev/null || true
done

ok "services enabled"
