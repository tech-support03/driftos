# Theming

The rice is themed by **four colours**. Pick them; everything else (shades,
gradients, the prompt tail) is derived. Quickshell re-themes **live**; the other
surfaces regenerate and reload on next launch.

```
c1 = accent / hero      c2 = blue      c3 = cyan      c4 = teal
```

## Quick start

```sh
rice-theme list                 # saved themes (● = active)
rice-theme set indigo           # apply a saved theme
rice-theme apply-colors '#5b6ee0' '#60a5fa' '#22d3ee' '#2dd4bf'   # apply live, unsaved
rice-theme save mytheme         # keep the current live palette as a named theme
rice-theme next                 # cycle to the next theme
rice-theme status               # active theme name
```

| Key | Action |
|---|---|
| **Mod+T** | open the Quickshell theme picker (swatch menu) |
| **Mod+Shift+T** | cycle to the next saved theme (+ notification) |

Themes live in `~/.config/rice/themes/*.theme` (4 colours each). **Theme #1 is
`indigo`** — the palette the rice shipped with. New palettes are **live-only
until you `save` them** (or click-create in the picker).

## How it works

`rice-theme` is the single entry point (`scripts/rice-theme.sh`). On a switch it:

1. Writes the 4 colours to **`~/.config/rice/colors`**. Quickshell's
   `Theme.qml` watches this file (a `FileView`, same pattern as the `Profile`
   singleton) and re-derives every token **live — no restart**.
2. Derives all shades and **generates** the configs that can't watch a file:
   - `~/.config/btop/themes/driftos.theme` (emitted by the script)
   - `~/.config/hypr/hyprlock.conf` (from `dotfiles/rice/templates/hyprlock.conf.tmpl`)
   - `~/.config/fastfetch/config.jsonc` (from `…/fastfetch-config.jsonc.tmpl`)
   - `~/.config/rice/colors.sh` — shell vars the **zsh prompt** sources
3. Sends a `notify-send` toast (on cycle).

btop/hyprlock/fastfetch pick up the change on next launch; the zsh prompt on the
next new terminal.

### Derived tokens

From `c1` (accent): `accentBright` (lighter — big clock, gradient peaks),
`accentDim` (darker — borders, gradient starts), `accentMuted`, `surfaceTint`
(very dark — album-art placeholder). From `c2`: `blueBright`. `c3`/`c4` are used
directly. Derivation lives in two mirrored places: `Theme.qml` (QML
`Qt.lighter/darker`) for Quickshell, and the Python block in `rice-theme.sh`
for everything else.

## Colour map — what each slot drives

| Surface | c1 accent | c2 blue | c3 cyan | c4 teal |
|---|---|---|---|---|
| niri | (borders are off — untouched) | | | |
| Quickshell sidebar | logo, focused-window pill, alacritty dock tint | network · bluetooth · sound widgets | — | — |
| Quickshell top bar | clock (bright), media waveform, art tint/note | media title (bright) | weather | — |
| Quickshell sysmon (+ flyout) | CPU | MEM | GPU | Disk |
| Quickshell calendar | "today", ‹ › arrows | — | — | — |
| Quickshell launcher / power flyout | selection border / icons | — | — | — |
| btop | CPU, temp, download, hi/selected/boxes | MEM box, "used" ramp, cached | "available", temp peak | NET box, free, upload |
| hyprlock | input field accent (`check_color`) | — | — | — |
| fastfetch | title + Arch logo | — | keys | — |
| zsh prompt | user\|host block + dim 2nd block | tail | tail | tail end |

**Not themed (intentionally):** app-brand dock tints (spotify/discord/steam/
whatsapp), battery/danger red `#f43f5e`, and alacritty's 16-colour ANSI palette.

## What changed (June 2026)

This theming system replaced a scheme where **every colour was hardcoded** and
the `Theme.qml` singleton was unused. The work, in order:

1. **zsh autocomplete shell** — zsh + `zsh-autosuggestions` /
   `-syntax-highlighting` / `-completions`, a Powerline prompt, ported bash bits
   (`PATH`, fastfetch greeting, `new` alias). See `dotfiles/zsh/.zshrc`,
   `01-base-packages.sh`, `install.sh` (`chsh`).
2. **Indigo recolour** — retired the lavender accent `#c5b3ff` for indigo
   `#5b6ee0` + blue/cyan/teal across the whole rice.
3. **Theme engine** — `Theme.qml` now reads the 4 colours live and derives the
   rest; **all** hardcoded accent hexes in the Quickshell QML were refactored to
   `Theme.<token>`; `rice-theme` + templates + the `Mod+T` picker + `Mod+Shift+T`
   cycle were added.

> **Editing rule:** never hardcode a themed colour. In QML use a `Theme` token;
> in a generated config use an `@TOKEN@` in its template + emit it in
> `rice-theme.sh`. App-brand and semantic colours are the only literal hexes.
> Full procedure for applying/adding themes: `.claude/skills/rice-theme/SKILL.md`.
