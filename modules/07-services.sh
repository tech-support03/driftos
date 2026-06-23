#!/usr/bin/env bash
# 07-services.sh — enable system + user services. Idempotent.
set -Eeuo pipefail

log "Setting timezone"
sudo timedatectl set-timezone America/Los_Angeles
sudo timedatectl set-ntp true

# ---- networking: iwd (wifi) + systemd-networkd (wired) ---------------------
# No NetworkManager — it fought iwd on this hardware. iwd runs standalone and
# does its own DHCP/association for wifi; systemd-networkd manages the wired
# NIC only (a lower route metric makes a plugged cable auto-win over wifi).
# DNS is deliberately left to a static /etc/resolv.conf (the live box layers
# Cloudflare WARP on top), so systemd-resolved is NOT enabled — turning it on
# would seize DNS and re-break the school content filter path.
log "Writing iwd config"
sudo install -Dm644 /dev/stdin /etc/iwd/main.conf <<'EOF'
[General]
# iwd configures the wifi link itself (address, routes, its own DHCP).
EnableNetworkConfiguration=true

[Network]
# Don't let iwd touch DNS — a static /etc/resolv.conf (+ WARP) owns it.
NameResolvingService=none
EOF

log "Writing systemd-networkd wired profile"
sudo install -Dm644 /dev/stdin /etc/systemd/network/20-wired.network <<'EOF'
# Wired NIC, managed by systemd-networkd (iwd still owns wifi). DHCP supplies
# address + routes only; DNS is left to the static /etc/resolv.conf (+ WARP)
# via UseDNS=no, so networkd never disturbs the (school-filtered) DNS path. A
# low RouteMetric makes a plugged-in cable win over wifi automatically;
# RequiredForOnline=no keeps an unplugged cable from stalling boot.
[Match]
Name=en*

[Network]
DHCP=yes

[Link]
RequiredForOnline=no

[DHCPv4]
RouteMetric=100
UseDNS=no

[IPv6AcceptRA]
RouteMetric=100
UseDNS=no
EOF

log "Writing polkit rule for the network flyout's wired override toggle"
sudo install -Dm644 /dev/stdin /etc/polkit-1/rules.d/50-networkd-links.rules <<'EOF'
// Let the active local session bring networkd-managed links up/down without a
// password — used by the Quickshell network flyout's manual Ethernet override.
// Scoped to link management only; DNS / route-policy actions still need admin.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.network1.manage-links" &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF

# Seed a static resolver if one isn't already in place (the live box points
# this at 1.1.1.1/8.8.8.8 and runs WARP over the top). Never clobber an
# existing resolv.conf — it may be a deliberate WARP/resolved setup.
if [[ ! -s /etc/resolv.conf ]]; then
    log "Seeding static /etc/resolv.conf"
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf >/dev/null
fi

log "Enabling system services"
sudo systemctl enable --now iwd.service
sudo systemctl enable --now systemd-networkd.service
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now seatd.service
sudo usermod -aG seat,video,input,audio,wheel "$USER" || true

log "Enabling ly login manager"
sudo systemctl enable ly@tty1.service

# Theme the greeter from the rice palette (falls back to indigo if rice-theme
# hasn't run yet). Idempotent; only edits colour/appearance keys in place.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sudo "$REPO_ROOT/scripts/theme-ly.sh" || log "ly theming skipped (run later: sudo scripts/theme-ly.sh)"

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
