# arch-setup — Niri Wayland desktop (driftos)

Idempotent installer + dotfiles for a borderless, translucent, dark-mode Niri
desktop. Caelestia/macOS/Material-You aesthetic. No Hyprland.

This repo does two things in one tree:

1. **Bare-metal install from the Arch ISO** — partitions a disk, pacstraps a
   minimal base, configures it inside `arch-chroot`, and installs the
   bootloader (GRUB or Limine + sbctl Secure Boot).
2. **Rice install in the booted user session** — adds Niri, waybar bars,
   swaylock, dotfiles, wallpapers, and AUR packages.

`install.sh` auto-detects which mode to run: if it's invoked from inside the
Arch ISO live env it forwards to `bootstrap.sh`; otherwise it runs the rice.

---

## Quick start (clone-and-run from the Arch ISO)

Boot the official Arch ISO in **UEFI mode**. At the live prompt (you'll be
`root`):

```bash
# (Wi-Fi only) bring up the network first
iwctl

# get the repo
pacman -Sy --noconfirm git
git clone https://github.com/tech-support03/driftos.git ~/arch-setup
cd ~/arch-setup

# bare-metal install (interactive — will prompt for disk/user/passwords)
./install.sh

# or fully unattended bare-metal install with Secure Boot:
./install.sh --disk /dev/nvme0n1 --user arjun --hostname driftos \
             --timezone America/New_York --profile personal --secure-boot --yes
```

After reboot, log in as your user on tty and run the rice layer:

```bash
cd ~/arch-setup
./install.sh --profile personal      # same script — detects it's NOT in the ISO now
```

---

## Layout

```
~/arch-setup/
├── install.sh                     # entry point — routes to bootstrap or rice
├── bootstrap.sh                   # ISO-side bare-metal installer
│
├── iso-stage/                     # bare-metal install pipeline (runs from ISO)
│   ├── 01-preflight.sh            #   UEFI/network/keyring/Setup-Mode checks
│   ├── 02-disk.sh                 #   GPT partition + format + mount /mnt
│   ├── 03-pacstrap.sh             #   base + kernel + bootloader pkgs
│   ├── 04-chroot-config.sh        #   inside chroot: locale, user, NM, mkinitcpio
│   └── 05-bootloader-chroot.sh    #   inside chroot: dispatch to grub/limine
│
├── modules/                       # rice-side modules (runs from user session)
│   ├── 00-display-config.sh       #   profile-aware kanshi
│   ├── 01-base-packages.sh        #   pacman repo packages
│   ├── 02-yay-bootstrap.sh        #   AUR helper
│   ├── 03-aur-packages.sh         #   niri, waybar, swaylock-effects, swww...
│   ├── 04-niri-stack.sh           #   xdg-portal + niri session entry
│   ├── 05-bootloader-grub.sh      #   reused by bootstrap (chroot-safe)
│   ├── 06-bootloader-limine.sh    #   reused by bootstrap (chroot-safe)
│   ├── 07-services.sh             #   bt, greetd, pipewire
│   ├── 08-link-dotfiles.sh        #   symlink dotfiles into ~/.config
│   └── 09-wallpapers.sh           #   five sample wallpapers via swww
│
├── dotfiles/                      # mirrors target ~/.config/* layout
├── scripts/                       # → ~/.local/bin/<name> on install
└── wallpapers/                    # local wallpaper cache
```

---

## bootstrap.sh — bare-metal flags

| flag                 | env-var          | meaning                                      |
| -------------------- | ---------------- | -------------------------------------------- |
| `--disk PATH`        | `DISK`           | target block device (will be ERASED)         |
| `--hostname NAME`    | `HOSTNAME`       | hostname                                     |
| `--user NAME`        | `USERNAME`       | primary user (added to `wheel`)              |
| `--timezone TZ`      | `TIMEZONE`       | e.g. `America/New_York`                      |
| `--locale LOCALE`    | `LOCALE`         | default `en_US.UTF-8`                        |
| `--keymap KMAP`      | `KEYMAP`         | default `us`                                 |
| `--profile NAME`     | `PROFILE`        | `vm` or `personal`                           |
| `--secure-boot`      | `SECURE_BOOT`    | Limine + sbctl Secure Boot setup             |
| `--yes`              | `ASSUME_YES`     | skip the "type ERASE to continue" prompt     |
|                      | `USER_PASSWORD`  | non-interactive user password                |
|                      | `ROOT_PASSWORD`  | non-interactive root password                |

Disk layout written by `iso-stage/02-disk.sh`:

| Partition | Size  | Type   | FS    | Mount  |
| --------- | ----- | ------ | ----- | ------ |
| p1 (UEFI) | 1 GiB | EF00   | FAT32 | /boot  |
| p2        | rest  | 8300   | ext4  | /      |
| p1 (BIOS) | 1 MiB | EF02   | —     | —      |

Kernel + initramfs live on the ESP (mounted at `/boot`) because Limine reads
them via `boot():/`.

---

## Secure Boot — what happens, what's required from you

The Limine path is the critical one to get right. Here's exactly what
`iso-stage/05-bootloader-chroot.sh` does, in order:

1. **Install Limine, efibootmgr, sbctl, b3sum** (pacstrapped earlier; this step
   just runs the module).
2. **Copy** `BOOTX64.EFI` into `$ESP/EFI/BOOT/` (the firmware fallback path —
   always boots even if NVRAM is wiped) and into `$ESP/EFI/limine/`.
3. **Register** a "Limine" boot entry via `efibootmgr` (parsed NVMe-aware:
   `/dev/nvme0n1p1` → disk `/dev/nvme0n1`, part `1`). Failure here is a warning,
   not fatal — the fallback path still boots.
4. **Create sbctl keys** (`PK`, `KEK`, `db`) under `/var/lib/sbctl/keys/`. Always
   succeeds; this is local key generation.
5. **Enroll keys** with Microsoft certificates (`--microsoft`, preserves DBX
   revocations and OEM vendor keys). This **only works in firmware Setup Mode**.
   - If Setup Mode is **enabled** → enrolled into firmware NVRAM. Done.
   - If Setup Mode is **disabled** → script emits a warning, installs the
     `sb-finalize` retry helper, and continues. Keys are not enrolled yet, but
     binaries are still signed below.
6. **Sign** every UEFI binary on the ESP: `BOOTX64.EFI` (both paths), all
   `vmlinuz-*`, all `initramfs-*.img`. Uses `sbctl sign -s` so the path is
   persisted in `/var/lib/sbctl/files.db` — future updates re-sign automatically.
7. **Write `${ESP}/limine.conf`** with BLAKE2B (`b3sum`) hashes for every
   kernel/initramfs pair. Limine refuses to boot binaries that don't match.
8. **Install pacman hook** at `/etc/pacman.d/hooks/95-limine-resign.hook` that
   triggers on `linux`/`linux-lts`/`linux-zen`/`linux-hardened`/`limine`/
   `systemd` package updates. It re-signs all assets and regenerates
   `limine.conf` with fresh BLAKE2B hashes.
9. **Install** `/usr/local/bin/sb-finalize` — a hand-runnable retry script for
   the "firmware wasn't in Setup Mode" case.

### What you need to do manually

Secure Boot key enrollment writes to firmware NVRAM and **requires firmware
Setup Mode**. There are two viable orderings:

**Path A — enable Setup Mode BEFORE running `bootstrap.sh` (recommended)**

1. In firmware (BIOS) settings, find "Secure Boot" → either "Reset to Setup
   Mode" or "Erase All Keys".
2. Save & exit. Now `sbctl status` will report `Setup Mode: Enabled`.
3. Boot the Arch ISO and run `./install.sh --secure-boot ...`. Enrollment
   succeeds during the chroot stage.
4. After install, reboot, enter firmware, re-enable Secure Boot, save. Done.

**Path B — let `sb-finalize` retry after first boot**

1. Run `./install.sh --secure-boot ...` from the ISO. Bootstrap completes;
   keys are created and signing is done, but enrollment is deferred.
2. First boot completes (Secure Boot still off in firmware).
3. Log in, then enter firmware setup → put it into Setup Mode → save & exit.
4. Boot back into Arch, run `sudo sb-finalize`. Keys enroll, binaries re-sign,
   `limine.conf` is regenerated.
5. Reboot, enable Secure Boot in firmware.

Both paths land in the same end state. Path A is one fewer reboot.

---

## Toggle effects

| Toggle               | Off (default)                              | On                                              |
| -------------------- | ------------------------------------------ | ----------------------------------------------- |
| `--secure-boot`      | GRUB on EFI (or BIOS) — VM-friendly        | Limine + sbctl + BLAKE2B + pacman re-sign hook  |
| `--profile vm`       | Single virtual 1920×1080 kanshi wildcard   | —                                               |
| `--profile personal` | —                                          | 3-monitor topology in `niri/config.kdl` + kanshi|

`nwg-displays` and `wdisplays` are installed in either case so you can drag
screens around visually after install.

---

## Editing the pinned-app dock

Open `dotfiles/waybar-side/config.jsonc`. The dock is just the `modules-center`
array of `"custom/pin-<name>"` keys. Each key must have a sibling block
declaring its `format` glyph and `on-click` launcher:

```jsonc
"modules-center": [
    "custom/pin-chrome",
    "custom/pin-spotify",
    "custom/pin-firefox",   // add a new pin here…
    "custom/launcher"
],

// …then add the matching block:
"custom/pin-firefox": { "format": "", "tooltip": "Firefox", "on-click": "firefox" }
```

Re-run `launch-bars` (installed to `~/.local/bin/`) after editing to live-reload.

---

## Lock screen, top bar, side bar — behavior summary

- **Lock screen** (`swaylock-effects`, bound to `Mod+L`, fires at 5 min idle
  via `swayidle`): translucent blur of the live session, large centered clock,
  small bottom widgets.
- **Top bar** (`waybar -c ~/.config/waybar-top/...`): completely transparent at
  rest. When media plays, only the centered waveform (cava ASCII → Unicode
  block glyphs → waybar JSON) is visible. Hover anywhere along the top edge
  reveals the full bar via CSS opacity transitions; container `min-width: 0`
  with horizontal padding keeps the waveform from ever being clipped.
- **Side bar** (`waybar -c ~/.config/waybar-side/...`): vertical, left-anchored,
  borderless icons (no background boxes). CPU/GPU/RAM as glyphs only; hover
  shows detailed temps/clocks/fans via tooltip.

---

## Where things live after install

| Item                       | Path                                            |
| -------------------------- | ----------------------------------------------- |
| Niri config                | `~/.config/niri/config.kdl`                     |
| Top + side bar configs     | `~/.config/waybar-top`, `~/.config/waybar-side` |
| Wallpapers                 | `~/Pictures/Wallpapers/`                        |
| Helper scripts             | `~/.local/bin/{waveform,media-status,sysmon-*,power-menu,fastfetch-popup,wallpaper-init,launch-bars}` |
| Limine bootloader          | `${ESP}/EFI/BOOT/BOOTX64.EFI`, `${ESP}/limine.conf` |
| sbctl re-sign hook         | `/etc/pacman.d/hooks/95-limine-resign.hook`     |
| Retry SB enrollment        | `/usr/local/bin/sb-finalize`                    |
| Limine conf regenerator    | `/usr/local/bin/limine-regen-conf`              |

---

## Known constraints

- **VMware Workstation/Player is not a supported target.** The `vmwgfx`
  guest driver exposes a DRM device without a working GBM allocator, so
  Niri (like every other modern Wayland compositor) refuses to start —
  the symptom is `error adding primary node device, display-only devices
  may not work: no allocator available for device` in the journal.
  Enabling "Accelerate 3D Graphics" in VMware settings improves OpenGL
  for X11 but does not fix Wayland. For VM testing, use **KVM/QEMU with
  virtio-gpu** instead (works out of the box) or VirtualBox 7+ with VMSVGA
  + 3D enabled. Bare metal is the intended deployment.
- **Disk encryption (LUKS) is not included** in v1. Adding it later requires
  swapping `iso-stage/02-disk.sh` to set up LUKS2 over the root partition and
  adding `sd-encrypt` to mkinitcpio HOOKS. ESP must stay unencrypted.
- **Connector names** in `dotfiles/niri/config.kdl` (`DP-1`, `DP-2`,
  `HDMI-A-1`) are best-guesses for the personal profile. Run `niri msg outputs`
  on first boot and adjust if your driver reports different names.
- **`bootstrap.sh` must run as root from the ISO**; `install.sh` (rice mode)
  must run as a normal user with sudo.

## Troubleshooting

If Niri shows a black screen or fails to render after login, run from a tty
(Ctrl+Alt+F2):

```bash
gpu-check
```

It walks the virtualization detection → DRM device → kernel driver → OpenGL
renderer → EGL/GBM → niri config-parse pipeline and prints exactly which step
is broken. The most common failure modes (in order) are: VMware host (see
above), missing mesa/mesa-utils, and a kernel driver other than the expected
one for the platform.
