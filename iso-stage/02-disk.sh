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

# Hard safety: refuse if $DISK is the disk the live ISO booted from. This is
# only physically possible in odd setups (writing to the same USB the ISO is
# running off), but the failure mode is catastrophic, so we check.
iso_src="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
if [[ -n "$iso_src" ]]; then
    iso_disk="/dev/$(lsblk -no PKNAME "$iso_src" 2>/dev/null | head -n1)"
    if [[ "$iso_disk" == "$DISK" ]]; then
        die "Refusing to install onto $DISK — the live ISO is running from it."
    fi
fi

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

# USB sticks live longer with fewer writes and don't reliably honor TRIM, so
# pick smaller ESP and write-cheap mount options. SSDs get a 1G ESP and weekly
# fstrim (enabled in chroot config). TARGET_TYPE is set by bootstrap.sh.
#
# NOTE on TRIM: ext4 does NOT accept `discard=async` (that's btrfs syntax — the
# kernel now strict-parses and fails the mount). The valid ext4 forms are bare
# `discard` (synchronous TRIM at delete time, measurably slow) or none. We
# choose none + fstrim.timer for batched weekly TRIM, which is the modern
# Arch-wiki recommendation for ext4-on-SSD.
case "${TARGET_TYPE:-ssd}" in
    usb)
        ESP_SIZE="+512M"
        # noatime already disables diratime; commit=120 batches metadata flushes
        # to spare USB flash write cycles.
        ROOT_OPTS="defaults,noatime,commit=120"
        ESP_OPTS="defaults,noatime,fmask=0077,dmask=0077"
        ;;
    *)
        ESP_SIZE="+1G"
        ROOT_OPTS="defaults,noatime"
        ESP_OPTS="defaults,noatime,fmask=0077,dmask=0077"
        ;;
esac

if [[ "$IS_UEFI" == "true" ]]; then
    log "Creating GPT (UEFI): ESP=$ESP_SIZE + rest root  (target=$TARGET_TYPE)"
    sgdisk -n 1:0:$ESP_SIZE -t 1:EF00 -c 1:"EFI System"        "$DISK"
    sgdisk -n 2:0:0         -t 2:8300 -c 2:"Linux Root"        "$DISK"
else
    log "Creating GPT (BIOS): 1M BIOS-boot + rest root"
    sgdisk -n 1:0:+1M       -t 1:EF02 -c 1:"BIOS Boot"         "$DISK"
    sgdisk -n 2:0:0         -t 2:8300 -c 2:"Linux Root"        "$DISK"
fi
partprobe "$DISK"
udevadm settle 2>/dev/null || sleep 1

# Resolve partition names. Kernel rule: if the device node ends in a digit
# (nvme0n1, mmcblk0, loop0, ...) partitions get a `p` separator; otherwise
# (sda, vda, ...) they don't. The previous (nvme|mmcblk|loop)[0-9]+$ regex
# failed on NVMe namespaces like nvme0n1 — it doesn't end in nvme<digit>, it
# ends in n<digit> — so we landed on /dev/nvme0n11 / /dev/nvme0n12.
if [[ "$DISK" =~ [0-9]$ ]]; then
    P1="${DISK}p1"; P2="${DISK}p2"
else
    P1="${DISK}1";  P2="${DISK}2"
fi

# partprobe is async on some kernels; wait briefly for udev to materialize the
# nodes before failing.
for _ in 1 2 3 4 5; do
    [[ -b "$P1" && -b "$P2" ]] && break
    udevadm settle 2>/dev/null || true
    sleep 1
done
[[ -b "$P1" && -b "$P2" ]] || die "expected partitions $P1 $P2 not present after partprobe"

log "Formatting"
if [[ "$IS_UEFI" == "true" ]]; then
    mkfs.fat -F32 -n EFI "$P1"
fi
# Stride/stripe-width left to mke2fs defaults — modern mke2fs picks reasonable
# values for SSDs and USB sticks alike.
mkfs.ext4 -F -L ROOT "$P2"

log "Mounting with target-appropriate options"
mount -o "$ROOT_OPTS" "$P2" /mnt
if [[ "$IS_UEFI" == "true" ]]; then
    mkdir -p /mnt/boot
    mount -o "$ESP_OPTS" "$P1" /mnt/boot
fi

# Persist for later stages.
export PART_ESP="$P1" PART_ROOT="$P2" ROOT_OPTS ESP_OPTS
ok "Disk ready (ESP=${PART_ESP:-n/a}, ROOT=$PART_ROOT, opts=$ROOT_OPTS)"
