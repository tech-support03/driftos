#!/usr/bin/env bash
# gpu-check — verifies the GPU/EGL/GBM stack Niri needs. Run from a tty when
# Niri refuses to render. Prints one section per check; "FAIL" lines are the
# ones that matter.
set -u

c_green(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
c_red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_blue() { printf '\033[1;34m%s\033[0m\n' "$*"; }
c_dim()  { printf '\033[2m%s\033[0m\n' "$*"; }
ok()   { c_green "  ok  $*"; }
fail() { c_red   "  FAIL $*"; }
hd()   { c_blue "\n── $* ──────────────────────────────"; }

hd "Virtualization"
v="$(systemd-detect-virt 2>/dev/null || echo unknown)"
c_dim "  systemd-detect-virt: $v"
case "$v" in
    vmware)
        c_red "  VMware detected. Niri requires a working GBM/EGL allocator and"
        c_red "  vmwgfx does not reliably provide one. Even with 'Accelerate 3D"
        c_red "  Graphics' enabled in VM settings, the result is hit-or-miss."
        c_red "  Recommended: switch to KVM/QEMU + virtio-gpu (works reliably)"
        c_red "  or install on bare metal."
        ;;
    kvm|qemu)  ok "KVM/QEMU — should work with virtio-gpu" ;;
    oracle)    c_dim "  VirtualBox — needs VMSVGA + 3D enabled" ;;
    none)      ok "bare metal" ;;
esac

hd "Display GPU (lspci)"
lspci -k 2>/dev/null | grep -A2 -E 'VGA|3D|Display' || fail "no VGA controller found"

hd "DRM devices"
if ls /dev/dri/ >/dev/null 2>&1; then
    ls -l /dev/dri/
    [[ -e /dev/dri/renderD128 ]] && ok "render node present" || fail "no /dev/dri/renderD128"
else
    fail "/dev/dri is missing — kernel DRM not exposed"
fi

hd "DRM kernel driver"
for c in /sys/class/drm/card*/device/driver; do
    [[ -L "$c" ]] && c_dim "  $c → $(readlink -f "$c")"
done

hd "OpenGL renderer"
if command -v glxinfo >/dev/null 2>&1; then
    glxinfo -B 2>/dev/null | grep -iE 'renderer|opengl (core|version)' || fail "glxinfo produced no output (no X server / no GL)"
    if glxinfo -B 2>/dev/null | grep -qi 'llvmpipe'; then
        fail "GL renderer is llvmpipe (software). Hardware acceleration NOT working."
    fi
else
    c_dim "  glxinfo not installed (mesa-utils); skipping"
    c_dim "  to install: sudo pacman -S mesa-utils"
fi

hd "EGL"
if command -v eglinfo >/dev/null 2>&1; then
    eglinfo 2>/dev/null | grep -iE 'EGL API|EGL vendor|EGL version|Wayland|GBM' | head -20
else
    c_dim "  eglinfo not installed (egl-utils); skipping"
fi

hd "vmwgfx specific"
if [[ "$v" == "vmware" ]]; then
    if dmesg 2>/dev/null | grep -i vmwgfx | tail -10; then
        :
    elif journalctl -b -k 2>/dev/null | grep -i vmwgfx | tail -10; then
        :
    fi
fi

hd "Niri config syntax"
if command -v niri >/dev/null 2>&1; then
    if niri validate 2>&1 | tail -3; then
        ok "niri config parses"
    else
        fail "niri validate had something to say (see above)"
    fi
else
    fail "niri binary not found — module 03 probably never finished"
fi

echo
c_dim "If you see 'llvmpipe' or 'no allocator' anywhere above, Niri will not work"
c_dim "in this environment. Switch hypervisor or install on bare metal."
