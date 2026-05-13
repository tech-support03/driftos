#!/usr/bin/env bash
# 05-bootloader-chroot.sh — runs INSIDE arch-chroot. Dispatches to GRUB or
# Limine+sbctl based on SECURE_BOOT. Wraps the bootloader modules with a
# chroot-friendly environment.
set -Eeuo pipefail

log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  XX\033[0m %s\n' "$*"; exit 1; }

# sudo shim — inside chroot we are root.
sudo() { "$@"; }
export -f sudo

# Hide `yay` from the Limine module's "extra packages" branch — yay won't run
# as root, and we already pacstrapped its needs (sbctl, limine, b3sum).
yay() {
    warn "yay called inside chroot — substituting pacman for: $*"
    # strip yay-only flags
    local args=()
    for a in "$@"; do
        case "$a" in
            --sudoloop|-S|--needed|--noconfirm) args+=("$a") ;;
            *) args+=("$a") ;;
        esac
    done
    pacman "${args[@]}"
}
export -f yay

export IS_CHROOT=1

if [[ "${SECURE_BOOT:-false}" == "true" ]]; then
    log "Installing Limine + sbctl (Secure Boot path)"
    bash "$MODULES_DIR/06-bootloader-limine.sh" || {
        warn "Limine module reported errors. Inspect output above. Install will continue."
    }

    # Drop a re-run helper for the "firmware wasn't in Setup Mode" case.
    log "Installing sb-finalize helper for post-boot key enrollment"
    install -Dm755 /dev/stdin /usr/local/bin/sb-finalize <<'EOF'
#!/usr/bin/env bash
# sb-finalize — retry sbctl key enrollment after putting firmware in Setup
# Mode, then re-sign all kernel/bootloader binaries and refresh limine.conf.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root: sudo sb-finalize" >&2; exit 1; }

if ! sbctl status 2>/dev/null | grep -qi 'Setup Mode:.*Enabled'; then
    echo "Firmware is NOT in Setup Mode."
    echo "Steps:"
    echo "  1. Reboot, enter UEFI firmware setup."
    echo "  2. Under Secure Boot, choose 'Clear/Erase Keys' or 'Reset to Setup Mode'."
    echo "  3. Save & exit, boot back into Arch, then re-run 'sudo sb-finalize'."
    exit 2
fi

echo ">>> creating keys (idempotent)"
sbctl create-keys || true
echo ">>> enrolling keys (with Microsoft certs)"
sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine

ESP="$(mountpoint -q /boot && echo /boot || (mountpoint -q /efi && echo /efi || echo /boot/efi))"
echo ">>> signing kernel + initramfs + EFI binaries on $ESP"
for f in "$ESP"/vmlinuz-* "$ESP"/initramfs-*.img \
         "$ESP"/EFI/BOOT/BOOTX64.EFI "$ESP"/EFI/limine/BOOTX64.EFI \
         /usr/share/limine/BOOTX64.EFI; do
    [[ -f "$f" ]] && sbctl sign -s "$f" || true
done

echo ">>> regenerating limine.conf with BLAKE2B hashes"
/usr/local/bin/limine-regen-conf "$ESP"

echo "Done. Reboot and re-enable Secure Boot in firmware."
EOF
else
    log "Installing GRUB"
    bash "$MODULES_DIR/05-bootloader-grub.sh"
fi

ok "bootloader stage complete"
