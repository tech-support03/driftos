#!/usr/bin/env bash
# 03-pacstrap.sh — install minimal base system into /mnt.
# Keeps the pacstrap small — heavyweight packages (niri, waybar, etc.) are
# layered in later by install.sh once the user logs in.
set -Eeuo pipefail

BASE_PKGS=(
    base base-devel
    linux linux-firmware
    mkinitcpio
    sudo
    git vim
    networkmanager
    iwd wpa_supplicant
    e2fsprogs dosfstools
    pciutils usbutils
    man-db man-pages
    bash-completion
)

# Bootloader packages depend on the toggle AND the target type.
if [[ "$SECURE_BOOT" == "true" ]]; then
    if [[ "${TARGET_TYPE:-ssd}" == "usb" ]]; then
        # USB / removable Secure Boot = shim + GRUB + MOK. NEVER limine/sbctl:
        # sbctl enroll-keys rewrites the host firmware's db and trips BitLocker
        # (PCR 7) on any Windows machine the stick is plugged into (CLAUDE.md §11).
        # shimx64.efi/mmx64.efi themselves are staged from the host (AUR
        # shim-signed) by bootstrap.sh — they can't be pacstrapped.
        BASE_PKGS+=( grub efibootmgr dosfstools mtools sbsigntools mokutil )
    else
        BASE_PKGS+=( limine efibootmgr sbctl )
    fi
else
    if [[ "$IS_UEFI" == "true" ]]; then
        BASE_PKGS+=( grub efibootmgr os-prober )
    else
        BASE_PKGS+=( grub )
    fi
fi

# USB sticks are portable across machines — including a 2014 MacBook Air whose
# Broadcom BCM4360 needs the out-of-tree `wl` driver (broadcom-wl-dkms, AUR,
# staged by bootstrap.sh). DKMS + matching kernel headers must be in the base so
# that driver builds at install time and rebuilds on every kernel update.
if [[ "${TARGET_TYPE:-ssd}" == "usb" ]]; then
    BASE_PKGS+=( dkms linux-headers )
fi

# Microcode is harmless to include — installer picks the active CPU's loader.
BASE_PKGS+=( intel-ucode amd-ucode )

# Laptop profile pulls in power-management + ACPI + brightness early so the
# system has working battery/lid behavior from first boot. Things like
# tlp.service are enabled in the chroot config step.
if [[ "$PROFILE" == "laptop" ]]; then
    BASE_PKGS+=(
        tlp tlp-rdw
        acpi acpid
        upower
        brightnessctl
        bluez bluez-utils
        wpa_supplicant
        iio-sensor-proxy        # auto rotation if hw supports it
    )
fi

# Mirror selection — let the user fix this post-install if desired.
log "Updating mirrorlist via reflector if available"
if command -v reflector >/dev/null 2>&1; then
    reflector --latest 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || \
        warn "reflector failed; using existing mirrorlist"
fi

log "Pacstrapping base system (this is the long step)"
pacstrap -K /mnt "${BASE_PKGS[@]}"

log "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# Copy the mirrorlist into the new system.
install -Dm644 /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

ok "base system installed at /mnt"
