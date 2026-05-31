# Arch Linux Rice — Build Spec for Claude Code

> **Read this end-to-end before touching anything.** This is a single-shot
> install spec for a daily-driver Arch setup. The user is reinstalling
> their whole system based on this — **it has to work first try, no
> hiccups.** If something is ambiguous, **stop and ask**, do not guess.
> Do not substitute packages or compositors without explicit approval.

The visual reference is `arch rice v5 daily-driver.html` (open it in a
browser to see exactly what hover/animation/translucency behavior is
expected). Match it precisely.

---

## 0. Non-negotiables

- **No Hyprland.** Compositor is **Niri** (scrollable-tiling Wayland).
- **Dark mode only.** No light theme code paths.
- **Every interactive surface must animate** (hover, click, expand,
  open/close, focus change). Default duration 180–320ms, ease
  `cubic-bezier(.2,.85,.25,1)`. No instant state changes.
- **Translucent surfaces** on every system piece: bar, sidebar, lock
  screen, terminal, notifications, launcher, quick settings,
  power flyout. Background alpha ~0.32, blur 28–32px, saturation 1.4.
- **Minimum packages.** If a feature can be done by an existing
  service, don't add another. List below is curated — don't expand it
  without asking.
- **No filler.** No placeholder widgets, no "TODO" panels shipped to
  the user. Either implement or leave out.
- **12-hour clocks everywhere.** All clock surfaces (sidebar, top bar
  dashboard, lock screen, OSD) render time as `h:MM` with an `AM`/`PM`
  suffix. Never `HH:MM` 24-hour.

---

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Compositor | **Niri** | Scrollable tiling, built-in animations, blur, no Hyprland |
| Shell / bar / widgets / launcher / power flyout | **Quickshell** | QML, full custom UI (Caelestia uses this) |
| Lock screen | **gtklock** | Approved fallback — Quickshell's WlSessionLock proved unstable |
| Notifications | **mako** | DBus daemon; Quickshell custom widget not yet built |
| Wallpaper | **swaybg** (or **swww** if present) | swaybg is the default; wallpaper-init.sh prefers swww when installed |
| Audio | **PipeWire + WirePlumber** | Standard |
| Network | **NetworkManager** | Standard, queried by Quickshell |
| Bluetooth | **BlueZ + bluetuith** (CLI) | Quickshell shows status via DBus |
| Idle / autolock | _none_ | Lock is manual-only (`Mod+L`); system never auto-sleeps |
| Terminal | **alacritty** | GPU-accelerated, Wayland-native |
| Screenshot | **niri built-in** (`screenshot` action) | Interactive region/window/output picker, saves to `~/Pictures/Screenshots/` |
| Clipboard history | **wl-clipboard + cliphist** | |
| Login manager | **ly** | TUI greeter on tty1, no GUI dep |
| File manager | **nautilus** | Familiar (ChromeOS/macOS-ish) |
| Fonts | **Inter + JetBrains Mono Nerd Font** | |
| Icons | **Papirus-Dark** (system) | |

> Quickshell owns launcher, power flyout, both bars, and (eventually)
> notifications. The only approved fallback is **gtklock** for the
> lock surface. Do not pull in waybar, eww, ags, dunst, hyprlock,
> swaylock, rofi, wofi, fuzzel, wlogout, swayidle.

---

## 2. Packages

Authoritative lists live in `modules/01-base-packages.sh` and
`modules/03-aur-packages.sh`; the summary below is for orientation.

### pacman
```
niri alacritty quickshell gtklock mako swaybg cava
pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol
networkmanager bluez bluez-utils blueman
xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
xdg-user-dirs polkit-gnome wl-clipboard cliphist
nautilus chromium discord
ly seatd
ttf-jetbrains-mono-nerd ttf-firacode-nerd noto-fonts noto-fonts-emoji
papirus-icon-theme adw-gtk-theme
qt5-wayland qt6-wayland
brightnessctl playerctl
```

### AUR (yay)
```
niri                     # compositor (also in extra; pin to AUR if preferred)
nwg-displays             # visual display arranger
kanshi                   # auto-applies display profiles
xwayland-satellite       # XWayland for niri
spotify                  # user-requested app
```

Enable `[multilib]` in `/etc/pacman.conf` for steam.

### Services to enable
```bash
systemctl enable --now NetworkManager bluetooth seatd
systemctl enable ly@tty1.service           # greeter on tty1
systemctl --user enable --now pipewire pipewire-pulse wireplumber kanshi
```

---

## 3. File tree (final state of `~/.config`)

```
~/.config/
├── niri/
│   ├── config.kdl                  # see §4
│   └── monitor.kdl                 # written by nwg-displays
├── quickshell/
│   ├── shell.qml                   # entry point
│   ├── Theme.qml                   # tokens (colors, radii, blur, anim)
│   ├── bars/
│   │   ├── TopBar.qml              # hover-reveal, waveform when playing
│   │   ├── SideBar.qml             # workspaces + apps + sysmon + power
│   │   └── Waveform.qml            # cava-driven animated bars
│   ├── overlays/
│   │   ├── Launcher.qml            # Launchpad-style app grid (Mod+Space)
│   │   └── PowerFlyout.qml         # lock/signout/suspend/reboot/poweroff (Mod+Esc)
│   ├── services/                   # MPRIS, audio, network, sys stats
│   └── cava.conf                   # config for the Waveform bars
├── alacritty/alacritty.toml
├── mako/config                     # notification daemon
├── cava/config
├── gtklock/                        # lock screen (Mod+L)
├── kanshi/config                   # display profiles, started via systemd --user
├── gtk-3.0/ gtk-4.0/               # dark theme
├── btop/  fastfetch/               # CLI utilities
```

Lock is **gtklock**, not Quickshell (WlSessionLock was unstable). Login
is **ly** on tty1 (`/etc/ly/config.ini`), not greetd. Launcher and
power flyout are Quickshell overlays — no fuzzel/rofi/wlogout.

Skeletons for `niri/config.kdl`, `alacritty/alacritty.toml`,
`quickshell/Theme.qml`, and `quickshell/shell.qml` are already in this
project — use them as starting points and flesh out the QML widgets to
match the HTML mockup.

---

## 4. Niri behavior (config.kdl highlights)

- **No window decorations.** Border 2px, focused color = accent
  (`#c5b3ff` default — read from `Theme.qml` via env var).
- **Gaps:** outer 12px, inner 8px.
- **Default rule:** `opacity 0.95` on `[term, file-manager,
  Quickshell-floating]` for the translucent-system look. **Do not
  blanket-opacity Chrome, Spotify, Discord, Steam, video apps** — they
  must stay opaque for legibility.
- **Animations:** keep niri's defaults but bump
  `window-open` and `workspace-switch` curves to feel slightly
  springy. Reference: niri's `animations { ... }` block.
- **Keybinds (must match):**

| Bind | Action |
|---|---|
| Super+Return | alacritty |
| Super+Space | toggle Quickshell launcher (`qs ipc call launcher toggle`) |
| Super+Escape | toggle power flyout (`qs ipc call power toggle`) |
| Super+L | lock — `gtklock -d -c ~/.config/gtklock/config.ini` |
| Super+W | close window |
| Super+F | maximize column |
| Super+Shift+F | fullscreen window |
| Super+R | reset window height |
| Super+Shift+B | next wallpaper |
| Super+1..9 | switch to workspace 1..9 |
| Super+Shift+1..3 | move window to workspace 1..3 |
| Super+Arrow | focus column/window |
| Super+Shift+Arrow | move column/window |
| Print | screenshot (niri built-in interactive UI) |
| XF86Audio* | playerctl / wpctl |
| XF86MonBrightness* | brightnessctl |

- **Autostart** (`spawn-at-startup`): `wallpaper-init` (swaybg or swww),
  `quickshell`, `mako`, `wl-paste --watch cliphist store` (text+image),
  `polkit-gnome-authentication-agent-1`, `xwayland-satellite`.
  No idle daemon — lock and suspend are user-initiated only.
- **Wallpaper:** seeded by `wallpaper-init`; cycle with `wallpaper-next`
  (bound to Super+Shift+B).

---

## 5. Quickshell behavior (must-haves)

This is the heaviest piece — keep it modular and **read the
Quickshell docs first** (`quickshell.outfoxxed.me`). Key APIs:
`PanelWindow`, `MprisPlayer`, `Process`, `FileView`, `DBusConnection`.

### 5.1 TopBar (`bars/TopBar.qml`)

- A `PanelWindow` anchored to the **top edge**, behind the cursor.
- **Default state:** `implicitHeight: 6` (thin strip). Visible **only
  if** `Mpris.activePlayer.playbackStatus === Playing` — otherwise
  fully hidden (`visible: false`).
- **When music plays:** render a 12-bar waveform centered, animated
  from MPRIS metadata (use a simple animated bar set — the real
  waveform from PipeWire is overkill and we want low CPU).
- **On hover:** animate `implicitHeight` 6 → 84px, `radius` 999 → 18,
  reveal 5 cells: Time / Calendar / Media / Weather / Notifications.
  Animations: 380ms with `easeOutCubic`. Cursor leaving collapses
  back.
- **Hover hit region** must extend a bit above the visible bar (an
  invisible 18px-tall hit area at `y=0`) so it triggers as soon as the
  cursor reaches the edge — matches the HTML mockup.
- **Weather** via `Process { command: ["curl","-s","wttr.in/?format=j1"] }`,
  refresh every 900s, parse JSON, render icon by `weatherCode`.
- **Notifications** count = unread count from `Notifications.qml`
  service.
- Width: stretches `left = SideBar.right + 12` to `right - 12`.

### 5.2 SideBar (`bars/SideBar.qml`)

- `PanelWindow` anchored **left**, 72px wide, full height with 12px
  gap on top/left/bottom.
- Top-to-bottom layout matches mockup:
  1. **Launcher** (logo)
  2. **Focused window** card (24×24 icon + 9px name, ellipsized)
  3. **Workspaces 1–9** (vertical dots; active = vertical pill in
     accent; occupied = solid dim dot)
  4. *spacer*
  5. **SystemMonitor** mini (CPU/MEM/GPU bars, polled every 1.5s).
     **On hover, popover** opens to the right with detailed view
     (clock speed, temps, VRAM, core counts). Use slide+fade
     animation (240ms).
  6. **Clock** (HH:MM + day abbreviation)
  7. **QuickSettings** button (single ⚙ that opens a popover with
     Wi-Fi / BT / volume / brightness / DND / dark — all toggleable)
  8. **AppDock** — chrome, spotify, terminal (alacritty), discord,
     whatsapp, steam. Read from `dock.json` so user can edit. Each
     icon: 44×44 round-rect, hover scales 1.08, click scales 0.94,
     running-dot indicator below. Last item is a dashed `+` button
     that opens a small editor dialog (add/remove/reorder
     `dock.json`).
  9. **Power** button → flyout (lock / sign out / suspend / reboot /
     power off). Use `systemctl suspend|reboot|poweroff` — these route
     through logind + polkit, so the active-session user runs them
     without a password. (`loginctl` has NO power verbs — only session/
     seat management — so don't use it for poweroff/reboot/suspend.)

- **Battery widget is hardware-gated: laptop shows it, desktop hides it.**
  The sidebar battery pill (between the volume and power buttons) is driven by
  the `Services.Battery` singleton, which polls `/sys/class/power_supply/BAT*`
  and exposes `present`. The pill is `visible: Services.Battery.present`, so it
  appears automatically on a laptop install and stays hidden on the desktop —
  one set of dotfiles, no profile flag. **Do not hardcode it on or off**; the
  `present` gate is the single source of truth. The desktop must never render a
  battery indicator.

### 5.3 LockScreen (`overlays/LockScreen.qml`)

- Full-screen `PanelWindow` with `WlrLayershell.layer: Overlay` and
  `exclusiveZone: -1`. Background: `rgba(0,0,0,0.20)` over the
  desktop with backdrop blur 28px.
- **Time** dead-center: 200px JetBrains Mono Light, tabular-nums,
  letter-spacing -0.06em. Date 22px below.
- **Password field**: pill input, blurred, accent submit button.
- **Bottom widgets** (grid 2 col, max-width 720): Weather, Now
  Playing. Subtle, no chrome dominance.
- Lock is **manual only** (`Mod+L`). No idle-based auto-lock and no
  auto display-off; the system stays awake until the user suspends or
  powers it down via the Quickshell power flyout.

### 5.4 Notifications (`widgets/Notifications.qml`)

- DBus name `org.freedesktop.Notifications`.
- Popups slide in from top-right (under top bar area when
  collapsed), auto-dismiss 6s, hoverable, action buttons supported.
- Persistent stack visible in the TopBar's expanded notifications
  cell (last 5).
- Sound: optional, default off.

### 5.5 Theme tokens (`Theme.qml`)

Single source of truth — every other QML imports this.

```qml
QtObject {
    readonly property color accent: "#c5b3ff"
    readonly property color fg0: "#f4f4f6"
    readonly property color fg1: "#c9c9d0"
    readonly property color fg2: "#8e8e96"
    readonly property real  alpha: 0.32
    readonly property color surface: Qt.rgba(0.086, 0.086, 0.11, alpha)
    readonly property color surface2: Qt.rgba(0.11, 0.11, 0.13, alpha + 0.18)
    readonly property int   radius: 18
    readonly property int   radiusSmall: 12
    readonly property int   blur: 32
    readonly property int   animFast: 180
    readonly property int   animMed: 240
    readonly property int   animSlow: 380
    readonly property var   easeOut: [0.2, 0.85, 0.25, 1.0]
}
```

---

## 6. Lock / idle behavior

**Idle daemon disabled by design.** The system never auto-locks and
never auto-blanks. The only paths to a locked or sleeping machine are
user-initiated:

- `Mod+L` → `gtklock -d -c ~/.config/gtklock/config.ini`
- Quickshell power flyout → suspend / reboot / power off via `systemctl`
  (logind + polkit; no password needed for the active-session user)

Do **not** re-add `swayidle` to `spawn-at-startup`. If lock-on-suspend
is wanted later, wire it explicitly and ask the user first.

---

## 7. Login manager (ly)

`ly` runs as `ly@tty1.service`. It reads installed Wayland sessions
from `/usr/share/wayland-sessions/` — niri's session file is written
by `modules/04-niri-stack.sh`.

Niri ships a `niri-session` script; if missing, write a 3-liner that
exports `XDG_CURRENT_DESKTOP=niri` and `exec niri`. Do not pull in
greetd/tuigreet/regreet — that stack was removed.

---

## 8. App-specific notes

- **Chrome:** launch with `google-chrome-stable --ozone-platform-hint=auto
  --enable-features=WaylandWindowDecorations`. Add a desktop file
  override if needed for proper icon.
- **Spotify:** runs under XWayland by default — fine. If you want
  Wayland-native, install `spotify-launcher` instead.
- **Discord:** XWayland.
- **Steam:** XWayland. Add `STEAM_FORCE_DESKTOPUI_SCALING=1.25` if
  user is on hi-dpi.
- **WhatsApp:** `whatsapp-for-linux` is electron-XWayland. If buggy
  on Niri, fall back to `zapzap-git`. Confirm with user.

---

## 9. Testing checklist (run before declaring done)

Each line must pass. If any fails, **stop and report exact error**;
do not paper over.

- [ ] `niri --validate ~/.config/niri/config.kdl` succeeds.
- [ ] `quickshell -c ~/.config/quickshell/shell.qml` starts with no
      QML errors in stderr.
- [ ] Boot → ly greeter on tty1 → log in → niri session lands with
      wallpaper visible.
- [ ] Sidebar visible, workspaces respond to `Super+1..9`.
- [ ] Hover top edge → bar drops down with 5 cells populated (time
      ticks live, weather fetched, media reflects spotify state).
- [ ] Start music → bar shows waveform when not hovered, hides when
      music stops and not hovered.
- [ ] App dock launches each app; running indicator appears.
- [ ] Hover system monitor → detail popover opens, numbers update.
- [ ] `Super+Escape` opens power flyout; Lock / Sign out / Suspend /
      Reboot / Power off all fire (test reboot LAST).
- [ ] `Super+L` → lock screen appears, time correct, password unlocks.
- [ ] System never auto-locks and never auto-blanks; only `Mod+L` and
      the power flyout change state.
- [ ] `Print` opens niri's built-in screenshot UI; output saved to `~/Pictures/Screenshots/`.
- [ ] Notifications: `notify-send "test"` shows popup top-right,
      auto-dismisses, appears in top bar history.
- [ ] Battery widget: **visible on laptop** (BAT* present, shows level +
      percent), **hidden on desktop** (no BAT* node).
- [ ] Terminal (alacritty) is translucent; Chrome / Spotify / Steam are
      opaque.
- [ ] All hover/click states animate (no instant snap anywhere).

---

## 10. Install order (run as plain user with sudo, not as root)

1. Confirm `pacman -Syu` is clean.
2. Enable multilib, install pacman package list.
3. Install paru (or yay), then AUR list.
4. Enable services (see §2).
5. Drop config files in place (this project's stubs).
6. `mkdir -p ~/.config/wallpapers` and copy at least one image to
   `current.jpg`.
7. `chsh -s /bin/bash` (or zsh — ask user).
8. Reboot, log in via ly → Niri.
9. Run testing checklist §9. If anything fails, **report it** — do
   not iterate silently.

---

## 11. Hard rules for Claude Code

- **Don't deviate** from the stack without surfacing the question.
- **Don't add cute extras** (cava bars in the panel, weather radar,
  blur shaders) until everything in §9 passes.
- **Don't run `pacman -R`** on anything not installed by this spec.
- **Don't overwrite** `/etc/*` files without showing the diff first.
- **Secure Boot depends on the target type — never use the wrong one:**
  - **Bare-metal installs** (`TARGET_TYPE=ssd`): the `sbctl` path is OK —
    it enrolls our own keys into the firmware's `db` (Limine + `sbctl
    enroll-keys --microsoft`). This requires firmware **Setup Mode** and
    rewrites **PCR 7**.
  - **USB / removable installs** (`TARGET_TYPE=usb`): **MUST use the shim +
    MOK chain. Never run `sbctl enroll-keys` on a USB target.** A portable
    stick gets plugged into machines we don't own; enrolling keys into `db`
    (or clearing PK for Setup Mode) changes PCR 7 and **triggers BitLocker
    recovery** on any dual-boot/Windows host. shim (Microsoft-signed) +
    a MOK enrolled once via MokManager keeps Secure Boot **enabled** and
    leaves `db`/PK/KEK **untouched**, so BitLocker is never disturbed.
  - Rule of thumb: `TARGET_TYPE=usb` ⇒ shim+MOK; `TARGET_TYPE=ssd` ⇒ sbctl.
- **When in doubt → stop and ask.**

---

## 12. Visual profiles — `full` / `light`

The rice runs in one of two visual profiles, switchable **live, no logout**.
`full` is the default daily-driver look. `light` is for the **2014 MacBook Air
(4GB, Intel HD 5000)** — purely cosmetic/perf, **no widget is removed**.

- **Single source of truth:** the one-word file `~/.config/rice/profile`
  (`full` | `light`).
- **One command:** `rice-profile [status|full|light|toggle]`. **`Mod+Shift+P`**
  is bound to `rice-profile toggle`. (`scripts/rice-profile.sh` →
  `/usr/local/bin/rice-profile`.)
- **Boot seed:** `rice-profile-seed` runs at niri startup (first
  `spawn-at-startup`, before quickshell). It reads `rice.profile=` from the
  kernel cmdline — so the USB's GRUB entries (`…full` / `…light`, written by
  `modules/10-bootloader-shim-mok.sh`) pick the profile automatically. With no
  cmdline directive it respects the saved choice, else defaults to `full`.

**What `light` changes (and nothing else):**

| Piece | full | light |
|---|---|---|
| niri window translucency (alacritty/dialogs) | opacity 0.92–0.95 | **opaque** |
| niri shadows | soft drop shadows | **off** |
| niri animations | springs (continuous sim) | **short fixed-duration curves** |
| TopBar cava waveform | on while media plays | **skipped** (no cava subproc / 30fps loop) |
| SystemMonitor poll | 1.5s | **5s** (popover still kept) |
| Quickshell sidebar surface | translucent (α 0.78) | **opaque** |

Everything else — launcher, flyouts, sysmon detail popover, clocks, workspaces
— is identical. Windows still animate in light (spec wants motion everywhere);
they just don't run a sustained spring simulation.

**Mechanics — niri config is GENERATED, not symlinked.** niri's `layout {}` and
`animations {}` are **single nodes**; having them twice (or via `include`) is a
hard parse error (`duplicate node 'layout'`). So:

```
dotfiles/niri/config.base.kdl    # shared: inputs, outputs, binds, autostart, env
dotfiles/niri/config.full.kdl    # full:  layout{+shadow} + animations + opacity rules
dotfiles/niri/config.light.kdl   # light: layout{shadow off} + cheap anims + opaque
```

`rice-profile` concatenates `config.base.kdl` + `config.<profile>.kdl` →
`~/.config/niri/config.kdl`, **validates with `niri validate` before swapping it
in** (a broken fragment can never strand the session), then pokes
`niri msg action load-config-file`. The Quickshell half reacts off the
`Services.Profile` singleton (`services/Profile.qml`), which watches
`~/.config/rice/profile` and re-flows the bars with no restart.

> When editing niri config, **edit the fragments**, never the generated
> `config.kdl`. After editing, run `rice-profile <profile>` to regenerate.
> Keep shared `layout` fields (gaps/widths/struts/border) in sync across both
> fragments — niri can't merge a partial `layout` block.

The visual is in `arch rice v5 daily-driver.html`. The user has tuned
it. Match its hover/animation/translucency behavior beat-for-beat in
QML. Every transition, every hover state, every flyout — animated.
