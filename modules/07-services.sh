#!/usr/bin/env bash
# 07-services.sh — enable system + user services. Idempotent.
set -Eeuo pipefail

log "Setting timezone"
sudo timedatectl set-timezone America/Los_Angeles
sudo timedatectl set-ntp true

log "Enabling system services"
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now seatd.service
sudo usermod -aG seat,video,input,audio,wheel "$USER" || true

log "Enabling ly login manager"
sudo systemctl enable ly@tty1.service

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
