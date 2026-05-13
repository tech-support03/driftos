#!/usr/bin/env bash
# 06-bootloader-limine.sh — bare-metal Secure Boot path: Limine + sbctl.
# Hashes kernel assets with BLAKE2B and signs everything on every pacman/mkinitcpio update.
# Runs in two contexts:
#   - directly on an installed system (sudo elevates)
#   - inside arch-chroot during bare-metal install (IS_CHROOT=1, root)
set -Eeuo pipefail

if [[ $EUID -eq 0 ]]; then
    sudo() { "$@"; }
fi
command -v log  >/dev/null 2>&1 || log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
command -v ok   >/dev/null 2>&1 || ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
command -v warn >/dev/null 2>&1 || warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }

if [[ ! -d /sys/firmware/efi ]]; then
    warn "Secure Boot requires UEFI; firmware is not EFI. Aborting."
    exit 1
fi

log "Installing Limine + sbctl + helpers"
# sbctl is in extra; b3sum is its own package. limine + efibootmgr in extra.
sudo pacman -S --needed --noconfirm limine efibootmgr sbctl b3sum

ESP="${ESP:-/boot}"
if ! mountpoint -q "$ESP"; then
    for cand in /boot/efi /efi; do
        mountpoint -q "$cand" && { ESP="$cand"; break; }
    done
fi
log "ESP: $ESP"

sudo mkdir -p "$ESP/EFI/BOOT" "$ESP/EFI/limine"
sudo cp -v /usr/share/limine/BOOTX64.EFI "$ESP/EFI/BOOT/BOOTX64.EFI"
sudo cp -v /usr/share/limine/limine.sys  "$ESP/EFI/limine/" 2>/dev/null || true

# Register with NVRAM only if missing. Handle NVMe (nvme0n1p1) and SATA (sda1).
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    warn "efivars not mounted — skipping efibootmgr. Most fallback firmwares will still boot \EFI\BOOT\BOOTX64.EFI."
elif ! efibootmgr 2>/dev/null | grep -qi limine; then
    ESP_SRC="$(findmnt -no SOURCE "$ESP")"
    if [[ "$ESP_SRC" =~ ^(.*[a-z])([0-9]+)$ ]]; then
        ESP_DISK="${BASH_REMATCH[1]}"; ESP_PART="${BASH_REMATCH[2]}"
        # NVMe partitions end with pN — drop the trailing 'p'.
        [[ "$ESP_DISK" =~ p$ ]] && ESP_DISK="${ESP_DISK%p}"
    fi
    if [[ -n "${ESP_DISK:-}" && -n "${ESP_PART:-}" ]]; then
        sudo efibootmgr --create --disk "$ESP_DISK" --part "$ESP_PART" \
            --label "Limine" --loader '\EFI\BOOT\BOOTX64.EFI' || \
            warn "efibootmgr failed; fallback boot path will still work"
    else
        warn "could not parse ESP source '$ESP_SRC' — skipping NVRAM entry"
    fi
fi

# ---- sbctl setup ----------------------------------------------------------
log "Creating Secure Boot keys (idempotent)"
sudo sbctl create-keys || warn "sbctl create-keys reported an error; continuing"

# Enrollment requires firmware in Setup Mode. Detect and gracefully skip when
# we're not — the sb-finalize helper installed by iso-stage/05 will retry.
if sudo sbctl status 2>/dev/null | grep -qi 'Setup Mode:.*Enabled'; then
    log "Firmware in Setup Mode — enrolling keys with Microsoft certs"
    sudo sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine || \
        warn "key enrollment failed; run 'sudo sb-finalize' after boot"
else
    warn "Firmware NOT in Setup Mode — keys are created and binaries will be signed,"
    warn "but enrollment is deferred. After first boot, place firmware in Setup Mode"
    warn "and run: sudo sb-finalize"
fi

# Sign critical EFI binaries.
for f in \
    "$ESP/EFI/BOOT/BOOTX64.EFI" \
    "$ESP/EFI/limine/BOOTX64.EFI" \
    /usr/share/limine/BOOTX64.EFI; do
    [[ -f "$f" ]] && sudo sbctl sign -s "$f" || true
done
for k in "$ESP"/vmlinuz-* "$ESP"/initramfs-*.img; do
    [[ -f "$k" ]] && sudo sbctl sign -s "$k" || true
done

# ---- limine.conf with BLAKE2B hashes --------------------------------------
log "Generating /boot/limine.conf with BLAKE2B hashes"
TMP="$(mktemp)"
{
    echo "timeout: 2"
    echo "default_entry: 1"
    echo "interface_branding: Arch Linux"
    echo ""
    for vmlinuz in "$ESP"/vmlinuz-*; do
        [[ -f "$vmlinuz" ]] || continue
        kernel="$(basename "$vmlinuz")"
        flavour="${kernel#vmlinuz-}"
        initramfs="initramfs-${flavour}.img"
        [[ -f "$ESP/$initramfs" ]] || initramfs="initramfs-${flavour}-fallback.img"
        kern_hash="$(sudo b3sum "$vmlinuz" | awk '{print $1}')"
        init_hash="$(sudo b3sum "$ESP/$initramfs" | awk '{print $1}')"
        ROOT_UUID="$(findmnt -no UUID /)"
        cat <<ENTRY
:Arch Linux ($flavour)
    protocol: linux
    kernel_path: boot():/$kernel
    kernel_cmdline: root=UUID=$ROOT_UUID rw quiet loglevel=3
    module_path: boot():/$initramfs
    kernel_b3sum: $kern_hash
    module_b3sum: $init_hash

ENTRY
    done
} > "$TMP"
sudo install -Dm644 "$TMP" "$ESP/limine.conf"
rm -f "$TMP"

# ---- pacman + mkinitcpio hooks --------------------------------------------
log "Installing pacman hooks for re-sign + re-enroll on kernel/bootloader updates"
sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/95-limine-resign.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened
Target = limine
Target = systemd

[Action]
Description = Re-signing kernel assets and rewriting limine.conf with BLAKE2B hashes
When = PostTransaction
Exec = /usr/local/bin/limine-resign
EOF

sudo install -Dm755 /dev/stdin /usr/local/bin/limine-resign <<'EOF'
#!/usr/bin/env bash
set -e
ESP="$(mountpoint -q /boot && echo /boot || (mountpoint -q /efi && echo /efi || echo /boot/efi))"
for f in "$ESP"/vmlinuz-* "$ESP"/initramfs-*.img "$ESP"/EFI/BOOT/BOOTX64.EFI "$ESP"/EFI/limine/BOOTX64.EFI; do
    [[ -f "$f" ]] && sbctl sign -s "$f" || true
done
"$(dirname "$0")/limine-regen-conf" "$ESP"
EOF

sudo install -Dm755 /dev/stdin /usr/local/bin/limine-regen-conf <<'EOF'
#!/usr/bin/env bash
set -e
ESP="${1:-/boot}"
ROOT_UUID="$(findmnt -no UUID /)"
TMP="$(mktemp)"
{
    echo "timeout: 2"
    echo "default_entry: 1"
    echo "interface_branding: Arch Linux"
    echo ""
    for vmlinuz in "$ESP"/vmlinuz-*; do
        [[ -f "$vmlinuz" ]] || continue
        kernel="$(basename "$vmlinuz")"
        flavour="${kernel#vmlinuz-}"
        initramfs="initramfs-${flavour}.img"
        [[ -f "$ESP/$initramfs" ]] || initramfs="initramfs-${flavour}-fallback.img"
        kern_hash="$(b3sum "$vmlinuz" | awk '{print $1}')"
        init_hash="$(b3sum "$ESP/$initramfs" | awk '{print $1}')"
        cat <<E
:Arch Linux ($flavour)
    protocol: linux
    kernel_path: boot():/$kernel
    kernel_cmdline: root=UUID=$ROOT_UUID rw quiet loglevel=3
    module_path: boot():/$initramfs
    kernel_b3sum: $kern_hash
    module_b3sum: $init_hash

E
    done
} > "$TMP"
install -Dm644 "$TMP" "$ESP/limine.conf"
rm -f "$TMP"
EOF

ok "Limine + sbctl Secure Boot stack configured"
