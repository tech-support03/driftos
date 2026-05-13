#!/usr/bin/env bash
# 05-bootloader-grub.sh — GRUB. Works either:
#   - directly on a running installed system (sudo elevates), or
#   - inside arch-chroot during bare-metal install (root, sudo() is a shim).
set -Eeuo pipefail

# Provide a sudo() shim when running as root (e.g. inside arch-chroot or as the
# `root` user on first boot). This lets the same module run in either context.
if [[ $EUID -eq 0 ]]; then
    sudo() { "$@"; }
fi

# Minimal log helpers in case this module is invoked stand-alone.
command -v log  >/dev/null 2>&1 || log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
command -v ok   >/dev/null 2>&1 || ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
command -v warn >/dev/null 2>&1 || warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }

log "Installing grub + efibootmgr + os-prober"
sudo pacman -S --needed --noconfirm grub efibootmgr os-prober dosfstools mtools

EFI_DIR="${EFI_DIR:-/boot/efi}"
if ! mountpoint -q "$EFI_DIR"; then
    # Try common alternatives.
    for cand in /boot /efi /boot/EFI; do
        if mountpoint -q "$cand" && [[ -d "$cand/EFI" || "$cand" == "/boot" ]]; then
            EFI_DIR="$cand"; break
        fi
    done
fi

log "Using EFI directory: $EFI_DIR"

if [[ -d /sys/firmware/efi ]]; then
    # Inside chroot the path '/boot' is the ESP; default is right.
    # USB targets get --removable so the binary lands at \EFI\BOOT\BOOTX64.EFI
    # (firmware fallback path) — meaning the USB will boot on ANY UEFI machine
    # without requiring an NVRAM entry on the specific laptop. SSDs get a
    # named NVRAM entry so the firmware boot menu has a friendly label.
    GRUB_EXTRA=()
    if [[ "${TARGET_TYPE:-ssd}" == "usb" ]]; then
        GRUB_EXTRA+=( --removable )
        log "USB target: installing GRUB with --removable (portable to any UEFI)"
    fi
    sudo grub-install \
        --target=x86_64-efi \
        --efi-directory="$EFI_DIR" \
        --bootloader-id=GRUB \
        --recheck "${GRUB_EXTRA[@]}"
else
    # BIOS: $DISK is required. Bootstrap exports it; standalone callers must set it.
    DISK="${DISK:-}"
    [[ -n "$DISK" && -b "$DISK" ]] || { warn "DISK not set or not a block device — set DISK=/dev/sdX"; exit 1; }
    sudo grub-install --target=i386-pc --recheck "$DISK"
fi

# Light defaults: quiet boot, but show menu briefly so VM users can pick.
sudo sed -i \
    -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' \
    -e 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' \
    /etc/default/grub

sudo grub-mkconfig -o /boot/grub/grub.cfg
ok "GRUB installed and configured"
