#!/usr/bin/env bash
# 02-disk.sh — partition + format + mount the target disk.
# Layout (UEFI):  GPT
#   p1  1 GiB  EF00  fat32  → /boot   (ESP; kernel + initramfs live here so
#                                       Limine can read them via boot():/)
#   p2  rest   8300  ext4   → /
# Layout (BIOS): GPT with a 1 MiB BIOS-boot partition and ext4 root.
set -Eeuo pipefail

[[ -n "${DISK:-}" ]] || die "DISK not set"
[[ -b "$DISK" ]]      || die "DISK $DISK not a block device"

# Safety: refuse if any partition on the target is currently mounted.
if mount | grep -qE "^${DISK}p?[0-9]+ "; then
    warn "Unmounting existing partitions on $DISK"
    for p in $(lsblk -nrpo NAME "$DISK" | tail -n +2); do
        umount -R "$p" 2>/dev/null || true
        swapoff "$p" 2>/dev/null || true
    done
fi

log "Zapping existing partition table on $DISK"
sgdisk --zap-all "$DISK"
wipefs -af "$DISK"
partprobe "$DISK" || true
sleep 1

if [[ "$IS_UEFI" == "true" ]]; then
    log "Creating GPT (UEFI): 1G ESP + rest root"
    sgdisk -n 1:0:+1G   -t 1:EF00 -c 1:"EFI System"        "$DISK"
    sgdisk -n 2:0:0     -t 2:8300 -c 2:"Linux Root"        "$DISK"
else
    log "Creating GPT (BIOS): 1M BIOS-boot + rest root"
    sgdisk -n 1:0:+1M   -t 1:EF02 -c 1:"BIOS Boot"         "$DISK"
    sgdisk -n 2:0:0     -t 2:8300 -c 2:"Linux Root"        "$DISK"
fi
partprobe "$DISK"
sleep 1

# Resolve partition names (NVMe uses ${DISK}p1, SATA uses ${DISK}1).
if [[ "$DISK" =~ (nvme|mmcblk)[0-9]+$ ]]; then
    P1="${DISK}p1"; P2="${DISK}p2"
else
    P1="${DISK}1";  P2="${DISK}2"
fi
[[ -b "$P1" && -b "$P2" ]] || die "expected partitions $P1 $P2 not present after partprobe"

log "Formatting"
if [[ "$IS_UEFI" == "true" ]]; then
    mkfs.fat -F32 -n EFI "$P1"
fi
mkfs.ext4 -F -L ROOT "$P2"

log "Mounting"
mount "$P2" /mnt
if [[ "$IS_UEFI" == "true" ]]; then
    mkdir -p /mnt/boot
    mount "$P1" /mnt/boot
fi

# Persist for later stages (env vars survive within bootstrap.sh's process).
export PART_ESP="$P1" PART_ROOT="$P2"
ok "Disk ready (ESP=${PART_ESP:-n/a}, ROOT=$PART_ROOT)"
