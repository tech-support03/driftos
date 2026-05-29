# Install flags reference

driftos has two installer modes, dispatched by a single entry point
(`install.sh`). Which mode runs is detected automatically:

- **Bootstrap mode** — `install.sh` is run from inside the Arch ISO live
  environment. It forwards every flag to `bootstrap.sh`, which partitions a
  disk, pacstraps a base, configures the chroot, and installs a bootloader.
- **Rice mode** — `install.sh` is run from a normal user session on an
  already-installed Arch system. It layers on Niri, Quickshell, dotfiles,
  AUR packages, and services.

You almost never call `bootstrap.sh` directly — let `install.sh` route.

---

## Profiles

The `--profile` flag is the single most important knob: it picks the target
hardware shape and trickles down to display layout, package selection, and
which systemd services get enabled.

| Profile    | Use when                                  | What changes                                                                                          |
| ---------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `vm`       | KVM/QEMU, VirtualBox, headless test rigs  | Single 1920×1080 wildcard via kanshi; no microcode; guest agents auto-detected (`open-vm-tools`, `qemu-guest-agent`, `spice-vdagent`, `virtualbox-guest-utils`) |
| `personal` | Desktop tower with 2–3 external monitors  | 3-monitor topology hardcoded in `niri/config.kdl` + `kanshi/config.personal`; CPU microcode (`intel-ucode amd-ucode`) installed |
| `laptop`   | Any laptop, single internal panel + dock  | `output * mode preferred enable` wildcard in kanshi (auto-fits any internal panel); CPU microcode; **TLP** (power-mgmt), **acpid**, **bluetooth**, brightness keys, lid-switch=suspend |

> **Connector names are best-guesses.** The personal profile assumes
> `DP-1` / `DP-3` / `HDMI-A-1`; the laptop docked profiles assume `eDP-1` +
> `HDMI-A-1`. Run `niri msg outputs` on first boot and adjust
> `dotfiles/niri/config.kdl` + the matching `dotfiles/kanshi/config.*` if
> your driver reports different names. (For ad-hoc rearrangement, just run
> `nwg-displays` — it writes `~/.config/niri/monitor.kdl`.)

---

## Bootstrap mode flags (`./install.sh` from the Arch ISO)

| Flag                            | Env var                  | Default            | Meaning                                                                                  |
| ------------------------------- | ------------------------ | ------------------ | ---------------------------------------------------------------------------------------- |
| `--disk PATH`                   | `DISK`                   | (prompted)         | Target block device. **Will be erased.**                                                 |
| `--hostname NAME`               | `TARGET_HOSTNAME`        | (prompted)         | System hostname.                                                                         |
| `--user NAME`                   | `TARGET_USERNAME`        | (prompted)         | Primary user, added to `wheel`.                                                          |
| `--timezone TZ`                 | `TIMEZONE`               | `America/New_York` | IANA timezone string (e.g. `Europe/Berlin`).                                             |
| `--locale LOCALE`               | `LOCALE`                 | `en_US.UTF-8`      | System locale.                                                                           |
| `--keymap KMAP`                 | `KEYMAP`                 | `us`               | Console keymap.                                                                          |
| `--profile NAME`                | `PROFILE`                | `vm`               | `vm` \| `personal` \| `laptop` (see profile table above).                                |
| `--target TYPE`                 | `TARGET_TYPE`            | `auto`             | `ssd` \| `usb` \| `auto`. Controls ESP size, mount opts, and GRUB install style.         |
| `--secure-boot`                 | `SECURE_BOOT`            | off                | Switches bootloader from GRUB → Limine + sbctl; installs the atomic re-sign pacman hook. |
| `--no-secure-boot`              | `SECURE_BOOT`            | —                  | Force-off override (in case env var is set).                                             |
| `--force-usb-secure-boot`       | `FORCE_USB_SECURE_BOOT`  | off                | Allow `--secure-boot` together with `--target usb`. Almost always wrong — sbctl enrolls keys into firmware NVRAM, which defeats the point of a portable USB install. |
| `--i-know-this-is-windows`      | `FORCE_OVERWRITE_WINDOWS`| off                | Dual-boot guard override. By default the installer refuses to wipe a disk that looks like Windows. |
| `--yes`, `-y`                   | `ASSUME_YES`             | off                | Skip the `type ERASE to continue` prompt. Combine with all other flags for fully unattended installs. |
| —                               | `USER_PASSWORD`          | (prompted)         | Non-interactive user password.                                                           |
| —                               | `ROOT_PASSWORD`          | (prompted)         | Non-interactive root password.                                                           |
| `-h`, `--help`                  | —                        | —                  | Print this reference summary.                                                            |

### Target-type details

| Target | ESP size | Root mount opts                  | GRUB install style                                                                            |
| ------ | -------- | -------------------------------- | --------------------------------------------------------------------------------------------- |
| `ssd`  | 1 GiB    | `noatime,discard=async`          | NVRAM entry "GRUB"; `fstrim.timer` enabled.                                                   |
| `usb`  | 512 MiB  | `noatime,nodiratime,commit=120`  | `--removable` (portable to any UEFI machine via `\EFI\BOOT\BOOTX64.EFI`).                     |
| `auto` | —        | (picks based on disk introspection) | Reads `/sys/block/.../removable` and `lsblk TRAN`; picks `ssd` or `usb` automatically.     |

---

## Rice mode flags (`./install.sh` on an installed system)

Most rice-mode flags are inherited from the bootstrap defaults (the profile
you chose at bootstrap time). The only useful flags to pass at rice time:

| Flag              | Env var    | Default | Meaning                                                                                  |
| ----------------- | ---------- | ------- | ---------------------------------------------------------------------------------------- |
| `--profile NAME`  | `PROFILE`  | `vm`    | Same values as bootstrap. Picks the kanshi config and microcode behavior.                |
| `--hostname NAME` | —          | —       | Rename the host now (handy if bootstrap saved a bad default).                            |
| `-h`, `--help`    | —          | —       | Print rice-mode usage.                                                                   |

`--secure-boot` / `--no-secure-boot` are accepted but ignored with a notice
— Secure Boot is a bootstrap-time decision (signing keys + pacman hooks
have to be in place at bootloader install).

---

## Recipes

### Laptop install (single internal panel, full power management)

From the Arch ISO:

```bash
./install.sh --disk /dev/nvme0n1 \
             --user you \
             --hostname driftos-laptop \
             --profile laptop \
             --target ssd \
             --secure-boot \
             --yes
```

This pulls in TLP + acpid + bluetooth, wires `HandleLidSwitch=suspend`
into logind, enables `tlp.service` + `acpid.service` in the chroot, and
writes a kanshi config that auto-fits whatever internal panel the laptop
reports (eDP-1 / eDP / LVDS-1).

To add the rice layer to an already-installed laptop:

```bash
cd ~/arch-setup
./install.sh --profile laptop
```

### Desktop install (multi-monitor)

```bash
./install.sh --disk /dev/nvme0n1 \
             --user you \
             --hostname driftos \
             --profile personal \
             --secure-boot \
             --yes
```

Adjust the output blocks in `dotfiles/niri/config.kdl` if your monitors
report different connector names (`niri msg outputs` after first login).

### VM install (KVM/QEMU recommended)

```bash
./install.sh --disk /dev/vda \
             --user you \
             --profile vm \
             --yes
```

Guest agents (`qemu-guest-agent` + `spice-vdagent`) are auto-detected and
installed based on `systemd-detect-virt`.

### USB test install (try the rice on real hardware without touching the SSD)

```bash
./install.sh --disk /dev/sdX \
             --user you \
             --profile laptop \
             --target usb
```

Boots on any UEFI machine via `\EFI\BOOT\BOOTX64.EFI`. Don't add
`--secure-boot` to a USB install — keys would enroll into whatever
laptop's firmware NVRAM you happen to test on. The installer refuses this
combo unless `--force-usb-secure-boot` is also set.

### Fully unattended

Combine flags + environment variables to skip every prompt:

```bash
USER_PASSWORD='hunter2' ROOT_PASSWORD='hunter2' \
./install.sh --disk /dev/nvme0n1 \
             --user you --hostname driftos \
             --profile personal --secure-boot --yes
```

---

## What flags do NOT control

- **Display arrangement after install.** Use `nwg-displays` (drag-and-drop
  GUI) — it writes `~/.config/niri/monitor.kdl` which `config.kdl` includes.
- **Pinned-app dock.** Edit `dotfiles/quickshell/bars/SideBar.qml`
  (`Column { id: dock ... }`) and save — Quickshell auto-reloads.
- **Theme colors / animation timing.** All tokens live in
  `dotfiles/quickshell/Theme.qml`.
- **Wallpapers.** Drop files into `~/Pictures/Wallpapers/` and cycle with
  `Super+Shift+B`.
