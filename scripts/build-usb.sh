#!/usr/bin/env bash
# build-usb.sh — one-shot driver to build the BitLocker-safe Secure Boot USB
# from a RUNNING Arch host (not the ISO). It does the three things bootstrap.sh
# can't do for itself on a normal system:
#
#   1. installs the host-side tools needed to partition/pacstrap/sign
#      (arch-install-scripts, gptfdisk, sbsigntools, mokutil, ...),
#   2. builds the AUR pieces that can't be pacstrapped or built as root in the
#      chroot — shim-signed (always) and broadcom-wl-dkms (only with
#      --with-macbook-wifi), and
#   3. invokes bootstrap.sh with the USB + Secure Boot env wired up
#      (TARGET_TYPE=usb, SECURE_BOOT=true → shim+MOK, never sbctl; CLAUDE.md §11).
#
# Run with sudo from a normal login (so $SUDO_USER can build AUR via yay):
#
#   sudo ./scripts/build-usb.sh --disk /dev/sda [--with-macbook-wifi]
#
# Passwords are prompted interactively by bootstrap's chroot stage unless you
# pre-export USER_PASSWORD / ROOT_PASSWORD — do NOT pass them on the cmdline.
set -Eeuo pipefail
shopt -s inherit_errexit

log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  XX\033[0m %s\n' "$*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- args ------------------------------------------------------------------
DISK=""
WITH_MACBOOK_WIFI="false"
PASSTHRU=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)               DISK="$2"; shift 2 ;;
        --disk=*)             DISK="${1#*=}"; shift ;;
        --with-macbook-wifi)  WITH_MACBOOK_WIFI="true"; shift ;;
        *)                    PASSTHRU+=("$1"); shift ;;   # forwarded to bootstrap.sh
    esac
done

[[ $EUID -eq 0 ]] || die "run as root: sudo ./scripts/build-usb.sh --disk /dev/sdX"
[[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] \
    || die "run via sudo from your normal login (need a non-root user to build AUR with yay)"
[[ -n "$DISK" ]] || die "specify the target USB: --disk /dev/sdX"
[[ -b "$DISK" ]] || die "$DISK is not a block device"

# Refuse anything that isn't actually removable — last line of defence before
# bootstrap's own ISO/Windows guards. The whole point is to not nuke an internal
# disk by fat-fingering the name.
base="$(basename "$DISK")"
if [[ "$(cat "/sys/block/$base/removable" 2>/dev/null)" != "1" ]]; then
    die "$DISK is not flagged removable. This driver only builds USB sticks. Aborting."
fi

# ---- 1. host prerequisites -------------------------------------------------
log "Installing host build prerequisites"
pacman -S --needed --noconfirm \
    arch-install-scripts gptfdisk dosfstools mtools \
    sbsigntools mokutil efibootmgr

# ---- 2. AUR pieces (built as the invoking user, not root) ------------------
aur_build() {  # pkgname  [--install]
    local pkg="$1" mode="${2:-}"
    if [[ "$mode" == "--install" ]]; then
        log "Building + installing $pkg on host (needed for staging files)"
        sudo -u "$SUDO_USER" yay -S --needed --noconfirm "$pkg"
    else
        log "Building $pkg package (not installing on host)"
        sudo -u "$SUDO_USER" bash -c '
            set -Eeuo pipefail
            d="$(mktemp -d)"; trap "rm -rf \"$d\"" EXIT
            git clone --depth=1 "https://aur.archlinux.org/'"$pkg"'.git" "$d/'"$pkg"'"
            cd "$d/'"$pkg"'"
            makepkg -f --noconfirm --nodeps   # dkms pkg: deps are install-time
            mkdir -p "'"$AUR_PKG_CACHE"'"
            cp -v ./*.pkg.tar.zst "'"$AUR_PKG_CACHE"'/"
        '
    fi
}

# shim-signed: install on the host so /usr/share/shim-signed exists; bootstrap
# stages that dir into the target.
command -v yay >/dev/null 2>&1 || die "yay not found — install an AUR helper first"
aur_build shim-signed --install

# broadcom-wl-dkms: only when the stick must boot the 2014 MacBook Air. Built
# into a cache dir and pacman -U'd inside the chroot by bootstrap.sh.
AUR_PKG_CACHE=""
if [[ "$WITH_MACBOOK_WIFI" == "true" ]]; then
    AUR_PKG_CACHE="$(mktemp -d /tmp/driftos-aur.XXXXXX)"
    chown "$SUDO_USER":"$SUDO_USER" "$AUR_PKG_CACHE"
    aur_build broadcom-wl-dkms
fi

# ---- 3. hand off to bootstrap ---------------------------------------------
log "Starting bootstrap (USB + shim+MOK Secure Boot)"
export DISK
export TARGET_TYPE="usb"
export SECURE_BOOT="true"
export PROFILE="${PROFILE:-laptop}"
export SHIM_SIGNED_DIR="/usr/share/shim-signed"
[[ -n "$AUR_PKG_CACHE" ]] && export AUR_PKG_CACHE

exec bash "$ROOT_DIR/bootstrap.sh" --disk "$DISK" "${PASSTHRU[@]}"
