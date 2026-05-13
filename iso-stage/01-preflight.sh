#!/usr/bin/env bash
# 01-preflight.sh — sourced by bootstrap.sh, validates ISO environment.
# IMPORTANT: this file is sourced (not exec'd) so `die` exits the parent.
set -Eeuo pipefail

log "Preflight checks"

# 1) Are we in the Arch ISO?
in_iso="false"
if grep -q archiso /proc/cmdline 2>/dev/null; then in_iso="true"; fi
[[ -d /run/archiso ]] && in_iso="true"
if [[ "$in_iso" != "true" ]]; then
    warn "Not detected as Arch ISO live env; continuing anyway. Pass --yes to skip this hint."
fi

# 2) UEFI firmware? (Hard requirement for Secure Boot; strongly preferred otherwise.)
is_uefi="false"
[[ -d /sys/firmware/efi ]] && is_uefi="true"

if [[ "$SECURE_BOOT" == "true" && "$is_uefi" != "true" ]]; then
    die "Secure Boot requested but firmware booted in legacy/BIOS mode. Reboot the ISO in UEFI mode."
fi
if [[ "$is_uefi" != "true" ]]; then
    warn "BIOS/legacy boot detected. GRUB will install in BIOS mode (--target=i386-pc)."
fi

# 3) Network connectivity (needed for pacstrap)
log "Checking network…"
if ! curl -fsS --max-time 5 https://archlinux.org/ -o /dev/null; then
    warn "No HTTPS to archlinux.org. Trying ping…"
    if ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        die "No network. Configure with 'iwctl' (wifi) or check the ethernet cable, then re-run."
    fi
fi
ok "network reachable"

# 4) Pacman keyring on the ISO is current (otherwise pacstrap fails with signature errors)
log "Refreshing pacman keys on the ISO"
pacman -Sy --noconfirm archlinux-keyring >/dev/null 2>&1 || warn "could not refresh archlinux-keyring (will retry during pacstrap)"

# 5) Required tools in the ISO
for t in parted mkfs.fat mkfs.ext4 sgdisk arch-chroot pacstrap genfstab lsblk findmnt curl; do
    command -v "$t" >/dev/null || die "missing required tool in ISO: $t"
done

# 6) Time sync (important for cert validation during pacstrap)
log "Enabling NTP"
timedatectl set-ntp true || true

# 7) Secure-Boot specific: warn if firmware is NOT in Setup Mode.
if [[ "$SECURE_BOOT" == "true" ]]; then
    if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
        warn "Secure Boot is currently ACTIVE in firmware. Key enrollment requires Setup Mode."
        warn "If sbctl can't enroll, you'll need to clear the PK in firmware, then run 'sudo sb-finalize' after first boot."
    fi
fi

ok "preflight passed (UEFI=$is_uefi, SECURE_BOOT=$SECURE_BOOT)"
export IS_UEFI="$is_uefi"
