#!/usr/bin/env bash
# add-windows-limine.sh — add a Windows entry to the live Limine menu, safely,
# on an ALREADY-INSTALLED system. Run once with sudo:
#
#     sudo scripts/add-windows-limine.sh
#
# What it does (all idempotent, re-runnable):
#   1. Probes every EFI System Partition (other than our own /boot ESP) for the
#      Microsoft bootloader and records the winner's GPT partition GUID in
#      /etc/limine-windows.conf.
#   2. Teaches the live config generator (/usr/local/bin/limine-regen-conf) to
#      emit a Windows chainload entry from that file — so it survives every
#      kernel/limine/systemd update (the pacman hook regenerates the config).
#   3. Runs limine-resign (regenerate config -> re-enroll its checksum ->
#      re-sign primary+rescue, atomically).
#
# Secure Boot: chainloading is the DOCUMENTED Secure Boot exception in Limine —
# the firmware verifies bootmgfw.efi against db, where `sbctl enroll-keys
# --microsoft` already placed Microsoft's CAs. No blake2b #hash is needed and NO
# firmware keys (db/KEK/PK) are touched. Secure Boot stays ENABLED and unchanged;
# PCR 7 is undisturbed. Arch (entry 1) stays the default; Windows is just listed.
#
# This is the post-install counterpart of the probe baked into
# modules/06-bootloader-limine.sh, which does the same thing during a fresh install.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo $0" >&2; exit 1; }
[[ -x /usr/local/bin/limine-resign ]] || {
    echo "ERROR: /usr/local/bin/limine-resign missing — is this the Limine+sbctl install?" >&2
    exit 1
}

# 1) Find the Windows ESP (must actually contain bootmgfw.efi).
ESP_SRC="$(findmnt -no SOURCE /boot)"
win=""
while read -r name parttype partuuid; do
    [[ "$parttype" == c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] || continue  # EFI System Partition
    [[ "/dev/$name" == "$ESP_SRC" ]] && continue                           # skip our own ESP
    probe="$(mktemp -d)"
    if mount -o ro "/dev/$name" "$probe" 2>/dev/null; then
        [[ -f "$probe/EFI/Microsoft/Boot/bootmgfw.efi" ]] && win="$partuuid"
        umount "$probe" 2>/dev/null || true
    fi
    rmdir "$probe" 2>/dev/null || true
    [[ -n "$win" ]] && break
done < <(lsblk -rno NAME,PARTTYPE,PARTUUID)
[[ -n "$win" ]] || { echo "ERROR: no Windows bootloader (bootmgfw.efi) found on any ESP" >&2; exit 1; }

printf 'WINDOWS_ESP_GUID=%s\nWINDOWS_EFI_PATH=%s\n' "$win" /EFI/Microsoft/Boot/bootmgfw.efi \
    | install -Dm644 /dev/stdin /etc/limine-windows.conf
echo ">> wrote /etc/limine-windows.conf  (WINDOWS_ESP_GUID=$win)"

# 2) Teach the live generator about Windows (insert once, before the redirect).
gen=/usr/local/bin/limine-regen-conf
if grep -q 'limine-windows.conf' "$gen"; then
    echo ">> $gen already Windows-aware — leaving as is"
else
    tmp="$(mktemp)"
    awk '
        /^\} > "\$TMP"$/ && !ins {
            print "    if [[ -f /etc/limine-windows.conf ]]; then"
            print "        WINDOWS_ESP_GUID=\"\""
            print "        WINDOWS_EFI_PATH=\"/EFI/Microsoft/Boot/bootmgfw.efi\""
            print "        . /etc/limine-windows.conf"
            print "        if [[ -n \"$WINDOWS_ESP_GUID\" ]]; then"
            print "            printf \047/Windows\\n    protocol: efi_chainload\\n    path: guid(%s):%s\\n\\n\047 \"$WINDOWS_ESP_GUID\" \"$WINDOWS_EFI_PATH\""
            print "        fi"
            print "    fi"
            ins=1
        }
        { print }
    ' "$gen" > "$tmp"
    grep -q 'limine-windows.conf' "$tmp" || { echo "ERROR: failed to patch $gen (insertion point not found)" >&2; rm -f "$tmp"; exit 1; }
    install -Dm755 "$tmp" "$gen"
    rm -f "$tmp"
    echo ">> patched $gen"
fi

# 2b) Set the boot menu timeout to 5 seconds (idempotent).
if grep -qE 'echo "timeout: [0-9]+"' "$gen"; then
    sed -i -E 's/echo "timeout: [0-9]+"/echo "timeout: 5"/' "$gen"
    echo ">> set Limine timeout to 5s in $gen"
fi

# 3) Regenerate config + re-enroll its checksum + re-sign (atomic).
/usr/local/bin/limine-resign
echo ">> limine-resign complete"

echo
echo "==== /boot/limine.conf ===="
cat /boot/limine.conf
