#!/usr/bin/env bash
# ~/arch-setup/install.sh
# Two-mode driver:
#   1) When run from inside the Arch ISO (live env), forwards to bootstrap.sh
#      which partitions a disk, pacstraps a base, configures it via arch-chroot,
#      and installs the bootloader (GRUB or Limine+sbctl).
#   2) When run from a normal user session on an installed system, layers on
#      the Niri rice (no bootloader work — that already happened in bootstrap).
#
# Usage (rice mode):
#   ./install.sh                        # default: --profile vm
#   ./install.sh --profile personal     # 3-monitor topology
#   PROFILE=personal ./install.sh
#
# ISO-mode flags are simply passed through to bootstrap.sh (--disk, --user, ...).
#
set -Eeuo pipefail
shopt -s inherit_errexit

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$ROOT_DIR/modules"
DOTFILES_DIR="$ROOT_DIR/dotfiles"
SCRIPTS_DIR="$ROOT_DIR/scripts"
WALLPAPERS_DIR="$ROOT_DIR/wallpapers"

export ROOT_DIR MODULES_DIR DOTFILES_DIR SCRIPTS_DIR WALLPAPERS_DIR

# ---- ISO-environment detection: forward to bootstrap.sh --------------------
if grep -q archiso /proc/cmdline 2>/dev/null || [[ -d /run/archiso ]]; then
    exec bash "$ROOT_DIR/bootstrap.sh" "$@"
fi

PROFILE="${PROFILE:-vm}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --profile=*) PROFILE="${1#*=}"; shift ;;
        --secure-boot|--no-secure-boot)
            echo "Note: --secure-boot is a bootstrap-time flag and is ignored in rice mode." ;
            shift ;;
        -h|--help)
            sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ "$PROFILE" == "vm" || "$PROFILE" == "personal" ]] || {
    echo "PROFILE must be 'vm' or 'personal'"; exit 2;
}

export PROFILE

c_red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
c_dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

export -f c_red c_green c_blue c_dim

log()  { c_blue ">>> $*"; }
ok()   { c_green "  ok  $*"; }
warn() { c_red "  !!  $*"; }
export -f log ok warn

trap 'warn "Failed at line $LINENO: $BASH_COMMAND"' ERR

[[ $EUID -eq 0 ]] && { warn "Run as a normal user with sudo access, not root."; exit 1; }
command -v sudo >/dev/null || { warn "sudo is required"; exit 1; }
sudo -v

log "Rice mode — Profile: $PROFILE"

run_mod() {
    local m="$1"
    [[ -x "$MODULES_DIR/$m" ]] || chmod +x "$MODULES_DIR/$m"
    log "module → $m"
    bash "$MODULES_DIR/$m"
    ok    "module → $m"
}

# Rice flow: bootloader is intentionally NOT here — bootstrap.sh did that
# inside arch-chroot during bare-metal install.
run_mod 01-base-packages.sh
run_mod 02-yay-bootstrap.sh
run_mod 03-aur-packages.sh
run_mod 04-niri-stack.sh
run_mod 00-display-config.sh
run_mod 07-services.sh
run_mod 08-link-dotfiles.sh
run_mod 09-wallpapers.sh

c_green ""
c_green "═══════════════════════════════════════════════════════════"
c_green "  Setup complete. Reboot, then select 'Niri' at greetd/tty."
c_green "═══════════════════════════════════════════════════════════"
