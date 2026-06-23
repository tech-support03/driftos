#!/usr/bin/env bash
# 06-bootloader-limine.sh — bare-metal Secure Boot path: Limine + sbctl.
# Hashes kernel assets with BLAKE2B and signs everything on every pacman/mkinitcpio update.
# Runs in two contexts:
#   - directly on an installed system (sudo elevates)
#   - inside arch-chroot during bare-metal install (IS_CHROOT=1, root)
#
# Boot-chain integrity (firmware → ... → kernel):
#   1. UEFI Secure Boot verifies the Limine EFI binary  (sbctl signature).
#   2. Limine verifies limine.conf                       (BLAKE2B checksum baked
#                                                          into the EFI binary via
#                                                          `limine enroll-config`).
#   3. limine.conf verifies each kernel/initramfs        (per-file BLAKE2B `#hash`
#                                                          appended to its path).
# Both checks (2 and 3) are enforced when UEFI Secure Boot is active — Limine
# forces hash_mismatch_panic=yes in that state. Links 2+3 are coupled: limine.conf
# and the binary's enrolled checksum MUST be updated together or Limine panics with
# "CHECKSUM MISMATCH FOR CONFIG FILE" and halts. The resign helper below therefore
# stages everything on temp files and only swaps the live copies in after every
# fallible step has succeeded, and a separate UNENROLLED *rescue* binary (no config
# checksum baked in) lets you recover a config-checksum mismatch from the firmware
# boot menu without a USB.
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

# Guard: this sbctl path enrolls our keys into the firmware's db, which requires
# Setup Mode and rewrites PCR 7 — fine for a machine we own, catastrophic for a
# portable stick (triggers BitLocker on every Windows host). USB targets MUST use
# the shim+MOK module instead. See CLAUDE.md §11.
if [[ "${TARGET_TYPE:-ssd}" == "usb" ]]; then
    warn "Refusing sbctl/enroll-keys on a USB target — use modules/10-bootloader-shim-mok.sh"
    warn "(shim+MOK). That avoids touching firmware keys and BitLocker (CLAUDE.md §11)."
    exit 1
fi

log "Installing Limine + sbctl + helpers"
# limine + efibootmgr + sbctl are in extra. BLAKE2B hashing uses b2sum from
# coreutils (always present) — Limine wants BLAKE2B, not BLAKE3.
sudo pacman -S --needed --noconfirm efibootmgr sbctl
# Force-reinstall limine on every run so /usr/share/limine/BOOTX64.EFI is the
# pristine package copy. The resign helper always rebuilds the ESP binaries from
# this pristine source (cp → enroll → sign), so a prior in-place sbctl signature
# or stacked enroll-config edit can never corrupt the next build.
sudo pacman -S --noconfirm limine

ESP="${ESP:-/boot}"
if ! mountpoint -q "$ESP"; then
    for cand in /boot/efi /efi; do
        mountpoint -q "$cand" && { ESP="$cand"; break; }
    done
fi
log "ESP: $ESP"

sudo mkdir -p "$ESP/EFI/BOOT" "$ESP/EFI/limine" "$ESP/EFI/limine-rescue"
sudo cp -v /usr/share/limine/limine.sys "$ESP/EFI/limine/" 2>/dev/null || true

# ---- on-target helper scripts ---------------------------------------------
# Installed first because the initial setup below runs limine-resign itself, so
# install-time and update-time use the exact same code path.

# limine-emit-theme — print the general-section theme keys (branding + colours)
# from /etc/limine-theme.conf. Called by limine-regen-conf below. Colours are
# data in /etc/limine-theme.conf (NOT baked into the generator) so the look can
# be re-themed from the rice palette (scripts/theme-limine.sh) without editing
# this script, and an absent/empty file falls back to plain "Arch Linux"
# branding — i.e. exactly the previous behaviour, so it can never break boot.
# These keys live INSIDE limine.conf, so they're covered by the enrolled BLAKE2B
# config checksum and ride through limine-resign like every other entry.
# NOTE: keep this byte-identical to the copy installed by scripts/theme-limine.sh.
sudo install -Dm755 /dev/stdin /usr/local/bin/limine-emit-theme <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
# All colours are bare RRGGBB hex (NO leading '#'). Empty => Limine default.
LIMINE_BRANDING="Arch Linux"
LIMINE_BRANDING_COLOUR=""
LIMINE_HELP_COLOUR=""
LIMINE_HELP_COLOUR_BRIGHT=""
LIMINE_BACKDROP=""
LIMINE_TERM_BG=""
LIMINE_TERM_BG_BRIGHT=""
LIMINE_TERM_FG=""
LIMINE_TERM_FG_BRIGHT=""
LIMINE_PALETTE=""
LIMINE_PALETTE_BRIGHT=""
LIMINE_TERM_MARGIN=""
LIMINE_TERM_MARGIN_GRADIENT=""
[[ -f /etc/limine-theme.conf ]] && . /etc/limine-theme.conf
emit() { [[ -n "$2" ]] && echo "$1: $2"; return 0; }
echo "interface_branding: $LIMINE_BRANDING"
emit interface_branding_colour   "$LIMINE_BRANDING_COLOUR"
emit interface_help_colour        "$LIMINE_HELP_COLOUR"
emit interface_help_colour_bright "$LIMINE_HELP_COLOUR_BRIGHT"
emit backdrop                     "$LIMINE_BACKDROP"
emit term_background              "$LIMINE_TERM_BG"
emit term_background_bright       "$LIMINE_TERM_BG_BRIGHT"
emit term_foreground              "$LIMINE_TERM_FG"
emit term_foreground_bright       "$LIMINE_TERM_FG_BRIGHT"
emit term_palette                 "$LIMINE_PALETTE"
emit term_palette_bright          "$LIMINE_PALETTE_BRIGHT"
emit term_margin                  "$LIMINE_TERM_MARGIN"
emit term_margin_gradient         "$LIMINE_TERM_MARGIN_GRADIENT"
EOF

# Default theme data — indigo rice palette, Omarchy-style flat menu with a soft
# accent margin-gradient frame. Installed only if absent so a re-run never
# clobbers a palette the user has since synced from rice-theme. Bare RRGGBB hex.
if [[ ! -f /etc/limine-theme.conf ]]; then
    sudo install -Dm644 /dev/stdin /etc/limine-theme.conf <<'EOF'
# /etc/limine-theme.conf — colours + branding for the Limine boot menu.
# Sourced by /usr/local/bin/limine-emit-theme. Re-theme from your rice palette
# with: sudo scripts/theme-limine.sh   (then it re-signs via limine-resign).
# All colours are bare RRGGBB hex (NO leading '#'). Empty => Limine default.
LIMINE_BRANDING="Arch Linux"
LIMINE_BRANDING_COLOUR="7d8cff"
LIMINE_HELP_COLOUR="8e8e96"
LIMINE_HELP_COLOUR_BRIGHT="c9c9d0"
LIMINE_BACKDROP="14141b"
LIMINE_TERM_BG="14141b"
LIMINE_TERM_BG_BRIGHT="222230"
LIMINE_TERM_FG="c9c9d0"
LIMINE_TERM_FG_BRIGHT="f4f4f6"
LIMINE_PALETTE="2a2a35;f43f5e;2dd4bf;e0af68;60a5fa;5b6ee0;22d3ee;c9c9d0"
LIMINE_PALETTE_BRIGHT="3a3a48;ff6b81;3ee6cf;f0c07a;7db4ff;7d8cff;5fe0f5;f4f4f6"
LIMINE_TERM_MARGIN="48"
LIMINE_TERM_MARGIN_GRADIENT="4"
EOF
fi

# limine-regen-conf <ESP> [outfile] — write a limine.conf with BLAKE2B path
# hashes. Defaults to the live config; the resign helper passes a temp outfile.
sudo install -Dm755 /dev/stdin /usr/local/bin/limine-regen-conf <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
ESP="${1:-/boot}"
OUT="${2:-$ESP/limine.conf}"
ROOT_UUID="$(findmnt -no UUID /)"
TMP="$(mktemp)"
{
    echo "timeout: 5"
    echo "default_entry: 1"
    limine-emit-theme        # branding + colours from /etc/limine-theme.conf
    echo ""
    for vmlinuz in "$ESP"/vmlinuz-*; do
        [[ -f "$vmlinuz" ]] || continue
        kernel="$(basename "$vmlinuz")"
        flavour="${kernel#vmlinuz-}"
        initramfs="initramfs-${flavour}.img"
        [[ -f "$ESP/$initramfs" ]] || initramfs="initramfs-${flavour}-fallback.img"
        kern_hash="$(b2sum "$vmlinuz" | awk '{print $1}')"
        init_hash="$(b2sum "$ESP/$initramfs" | awk '{print $1}')"
        cat <<E
/Arch Linux ($flavour)
    protocol: linux
    kernel_path: boot():/$kernel#$kern_hash
    kernel_cmdline: root=UUID=$ROOT_UUID rw quiet loglevel=3
    module_path: boot():/$initramfs#$init_hash

E
    done

    # --- Windows (chainload), optional ------------------------------------
    # /etc/limine-windows.conf is written once at install time (see the probe
    # below) with WINDOWS_ESP_GUID=<GPT partition GUID of the Windows ESP>.
    # Chainloading is the documented Secure Boot EXCEPTION (Limine USAGE.md):
    # the firmware verifies bootmgfw.efi against db — where our `sbctl
    # enroll-keys --microsoft` already placed Microsoft's CAs — so this needs
    # NO blake2b #hash and touches NO firmware keys. Secure Boot stays enabled
    # and unchanged. Arch (entry 1) stays default; Windows is just listed below.
    if [[ -f /etc/limine-windows.conf ]]; then
        WINDOWS_ESP_GUID=""
        WINDOWS_EFI_PATH="/EFI/Microsoft/Boot/bootmgfw.efi"
        . /etc/limine-windows.conf
        if [[ -n "$WINDOWS_ESP_GUID" ]]; then
            printf '/Windows\n    protocol: efi_chainload\n    path: guid(%s):%s\n\n' \
                "$WINDOWS_ESP_GUID" "$WINDOWS_EFI_PATH"
        fi
    fi
} > "$TMP"
install -Dm644 "$TMP" "$OUT"
rm -f "$TMP"
EOF

# limine-resign — the failure-safe rebuild. Order matters: rebuild everything on
# temp paths (regen conf, pristine→enroll→sign primary, pristine→sign rescue),
# and only swap the live copies in once every fallible step has succeeded. A
# failed sign/enroll then leaves the previous, still-matching config + binary
# untouched instead of stranding a half-updated pair that panics on next boot.
sudo install -Dm755 /dev/stdin /usr/local/bin/limine-resign <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

PRISTINE=/usr/share/limine/BOOTX64.EFI
ESP="$(mountpoint -q /boot && echo /boot || (mountpoint -q /efi && echo /efi || echo /boot/efi))"
PRIMARY="$ESP/EFI/BOOT/BOOTX64.EFI"
RESCUE="$ESP/EFI/limine-rescue/BOOTX64.EFI"
mkdir -p "$(dirname "$PRIMARY")" "$(dirname "$RESCUE")"

# 1. Regenerate the config to a temp file (NOT the live path).
CONF_NEW="$ESP/limine.conf.new"
limine-regen-conf "$ESP" "$CONF_NEW"
CONF_HASH="$(b2sum "$CONF_NEW" | awk '{print $1}')"

# 2. Primary binary on a temp path: pristine copy → enroll config checksum →
#    sign. Starting from the pristine package binary avoids stacking enroll-config
#    edits and stale signatures across updates.
cp -f "$PRISTINE" "$PRIMARY.new"
limine enroll-config "$PRIMARY.new" "$CONF_HASH" --quiet
sbctl sign "$PRIMARY.new"

# 3. Rescue binary on a temp path: pristine copy → sign, NO enroll. With no
#    enrolled checksum it skips the config-checksum check (it still honours the
#    per-file kernel/initramfs #hash entries, which match because we just
#    regenerated the config), so a config-checksum mismatch is recoverable from
#    the firmware boot menu without a USB.
cp -f "$PRISTINE" "$RESCUE.new"
sbctl sign "$RESCUE.new"

# 4. Everything signed — commit. Renames on one filesystem are ~atomic and no
#    fallible command runs between them, so the config and the binary that
#    enforces its checksum land together.
mv -f "$PRIMARY.new" "$PRIMARY"
mv -f "$RESCUE.new"  "$RESCUE"
mv -f "$CONF_NEW"    "$ESP/limine.conf"

# 5. Record the canonical paths in sbctl's db so its own hook keeps them signed
#    across key rotations. Idempotent and non-bricking if it fails — the live
#    binaries are already validly signed from steps 2-3.
for efi in "$PRIMARY" "$RESCUE"; do
    sbctl remove-file "$efi" 2>/dev/null || true
    sbctl sign -s "$efi" || true
done
EOF

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

# ---- probe for Windows → optional chainload entry -------------------------
# Find an EFI System Partition (other than our own ESP) that actually contains
# the Microsoft bootloader, and record its GPT partition GUID in
# /etc/limine-windows.conf. The generator above turns that into a chainload
# entry. Chainloading is the Secure Boot exception (firmware verifies
# bootmgfw.efi against the enrolled MS certs), so this needs no hash and touches
# no keys. Re-running the module re-probes and keeps the file current.
log "Probing for a Windows bootloader to add as a chainload entry"
ESP_SRC_DEV="$(findmnt -no SOURCE "$ESP")"
win_guid=""
while read -r _name _parttype _partuuid; do
    [[ "$_parttype" == c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] || continue  # ESP type GUID
    dev="/dev/$_name"
    [[ "$dev" == "$ESP_SRC_DEV" ]] && continue                              # skip our own ESP
    probe="$(mktemp -d)"
    if sudo mount -o ro "$dev" "$probe" 2>/dev/null; then
        [[ -f "$probe/EFI/Microsoft/Boot/bootmgfw.efi" ]] && win_guid="$_partuuid"
        sudo umount "$probe" 2>/dev/null || true
    fi
    rmdir "$probe" 2>/dev/null || true
    [[ -n "$win_guid" ]] && break
done < <(lsblk -rno NAME,PARTTYPE,PARTUUID)
if [[ -n "$win_guid" ]]; then
    log "Found Windows on GUID $win_guid — writing /etc/limine-windows.conf"
    printf 'WINDOWS_ESP_GUID=%s\nWINDOWS_EFI_PATH=%s\n' \
        "$win_guid" "/EFI/Microsoft/Boot/bootmgfw.efi" \
        | sudo install -Dm644 /dev/stdin /etc/limine-windows.conf
else
    warn "No Windows bootloader found on any ESP — skipping chainload entry"
fi

# ---- initial bootloader build (same path as every later update) -----------
log "Building limine.conf + signed primary/rescue binaries via limine-resign"
sudo /usr/local/bin/limine-resign

# ---- NVRAM entries (idempotent) -------------------------------------------
# Two entries: "Limine" (enforces the enrolled config checksum) and
# "Limine (rescue)" (same config, no enrolled checksum) so a config-checksum
# mismatch can be escaped from the firmware boot menu. Create the rescue entry FIRST so
# the later-created primary lands ahead of it in BootOrder and stays the default
# (efibootmgr --create prepends to BootOrder).
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    warn "efivars not mounted — skipping efibootmgr. Most fallback firmwares will still boot \EFI\BOOT\BOOTX64.EFI."
else
    ESP_SRC="$(findmnt -no SOURCE "$ESP")"
    if [[ "$ESP_SRC" =~ ^(.*[a-z])([0-9]+)$ ]]; then
        ESP_DISK="${BASH_REMATCH[1]}"; ESP_PART="${BASH_REMATCH[2]}"
        # NVMe partitions end with pN — drop the trailing 'p'.
        [[ "$ESP_DISK" =~ p$ ]] && ESP_DISK="${ESP_DISK%p}"
    fi
    if [[ -n "${ESP_DISK:-}" && -n "${ESP_PART:-}" ]]; then
        # Exact-label match: strip the "BootNNNN* " prefix, take the label field
        # (up to the first tab that -v adds before the device path), compare whole
        # strings so "Limine" doesn't spuriously match "Limine (rescue)".
        entry_exists() {
            efibootmgr 2>/dev/null \
                | sed -n 's/^Boot[0-9A-Fa-f]\{4\}\*\? //p' \
                | cut -f1 | grep -qxF "$1"
        }
        mk_entry() {  # label loader
            entry_exists "$1" && return 0
            sudo efibootmgr --create --disk "$ESP_DISK" --part "$ESP_PART" \
                --label "$1" --loader "$2" \
                || warn "efibootmgr failed for '$1'; fallback boot path will still work"
        }
        mk_entry "Limine (rescue)" '\EFI\limine-rescue\BOOTX64.EFI'
        mk_entry "Limine"          '\EFI\BOOT\BOOTX64.EFI'
    else
        warn "could not parse ESP source '$ESP_SRC' — skipping NVRAM entries"
    fi
fi

# ---- pacman hook ----------------------------------------------------------
log "Installing pacman hook for re-sign + re-enroll on kernel/bootloader updates"
sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/95-limine-resign.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened
Target = mkinitcpio
Target = limine
Target = systemd

[Action]
Description = Rebuilding limine.conf + re-enrolling checksum + re-signing (primary + rescue)
When = PostTransaction
Exec = /usr/local/bin/limine-resign
EOF

ok "Limine + sbctl Secure Boot stack configured"
