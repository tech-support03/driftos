#!/usr/bin/env bash
# 07-services.sh — enable system + user services. Idempotent.
set -Eeuo pipefail

log "Enabling system services"
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now seatd.service
sudo usermod -aG seat,video,input,audio,wheel "$USER" || true

log "Configuring greetd (cage + regreet → niri)"
# regreet is a GTK4 greeter; it needs a Wayland compositor to draw into. We
# use `cage` as a single-surface kiosk compositor. After login regreet execs
# niri-session as the chosen user.
sudo install -Dm644 /dev/stdin /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "cage -s -m last -- regreet"
user = "greeter"
EOF

# regreet stores last user / last session under /var/lib/regreet — make sure
# the greeter user can write there.
sudo install -d -o greeter -g greeter -m 0755 /var/lib/regreet 2>/dev/null || \
    sudo install -d -m 0755 /var/lib/regreet

sudo systemctl enable greetd.service

# Hypervisor guest agents — harmless on bare metal because the service files
# only exist if the matching package was installed.
for unit in vmtoolsd.service vmware-vmblock-fuse.service \
            qemu-guest-agent.service spice-vdagent.service \
            vboxservice.service; do
    sudo systemctl enable "$unit" 2>/dev/null || true
done

log "Enabling user services"
systemctl --user daemon-reload
for unit in pipewire pipewire-pulse wireplumber; do
    systemctl --user enable --now "${unit}.service" 2>/dev/null || true
done

ok "services enabled"
