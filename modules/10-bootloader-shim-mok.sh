#!/usr/bin/env bash
# 10-bootloader-shim-mok.sh — USB / removable Secure Boot path: shim + GRUB + MOK.
#
# This is the REMOVABLE-MEDIA counterpart to 06-bootloader-limine.sh. It exists
# because a portable stick gets plugged into machines we do not own, where the
# bare-metal sbctl approach is actively harmful:
#
#   sbctl enroll-keys  →  rewrites firmware db / needs Setup Mode (clear PK)
#                      →  changes TPM PCR 7
#                      →  triggers BitLocker recovery on the host's Windows
#
# Instead we use the shim chain, which leaves the host firmware's keys ALONE:
#
#   firmware  →  shim (Microsoft-signed, already trusted by db; no key changes)
#            →  grubx64.efi (signed with OUR MOK)
#            →  vmlinuz     (signed with OUR MOK)
#
# The MOK lives in shim's own MokList variable, NOT in db/KEK/PK. Windows never
# measures MokList into PCR 7, so BitLocker is undisturbed and Secure Boot stays
# ENABLED the whole time. The one manual step is a single MokManager enrollment
# on first boot of each new host (see the printed instructions at the end).
#
# Layout written to the ESP (mounted at /boot here, same as the Limine path):
#   /boot/EFI/BOOT/BOOTX64.EFI   = shimx64.efi   (MS-signed, firmware entry point)
#   /boot/EFI/BOOT/grubx64.efi   = GRUB          (signed with MOK; shim loads this)
#   /boot/EFI/BOOT/mmx64.efi     = MokManager    (MS-signed, enrollment UI)
#   /boot/EFI/BOOT/MOK.der       = our public key (browse to this in MokManager)
#   /boot/grub/grub.cfg          = two entries: full rice + light profile
#
# Env in:
#   SHIM_SRC   dir holding shimx64.efi + mmx64.efi (default /usr/share/shim-signed).
#              The orchestrator must stage these into the target before chroot,
#              because shim-signed is an AUR package and yay won't build as root
#              inside arch-chroot. On a from-host build, point at the host copy.
#   ESP        ESP mountpoint (default /boot).
set -Eeuo pipefail

if [[ $EUID -eq 0 ]]; then
    sudo() { "$@"; }
fi
command -v log  >/dev/null 2>&1 || log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
command -v ok   >/dev/null 2>&1 || ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
command -v warn >/dev/null 2>&1 || warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
command -v die  >/dev/null 2>&1 || die()  { printf '\033[1;31m  XX\033[0m %s\n' "$*"; exit 1; }

[[ -d /sys/firmware/efi ]] || die "shim+MOK requires UEFI; firmware is not EFI."

ESP="${ESP:-/boot}"
mountpoint -q "$ESP" || die "ESP not mounted at $ESP"
BOOTDIR="$ESP/EFI/BOOT"

SHIM_SRC="${SHIM_SRC:-/usr/share/shim-signed}"
[[ -f "$SHIM_SRC/shimx64.efi" && -f "$SHIM_SRC/mmx64.efi" ]] \
    || die "shim binaries not found in $SHIM_SRC — install shim-signed (AUR) and stage it, or set SHIM_SRC."

log "Installing grub + signing tooling"
sudo pacman -S --needed --noconfirm grub efibootmgr dosfstools mtools sbsigntools mokutil

# ---- MOK keypair -----------------------------------------------------------
# Persisted on the ROOT fs (not the ESP) so the private key isn't sitting on the
# FAT partition. .der is the DER-encoded public cert MokManager enrolls.
MOKDIR=/etc/secureboot/mok
sudo install -d -m700 "$MOKDIR"
if [[ ! -f "$MOKDIR/MOK.key" ]]; then
    log "Generating Machine Owner Key (MOK)"
    sudo openssl req -newkey rsa:2048 -nodes -keyout "$MOKDIR/MOK.key" \
        -new -x509 -sha256 -days 3650 -subj "/CN=driftOS USB MOK/" \
        -out "$MOKDIR/MOK.crt"
    sudo openssl x509 -outform DER -in "$MOKDIR/MOK.crt" -out "$MOKDIR/MOK.der"
fi

# ---- shim + MokManager into the firmware fallback path ---------------------
# \EFI\BOOT\BOOTX64.EFI is the removable-media path every UEFI (and the 2014
# MacBook's EFI) boots without an NVRAM entry. shim then loads grubx64.efi from
# its OWN directory, so GRUB goes in EFI/BOOT too.
log "Placing shim + MokManager in $BOOTDIR"
sudo install -d "$BOOTDIR"
sudo install -Dm644 "$SHIM_SRC/shimx64.efi" "$BOOTDIR/BOOTX64.EFI"
sudo install -Dm644 "$SHIM_SRC/mmx64.efi"   "$BOOTDIR/mmx64.efi"
sudo install -Dm644 "$MOKDIR/MOK.der"       "$BOOTDIR/MOK.der"

# ---- GRUB image ------------------------------------------------------------
# We want the shim verifier baked in so a GRUB launched BY shim refuses to boot
# a kernel that isn't signed by db or an enrolled MOK. Up to grub 2.12 that was a
# separate loadable module, shim_lock.mod; grub 2.14 folds the verifier into the
# core EFI image, so shim_lock.mod no longer exists and naming it in --modules
# makes grub-install abort ("cannot open .../shim_lock.mod"). To work on both, we
# filter the desired list down to modules this grub actually ships — shim_lock is
# added when present, and silently dropped (already built in) when it isn't.
GRUB_MODDIR="/usr/lib/grub/x86_64-efi"
GRUB_MODULES=""
for _m in normal test efi_gop efi_uga part_gpt fat ext2 search search_fs_uuid \
          linux echo all_video gfxterm loadenv configfile tpm shim_lock; do
    [[ -f "$GRUB_MODDIR/$_m.mod" ]] && GRUB_MODULES="$GRUB_MODULES $_m"
done
GRUB_MODULES="${GRUB_MODULES# }"
SBAT_ARGS=(); [[ -f /usr/share/grub/sbat.csv ]] && SBAT_ARGS=(--sbat /usr/share/grub/sbat.csv)
log "Building grubx64.efi (modules: $GRUB_MODULES)"
sudo grub-install \
    --target=x86_64-efi \
    --efi-directory="$ESP" \
    --boot-directory="$ESP" \
    --bootloader-id=BOOT \
    --modules="$GRUB_MODULES" \
    "${SBAT_ARGS[@]}" \
    --no-nvram --removable --recheck
# grub-install --removable --bootloader-id=BOOT writes EFI/BOOT/BOOTX64.EFI; we
# do NOT want GRUB there (shim must own that name). Move GRUB to grubx64.efi and
# restore shim as BOOTX64.EFI.
sudo mv -f "$BOOTDIR/BOOTX64.EFI" "$BOOTDIR/grubx64.efi"
sudo install -Dm644 "$SHIM_SRC/shimx64.efi" "$BOOTDIR/BOOTX64.EFI"

# ---- grub.cfg: full rice + light profile -----------------------------------
# The profile is passed on the kernel cmdline (rice.profile=); the session
# reads /proc/cmdline at niri start to pick the full vs light config set.
ROOT_UUID="$(findmnt -no UUID /)"
# The kernel + initramfs + ucode live on the ESP (this layout has /boot == the FAT
# ESP), so GRUB must set its $root to the ESP to FIND them — not to the ext4 root.
# The ext4 root UUID is only used for the kernel's own root= param (mounting /).
ESP_UUID="$(findmnt -no UUID "$ESP")"
UCODE=""
[[ -f "$ESP/amd-ucode.img"   ]] && UCODE="$UCODE /amd-ucode.img"
[[ -f "$ESP/intel-ucode.img" ]] && UCODE="$UCODE /intel-ucode.img"
log "Writing grub.cfg (root UUID=$ROOT_UUID, ucode=${UCODE:-none})"
sudo install -d "$ESP/grub"
sudo install -Dm644 /dev/stdin "$ESP/grub/grub.cfg" <<EOF
set timeout=3
set default=0
insmod all_video
insmod gfxterm
terminal_output gfxterm
search --no-floppy --fs-uuid --set=root $ESP_UUID

menuentry "driftOS — full rice (laptop / desktop)" {
    linux  /vmlinuz-linux root=UUID=$ROOT_UUID rw quiet loglevel=3 rice.profile=full
    initrd$UCODE /initramfs-linux.img
}
menuentry "driftOS — light (4GB / MacBook Air)" {
    linux  /vmlinuz-linux root=UUID=$ROOT_UUID rw quiet loglevel=3 rice.profile=light
    initrd$UCODE /initramfs-linux.img
}
EOF

# ---- on-target re-sign helper ----------------------------------------------
# Kernel + GRUB must be re-signed with the MOK after every kernel/grub update,
# exactly like the Limine path re-signs on update. Same MOK = no re-enrollment.
sudo install -Dm755 /dev/stdin /usr/local/bin/shim-mok-resign <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
MOKDIR=/etc/secureboot/mok
ESP="$(mountpoint -q /boot && echo /boot || (mountpoint -q /efi && echo /efi || echo /boot/efi))"
sign() {  # path
    sbsign --key "$MOKDIR/MOK.key" --cert "$MOKDIR/MOK.crt" --output "$1" "$1"
    sbverify --cert "$MOKDIR/MOK.crt" "$1" >/dev/null
}
sign "$ESP/EFI/BOOT/grubx64.efi"
for k in "$ESP"/vmlinuz-*; do [[ -f "$k" ]] && sign "$k"; done
echo "shim-mok-resign: grub + $(ls "$ESP"/vmlinuz-* 2>/dev/null | wc -l) kernel(s) signed"
EOF

log "Signing grubx64.efi + kernel with MOK (and verifying)"
sudo /usr/local/bin/shim-mok-resign

# ---- pacman hook: re-sign on kernel/grub updates ---------------------------
sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/95-shim-mok-resign.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened
Target = mkinitcpio
Target = grub

[Action]
Description = Re-signing GRUB + kernel with the Machine Owner Key (shim chain)
When = PostTransaction
Exec = /usr/local/bin/shim-mok-resign
EOF

# ---- optional NVRAM entry --------------------------------------------------
# Purely a convenience label for the laptop's firmware boot menu; the removable
# \EFI\BOOT\BOOTX64.EFI fallback is what actually makes the stick portable (and
# is the ONLY thing the 2014 Mac will see via the Option-key picker).
if [[ -d /sys/firmware/efi/efivars ]]; then
    ESP_SRC="$(findmnt -no SOURCE "$ESP")"
    if [[ "$ESP_SRC" =~ ^(/dev/.*[a-z])p?([0-9]+)$ ]]; then
        ESP_DISK="${BASH_REMATCH[1]}"; ESP_PART="${BASH_REMATCH[2]}"
        [[ "$ESP_DISK" =~ p$ ]] && ESP_DISK="${ESP_DISK%p}"
        if ! efibootmgr 2>/dev/null | sed -n 's/^Boot[0-9A-Fa-f]\{4\}\*\? //p' | cut -f1 | grep -qxF "driftOS USB"; then
            sudo efibootmgr --create --disk "$ESP_DISK" --part "$ESP_PART" \
                --label "driftOS USB" --loader '\EFI\BOOT\BOOTX64.EFI' \
                || warn "efibootmgr entry failed; removable fallback path still boots"
        fi
    fi
fi

cat <<EOF

  ┌─ shim + MOK installed. FIRST BOOT ON A NEW HOST (one time per machine):
  │
  │  1. Boot menu → pick the USB  (laptop: F12/F9;  Mac: hold Option ⌥).
  │  2. shim shows a blue "MOK management" screen → Enroll key from disk
  │     → browse to  EFI/BOOT/MOK.der  → Continue → reboot.
  │  3. From then on it boots straight through with Secure Boot ENABLED.
  │
  │  No firmware keys are changed, Setup Mode is never entered, and the host's
  │  BitLocker (PCR 7) is never disturbed.
  └─
EOF
ok "shim+MOK Secure Boot stack configured (USB/removable)"
