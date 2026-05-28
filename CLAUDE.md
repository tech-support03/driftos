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

---

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Compositor | **Niri** | Scrollable tiling, built-in animations, blur, no Hyprland |
| Shell / bar / widgets / lock | **Quickshell** | QML, full custom UI (Caelestia uses this) |
| App launcher | **Fuzzel** | Lightweight, native Wayland, themable |
| Notifications | Quickshell custom (DBus listener) | Avoid swaync dependency |
| Wallpaper | **swww** | Animated, smooth transitions |
| Audio | **PipeWire + WirePlumber** | Standard |
| Network | **NetworkManager** | Standard, queried by Quickshell |
| Bluetooth | **BlueZ + bluetuith** (CLI) | Quickshell shows status via DBus |
| Idle / autolock | **swayidle** | Triggers Quickshell lock |
| Terminal | **alacritty** | GPU-accelerated, Wayland-native |
| Screenshot | **grim + slurp + satty** | Annotate after capture |
| Clipboard history | **wl-clipboard + cliphist** | |
| Login manager | **greetd + tuigreet** | Minimal, no GUI dep |
| File manager | **nautilus** | Familiar (ChromeOS/macOS-ish) |
| Fonts | **Inter + JetBrains Mono Nerd Font** | |
| Icons | **Papirus-Dark** (system) | |

> If Quickshell can't do something cleanly (e.g. its lock surface
> proves unstable), the only approved fallbacks are: **gtklock** for
> lock, **fuzzel** for launcher. Do not pull in waybar, eww, ags,
> dunst, mako, hyprlock, swaylock, rofi, wofi.

---

## 2. Packages

### pacman
```
niri alacritty fuzzel swww pipewire pipewire-pulse pipewire-alsa wireplumber
networkmanager network-manager-applet bluez bluez-utils
xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
xdg-user-dirs polkit-gnome
grim slurp wl-clipboard
nautilus
greetd
inter-font ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
papirus-icon-theme
qt6-base qt6-declarative qt6-wayland qt6-svg qt6-multimedia
brightnessctl playerctl
```

### AUR (paru or yay — pick one, document it)
```
quickshell-git           # the shell itself
swayidle                 # idle daemon (Wayland)
satty                    # screenshot annotator
cliphist                 # clipboard history
tuigreet                 # greeter for greetd
google-chrome            # user-requested app
spotify                  # user-requested app
discord                  # user-requested app
whatsapp-for-linux       # user-requested app (or zapzap if preferred)
# steam goes through multilib pacman, not AUR
```

Enable `[multilib]` in `/etc/pacman.conf` for steam.

### Services to enable
```bash
systemctl enable --now NetworkManager bluetooth greetd
systemctl --user enable --now pipewire pipewire-pulse wireplumber
```

---

## 3. File tree (final state of `~/.config`)

```
~/.config/
├── niri/
│   └── config.kdl                  # see §4
├── quickshell/
│   ├── shell.qml                   # entry point
│   ├── Theme.qml                   # tokens (colors, radii, blur, anim)
│   ├── bars/
│   │   ├── TopBar.qml              # hover-reveal, waveform when playing
│   │   └── SideBar.qml             # workspaces + apps + sysmon + power
│   ├── widgets/
│   │   ├── Clock.qml
│   │   ├── Calendar.qml
│   │   ├── Weather.qml             # wttr.in fetch every 15min
│   │   ├── MediaPlayer.qml         # MPRIS
│   │   ├── Notifications.qml       # DBus listener + popup stack
│   │   ├── SystemMonitor.qml       # /proc/stat, /proc/meminfo, nvidia-smi/radeontop
│   │   ├── AppDock.qml             # configured via dock.json
│   │   ├── QuickSettings.qml       # wifi/bt/vol/bri/dnd/dark
│   │   └── PowerFlyout.qml         # lock/signout/suspend/reboot/poweroff
│   ├── overlays/
│   │   ├── LockScreen.qml          # transparent, time center, widgets bottom
│   │   ├── Launcher.qml            # OR delegate to fuzzel via process
│   │   └── OSD.qml                 # vol/bri overlay
│   ├── services/
│   │   ├── Mpris.qml
│   │   ├── Network.qml
│   │   ├── Audio.qml
│   │   ├── Brightness.qml
│   │   ├── Battery.qml             # NO-OP on desktop; do not render
│   │   └── SysStats.qml
│   └── dock.json                   # editable app list
├── alacritty/
│   └── alacritty.toml
├── fuzzel/
│   └── fuzzel.ini
├── swayidle/
│   └── config
├── greetd/                         # /etc/greetd/config.toml actually
└── gtk-4.0/ gtk-3.0/               # match dark theme
```

Skeletons for `niri/config.kdl`, `alacritty/alacritty.toml`, `fuzzel/fuzzel.ini`,
`swayidle/config`, `quickshell/Theme.qml`, and `quickshell/shell.qml`
are already in this project — use them as starting points and flesh
out the QML widgets to match the HTML mockup.

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
| Super+Space | toggle launcher (`fuzzel` or Quickshell launcher) |
| Super+1..9 | switch to workspace 1..9 |
| Super+Shift+1..9 | move window to workspace |
| Super+Return | alacritty |
| Super+E | nautilus |
| Super+B | chrome |
| Super+Q | close window |
| Super+L | lock (`quickshell lock` or `loginctl lock-session`) |
| Super+Shift+S | screenshot region (`grim+slurp+satty`) |
| Super+V | cliphist picker via fuzzel |
| XF86Audio* | playerctl / wpctl |
| XF86MonBrightness* | brightnessctl |

- **Autostart** (`spawn-at-startup`): `swww-daemon`, `quickshell`,
  `swayidle -c ~/.config/swayidle/config`, `nm-applet --indicator`,
  `polkit-gnome-authentication-agent-1`.
- **Wallpaper:** set via `swww img ~/.config/wallpapers/current.jpg
  --transition-type wipe`.

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
     power off). Power off + reboot must `loginctl` the right verbs;
     do NOT `systemctl poweroff` directly.

- **No battery indicator anywhere.** This is a desktop. Hide the
  battery service entirely (`Battery.qml` exists but `enabled: false`).

### 5.3 LockScreen (`overlays/LockScreen.qml`)

- Full-screen `PanelWindow` with `WlrLayershell.layer: Overlay` and
  `exclusiveZone: -1`. Background: `rgba(0,0,0,0.20)` over the
  desktop with backdrop blur 28px.
- **Time** dead-center: 200px JetBrains Mono Light, tabular-nums,
  letter-spacing -0.06em. Date 22px below.
- **Password field**: pill input, blurred, accent submit button.
- **Bottom widgets** (grid 2 col, max-width 720): Weather, Now
  Playing. Subtle, no chrome dominance.
- Wake via swayidle's `lock` trigger; idle 5min lock, 10min screen
  off.

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

```
# ~/.config/swayidle/config
timeout 300  'loginctl lock-session'
timeout 600  'niri msg action power-off-monitors'
resume       'niri msg action power-on-monitors'
before-sleep 'loginctl lock-session'
lock         'quickshell ipc call lock show'   # or gtklock fallback
```

---

## 7. Greetd / login

`/etc/greetd/config.toml`:

```toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --remember --cmd niri-session"
user = "greeter"
```

Niri ships a `niri-session` script; if missing, write a 3-liner that
exports `XDG_CURRENT_DESKTOP=niri` and `exec niri`.

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
- [ ] Boot → tuigreet → log in → niri session lands with wallpaper
      visible.
- [ ] Sidebar visible, workspaces respond to `Super+1..9`.
- [ ] Hover top edge → bar drops down with 5 cells populated (time
      ticks live, weather fetched, media reflects spotify state).
- [ ] Start music → bar shows waveform when not hovered, hides when
      music stops and not hovered.
- [ ] App dock launches each app; running indicator appears.
- [ ] Hover system monitor → detail popover opens, numbers update.
- [ ] Power flyout: lock works, suspend works, reboot works (test
      reboot LAST), poweroff works.
- [ ] `Super+L` → lock screen appears, time correct, password unlocks.
- [ ] Idle 5min → auto-lock; 10min → screen off; mouse wakes both.
- [ ] Screenshot bind captures region and opens satty.
- [ ] Notifications: `notify-send "test"` shows popup top-right,
      auto-dismisses, appears in top bar history.
- [ ] **No** battery widget visible anywhere.
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
8. Reboot, log in via tuigreet → Niri.
9. Run testing checklist §9. If anything fails, **report it** — do
   not iterate silently.

---

## 11. Hard rules for Claude Code

- **Don't deviate** from the stack without surfacing the question.
- **Don't add cute extras** (cava bars in the panel, weather radar,
  blur shaders) until everything in §9 passes.
- **Don't run `pacman -R`** on anything not installed by this spec.
- **Don't overwrite** `/etc/*` files without showing the diff first.
- **When in doubt → stop and ask.**

The visual is in `arch rice v5 daily-driver.html`. The user has tuned
it. Match its hover/animation/translucency behavior beat-for-beat in
QML. Every transition, every hover state, every flyout — animated.
