#!/usr/bin/env bash
# ~/arch-setup/bootstrap.sh
# Bare-metal Arch installer — meant to be run from inside the Arch ISO live
# environment as root. Partitions a target disk, pacstraps a minimal base,
# configures it inside arch-chroot, and installs the bootloader (GRUB or
# Limine+sbctl). After reboot, the user runs `~/arch-setup/install.sh` to
# layer on the Niri rice.
#
# Usage (all flags optional; missing values are prompted):
#   sudo ./bootstrap.sh \
#       --disk /dev/nvme0n1 \
#       --hostname driftos \
#       --user arjun \
#       --timezone America/New_York \
#       --profile personal \
#       --secure-boot \
#       --yes                  # skip the "destroy disk" confirmation
#
# Environment-variable equivalents:
#   DISK, HOSTNAME, USERNAME, TIMEZONE, PROFILE, SECURE_BOOT, ASSUME_YES,
#   USER_PASSWORD, ROOT_PASSWORD
#
set -Eeuo pipefail
shopt -s inherit_errexit

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$ROOT_DIR/iso-stage"
MODULES_DIR="$ROOT_DIR/modules"
DOTFILES_DIR="$ROOT_DIR/dotfiles"
SCRIPTS_DIR="$ROOT_DIR/scripts"

export ROOT_DIR STAGE_DIR MODULES_DIR DOTFILES_DIR SCRIPTS_DIR

# ---- defaults / args -------------------------------------------------------
# NB: do NOT name these `HOSTNAME` or `USER` — bash auto-populates those from
# the running shell's identity, so `${HOSTNAME:-driftos}` would read "archiso"
# from the live ISO and silently skip every default/prompt. Use TARGET_* names
# to keep the live-env environment out of our config.
DISK="${DISK:-}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-}"
TARGET_USERNAME="${TARGET_USERNAME:-}"
TIMEZONE="${TIMEZONE:-America/New_York}"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"
PROFILE="${PROFILE:-vm}"
TARGET_TYPE="${TARGET_TYPE:-auto}"        # ssd | usb | auto
SECURE_BOOT="${SECURE_BOOT:-false}"
ASSUME_YES="${ASSUME_YES:-false}"
FORCE_USB_SECURE_BOOT="${FORCE_USB_SECURE_BOOT:-false}"
# Dual-boot guard: if the target disk looks like it has Windows on it, refuse
# unless the user explicitly overrides. Prevents the single most common
# mistake (typing /dev/sda when you meant /dev/nvme1n1 on a dual-boot box).
FORCE_OVERWRITE_WINDOWS="${FORCE_OVERWRITE_WINDOWS:-false}"
USER_PASSWORD="${USER_PASSWORD:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)         DISK="$2"; shift 2 ;;
        --hostname)     TARGET_HOSTNAME="$2"; shift 2 ;;
        --user)         TARGET_USERNAME="$2"; shift 2 ;;
        --timezone)     TIMEZONE="$2"; shift 2 ;;
        --locale)       LOCALE="$2"; shift 2 ;;
        --keymap)       KEYMAP="$2"; shift 2 ;;
        --profile)      PROFILE="$2"; shift 2 ;;
        --target)       TARGET_TYPE="$2"; shift 2 ;;
        --secure-boot)  SECURE_BOOT="true"; shift ;;
        --no-secure-boot) SECURE_BOOT="false"; shift ;;
        --force-usb-secure-boot) FORCE_USB_SECURE_BOOT="true"; shift ;;
        --i-know-this-is-windows) FORCE_OVERWRITE_WINDOWS="true"; shift ;;
        --yes|-y)       ASSUME_YES="true"; shift ;;
        -h|--help)
            sed -n '2,22p' "$0"
            echo
            echo "Full flag reference: docs/install-flags.md"
            exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ "$PROFILE" == "vm" || "$PROFILE" == "personal" || "$PROFILE" == "laptop" ]] || {
    echo "PROFILE must be one of: vm | personal | laptop"; exit 2;
}
[[ "$TARGET_TYPE" == "ssd" || "$TARGET_TYPE" == "usb" || "$TARGET_TYPE" == "auto" ]] || {
    echo "TARGET_TYPE must be: ssd | usb | auto"; exit 2;
}

# ---- color helpers (re-exported so stage scripts inherit) ------------------
c_red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
c_dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
log()  { c_blue ">>> $*"; }
ok()   { c_green "  ok  $*"; }
warn() { c_yellow "  !!  $*"; }
die()  { c_red    "  XX  $*"; exit 1; }
export -f c_red c_green c_blue c_yellow c_dim log ok warn die

trap 'warn "Failed at line $LINENO: $BASH_COMMAND"' ERR

# ---- preconditions ---------------------------------------------------------
[[ $EUID -eq 0 ]] || die "bootstrap.sh must run as root (you are inside the Arch ISO)."

source "$STAGE_DIR/01-preflight.sh"

# ---- prompt for any missing values ----------------------------------------
prompt_default() {
    local var="$1" prompt="$2" default="$3"
    local current="${!var}"
    if [[ -z "$current" ]]; then
        read -r -p "$prompt [$default]: " val < /dev/tty || true
        printf -v "$var" '%s' "${val:-$default}"
    fi
}
prompt_password() {
    local var="$1" prompt="$2"
    local p1 p2
    while [[ -z "${!var}" ]]; do
        read -r -s -p "$prompt: " p1 < /dev/tty; echo
        read -r -s -p "Confirm: "  p2 < /dev/tty; echo
        [[ "$p1" == "$p2" && -n "$p1" ]] || { warn "passwords didn't match or empty, retry"; continue; }
        printf -v "$var" '%s' "$p1"
    done
}

if [[ -z "$DISK" ]]; then
    log "Available block devices:"
    # Include REM (removable) and TRAN (transport: usb/nvme/sata) so it's
    # obvious which device is a USB stick vs. the internal disk.
    lsblk -dpno NAME,SIZE,MODEL,TRAN,REM | grep -Ev 'loop|sr0|rom' || true
    prompt_default DISK "Target disk (will be ERASED)" "/dev/sda"
fi
[[ -b "$DISK" ]] || die "Disk $DISK does not exist."

# Auto-detect SSD vs USB from /sys metadata if the user didn't specify.
detect_target_type() {
    local d
    d="$(basename "$DISK" | sed -E 's/p?[0-9]+$//')"
    local rem tran
    rem="$(cat "/sys/block/$d/removable" 2>/dev/null || echo 0)"
    tran="$(lsblk -dno TRAN "$DISK" 2>/dev/null || echo)"
    if [[ "$rem" == "1" || "$tran" == "usb" ]]; then echo usb; else echo ssd; fi
}
if [[ "$TARGET_TYPE" == "auto" ]]; then
    TARGET_TYPE="$(detect_target_type)"
    log "Auto-detected target type: $TARGET_TYPE  (override with --target ssd|usb)"
fi

# Secure Boot on a USB target writes keys to the LAPTOP firmware NVRAM (not
# the USB itself), which defeats the point of testing on removable media.
# Refuse unless the user explicitly overrides with --force-usb-secure-boot.
if [[ "$TARGET_TYPE" == "usb" && "$SECURE_BOOT" == "true" && "$FORCE_USB_SECURE_BOOT" != "true" ]]; then
    warn "USB target + Secure Boot enrolls keys into the LAPTOP firmware,"
    warn "which affects any other OS installed on this machine. Disabling SB"
    warn "for this run. Pass --force-usb-secure-boot to override."
    SECURE_BOOT="false"
fi

# ---- Dual-boot safety: detect Windows on the target disk -------------------
# Run BEFORE the destroy confirmation. Scans for NTFS/exfat partitions, a
# Microsoft EFI loader directory on any FAT32 partition, and "Microsoft basic
# data" GPT type GUIDs. If any of those are present, the user almost certainly
# pointed us at the wrong disk on a dual-boot machine.
disk_looks_like_windows() {
    local d="$1" reasons=()

    # 1) NTFS or exfat filesystem signatures on any partition of this disk.
    local fstypes
    fstypes="$(lsblk -nrpo NAME,FSTYPE "$d" 2>/dev/null | awk 'NR>1 {print $2}' | tr '\n' ' ')"
    if grep -qiE '\b(ntfs|exfat)\b' <<<"$fstypes"; then
        reasons+=("NTFS/exfat partition present")
    fi

    # 2) Microsoft loader on an EFI partition. Mount each FAT32 partition
    #    read-only briefly and look for \EFI\Microsoft\Boot\bootmgfw.efi.
    local p
    for p in $(lsblk -nrpo NAME,FSTYPE "$d" 2>/dev/null | awk '$2=="vfat"{print $1}'); do
        local mnt; mnt="$(mktemp -d)"
        if mount -o ro "$p" "$mnt" 2>/dev/null; then
            if [[ -f "$mnt/EFI/Microsoft/Boot/bootmgfw.efi" ]] || \
               [[ -d "$mnt/EFI/Microsoft" ]]; then
                reasons+=("Microsoft EFI loader on $p")
            fi
            umount "$mnt" 2>/dev/null || true
        fi
        rmdir "$mnt" 2>/dev/null || true
    done

    # 3) GPT partition type GUIDs that Windows uses.
    if command -v sgdisk >/dev/null 2>&1; then
        local gpt
        gpt="$(sgdisk -p "$d" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        if grep -qE 'microsoft (basic data|reserved|recovery)' <<<"$gpt"; then
            reasons+=("Microsoft GPT partition type on $d")
        fi
    fi

    if ((${#reasons[@]} > 0)); then
        printf '%s\n' "${reasons[@]}"
        return 0
    fi
    return 1
}

windows_evidence="$(disk_looks_like_windows "$DISK" || true)"
if [[ -n "$windows_evidence" ]]; then
    c_red ""
    c_red "═══════════════════════════════════════════════════════════"
    c_red "  STOP: $DISK looks like a WINDOWS disk."
    c_red "═══════════════════════════════════════════════════════════"
    while IFS= read -r line; do c_red "    • $line"; done <<<"$windows_evidence"
    c_yellow ""
    c_yellow "  This is almost certainly NOT the disk you want to install onto."
    c_yellow "  On dual-boot machines, you want the OTHER SSD (the empty one,"
    c_yellow "  or your existing Linux disk). All disks visible right now:"
    c_yellow ""
    lsblk -dpno NAME,SIZE,MODEL,TRAN,REM | grep -Ev 'loop|sr0|rom' || true
    c_yellow ""
    if [[ "$FORCE_OVERWRITE_WINDOWS" != "true" ]]; then
        die "Refusing to wipe $DISK. Re-run with the correct --disk, or pass --i-know-this-is-windows to override."
    fi
    warn "FORCE_OVERWRITE_WINDOWS=true — proceeding to ERASE Windows on $DISK."
fi

# ---- "Other disks" preview — show what will NOT be touched -----------------
# On a dual-boot machine this is the most reassuring line: every other SSD
# in the box is listed explicitly as untouched.
other_disks="$(lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -Ev 'loop|sr0|rom' | awk -v d="$DISK" '$1!=d {print}')"

prompt_default TARGET_USERNAME "Username" "arjun"
prompt_default TARGET_HOSTNAME "Hostname" "driftos"
prompt_default TIMEZONE "Timezone (e.g. America/New_York)" "$TIMEZONE"

prompt_password USER_PASSWORD "Password for $TARGET_USERNAME"
prompt_password ROOT_PASSWORD "Password for root"

export DISK TARGET_TYPE TARGET_HOSTNAME TARGET_USERNAME TIMEZONE LOCALE KEYMAP \
       PROFILE SECURE_BOOT USER_PASSWORD ROOT_PASSWORD ASSUME_YES

# ---- summary + confirmation -----------------------------------------------
disk_size="$(lsblk -dpno SIZE "$DISK" 2>/dev/null || echo '?')"
disk_model="$(lsblk -dpno MODEL "$DISK" 2>/dev/null | xargs || echo '?')"
c_yellow ""
c_yellow "═══════════════════════════════════════════════════════════"
c_yellow "  About to DESTROY all data on $DISK and install Arch."
c_yellow "═══════════════════════════════════════════════════════════"
c_dim    "  Disk:           $DISK   ($disk_size  $disk_model)"
c_dim    "  Target type:    $TARGET_TYPE"
c_dim    "  Hostname:       $TARGET_HOSTNAME"
c_dim    "  User:           $TARGET_USERNAME"
c_dim    "  Timezone:       $TIMEZONE"
c_dim    "  Locale:         $LOCALE"
c_dim    "  Profile:        $PROFILE"
c_dim    "  Bootloader:     $([[ "$SECURE_BOOT" == "true" ]] && echo 'Limine + sbctl (Secure Boot)' || echo "GRUB$([[ "$TARGET_TYPE" == "usb" ]] && echo ' (--removable, portable)')")"
if [[ -n "$other_disks" ]]; then
c_green ""
c_green "  These disks will NOT be touched (data preserved):"
while IFS= read -r line; do c_dim    "    • $line"; done <<<"$other_disks"
fi
c_yellow ""
if [[ "$ASSUME_YES" != "true" ]]; then
    read -r -p "Type ERASE to continue, anything else to abort: " ack < /dev/tty || true
    [[ "$ack" == "ERASE" ]] || die "aborted by user"
fi

# ---- run stages -----------------------------------------------------------
bash "$STAGE_DIR/02-disk.sh"
bash "$STAGE_DIR/03-pacstrap.sh"

# Copy this entire repo into the new system under the user's homedir, so the
# rice install.sh is available immediately after first boot.
log "Copying arch-setup tree into /mnt/home/$TARGET_USERNAME/arch-setup"
install -d -m 0755 "/mnt/home/$TARGET_USERNAME"
cp -a "$ROOT_DIR/." "/mnt/home/$TARGET_USERNAME/arch-setup/"
# chown is applied inside chroot once the user exists.

# Hand off the in-chroot script through arch-chroot.
log "Entering arch-chroot for system configuration"
install -Dm755 "$STAGE_DIR/04-chroot-config.sh"     "/mnt/root/04-chroot-config.sh"
install -Dm755 "$STAGE_DIR/05-bootloader-chroot.sh" "/mnt/root/05-bootloader-chroot.sh"
install -Dm755 "$MODULES_DIR/05-bootloader-grub.sh"   "/mnt/root/modules/05-bootloader-grub.sh"
install -Dm755 "$MODULES_DIR/06-bootloader-limine.sh" "/mnt/root/modules/06-bootloader-limine.sh"

arch-chroot /mnt /bin/bash -lc "
    set -Eeuo pipefail
    export TARGET_HOSTNAME='$TARGET_HOSTNAME' TARGET_USERNAME='$TARGET_USERNAME' \
           TIMEZONE='$TIMEZONE' LOCALE='$LOCALE' KEYMAP='$KEYMAP' \
           PROFILE='$PROFILE' SECURE_BOOT='$SECURE_BOOT' \
           TARGET_TYPE='$TARGET_TYPE' \
           USER_PASSWORD='$USER_PASSWORD' ROOT_PASSWORD='$ROOT_PASSWORD' \
           IS_CHROOT=1 MODULES_DIR=/root/modules
    bash /root/04-chroot-config.sh
    bash /root/05-bootloader-chroot.sh
    rm -f /root/04-chroot-config.sh /root/05-bootloader-chroot.sh
    rm -rf /root/modules
"

# ---- finalize -------------------------------------------------------------
log "Syncing and unmounting"
sync
umount -R /mnt || warn "some mounts didn't unmount cleanly; check manually"

c_green ""
c_green "═══════════════════════════════════════════════════════════════════"
c_green "  Base Arch is installed."
c_green "═══════════════════════════════════════════════════════════════════"
c_dim    "  Next steps:"
c_dim    "    1. reboot   (then remove the install media)"
c_dim    "    2. log in as $TARGET_USERNAME on tty"
if [[ "$SECURE_BOOT" == "true" ]]; then
c_yellow "    3. (Secure Boot) enter UEFI firmware setup. If sbctl reported"
c_yellow "       that keys could not be enrolled (firmware not in Setup Mode),"
c_yellow "       clear/remove the platform key in firmware first, reboot, then"
c_yellow "       run:    sudo sb-finalize"
c_yellow "       After that, re-enable Secure Boot in firmware."
fi
c_dim    "    $([[ "$SECURE_BOOT" == "true" ]] && echo 4 || echo 3). cd ~/arch-setup && ./install.sh --profile $PROFILE"
c_green ""
