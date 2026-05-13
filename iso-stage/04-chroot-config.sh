#!/usr/bin/env bash
# 04-chroot-config.sh — runs INSIDE arch-chroot. Configures locale, time,
# hostname, user account, network, and mkinitcpio. Bootloader install is a
# separate stage (05-bootloader-chroot.sh) so its failures are easier to
# isolate.
set -Eeuo pipefail

# Inside chroot we are root; provide a sudo() shim so shared modules work.
sudo() { "$@"; }
export -f sudo

# log/ok/warn aren't inherited through arch-chroot — redefine minimal versions.
log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  XX\033[0m %s\n' "$*"; exit 1; }

: "${HOSTNAME:?missing}"
: "${USERNAME:?missing}"
: "${TIMEZONE:?missing}"
: "${LOCALE:?missing}"
: "${KEYMAP:?missing}"
: "${USER_PASSWORD:?missing}"
: "${ROOT_PASSWORD:?missing}"

# ---- timezone --------------------------------------------------------------
log "Timezone → $TIMEZONE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# ---- locale ----------------------------------------------------------------
log "Locale → $LOCALE"
sed -i "s/^#\($LOCALE\)/\1/" /etc/locale.gen
locale-gen
printf 'LANG=%s\n' "$LOCALE" > /etc/locale.conf
printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf

# ---- hostname --------------------------------------------------------------
log "Hostname → $HOSTNAME"
printf '%s\n' "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# ---- root password ---------------------------------------------------------
log "Setting root password"
printf 'root:%s' "$ROOT_PASSWORD" | chpasswd

# ---- user account ----------------------------------------------------------
log "Creating user $USERNAME"
if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd -m -G wheel,audio,video,input,storage,optical -s /bin/bash "$USERNAME"
fi
printf '%s:%s' "$USERNAME" "$USER_PASSWORD" | chpasswd

# Wheel → sudo. Use a drop-in so we don't depend on sudoers.tmpl variations.
install -Dm440 /dev/stdin /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
# Sanity-check sudoers parses.
visudo -cf /etc/sudoers.d/10-wheel >/dev/null || die "sudoers drop-in failed validation"

# ---- network ---------------------------------------------------------------
log "Enabling NetworkManager"
systemctl enable NetworkManager.service

# ---- mkinitcpio ------------------------------------------------------------
# Default arch HOOKS = (base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)
# That's fine for both GRUB and Limine. No changes needed unless adding LUKS
# (intentionally out of scope here for first-version reliability).
log "Regenerating initramfs"
mkinitcpio -P

# ---- ownership of the staged repo ------------------------------------------
if [[ -d "/home/$USERNAME/arch-setup" ]]; then
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/arch-setup"
fi

# ---- first-login hint ------------------------------------------------------
install -Dm644 /dev/stdin /etc/motd <<EOF
─────────────────────────────────────────────────────────────────────
  Welcome to driftos. To finish setup, run:

      cd ~/arch-setup
      ./install.sh --profile $PROFILE

EOF

ok "chroot config complete"
