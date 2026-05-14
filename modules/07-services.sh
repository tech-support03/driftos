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

# ---- greeter user prerequisites -------------------------------------------
# The `greeter` system user is created by the greetd package. It is NOT
# automatically added to the groups cage/regreet need:
#   seat   — talk to /run/seatd.sock (libseat backend; logind fallback works
#            but is noisier and on some configs fails outright)
#   video  — open /dev/dri/cardN for KMS
#   render — open /dev/dri/renderDN  (newer split-render kernels)
#   input  — read /dev/input/* for keyboard/mouse
# Without these the greeter exits before drawing anything and greetd loops
# until start-limit-hit. Idempotent.
sudo usermod -aG seat,video,input,render greeter 2>/dev/null || \
    warn "could not add greeter to groups (user may not exist yet)"

# regreet writes three things, all of which we pre-create with greeter
# ownership so it doesn't fail on its first run:
#   /var/lib/regreet     — runtime state (wallpaper.jpg seeded by 09-wallpapers)
#   /var/cache/regreet/  — cache.toml (remembers last user / last session)
#   /var/log/regreet.log — log output (the path is set in regreet.toml)
# These default to root-owned and mode 755, which the greeter user cannot
# write to. Without pre-creation regreet hits "permission denied" on its
# logger and exits, which surfaces in journalctl ONLY as the cryptic greetd
# message "greeter exited without creating a session".
for d in /var/lib/regreet /var/cache/regreet; do
    sudo install -d -o greeter -g greeter -m 0755 "$d"
done
sudo touch /var/log/regreet.log
sudo chown greeter:greeter /var/log/regreet.log
sudo chmod 0640 /var/log/regreet.log

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
