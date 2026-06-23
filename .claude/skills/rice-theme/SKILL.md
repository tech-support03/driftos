---
name: rice-theme
description: Apply a 4-colour palette across the whole Arch rice (Quickshell bars/widgets/overlays, btop, hyprlock, fastfetch, zsh prompt). TRIGGER when the user gives a palette / colours, or asks to theme, re-theme, recolour, or restyle the system, or to save/switch/list themes.
---

# Rice theming

The rice is themed by **four colours**. Every other shade (bright/dim/muted
accents, the album-art tint, btop gradients, the prompt tail) is **derived** —
you only ever choose four. The engine is `rice-theme` (a CLI on PATH;
`scripts/rice-theme.sh` → `/usr/local/bin/rice-theme`).

## The 4-colour model

| Slot | Role | Drives |
|---|---|---|
| `c1` | **accent / hero** | borders, focus, active workspace, logo, prompt block, btop CPU, launcher selection, hyprlock input accent — everything "primary" |
| `c2` | **blue** | network / sound / bluetooth widgets, btop MEM, media-title (a brighter shade) |
| `c3` | **cyan** | GPU, weather, btop "available"/temp peak, prompt tail |
| `c4` | **teal** | disk, btop NET/free, prompt tail end |

Derived automatically (do **not** ask the user for these): `accentBright`
(lighter c1 — big clock, gradient peaks), `accentDim` (darker c1 — gradient
starts, prompt block 2), `accentMuted`, `surfaceTint` (very dark c1 — art
placeholder), `blueBright`.

## How to apply a palette the user gives you

1. Map their colours to c1..c4 by role. If they give an unordered set, pick the
   most "hero"/saturated as c1; ask only if genuinely ambiguous. Always show
   pros/cons + a recommendation when asking the user to choose (project rule).
2. **Apply live, do NOT save yet** (palettes are ephemeral until the user says
   "save" — that's an explicit rule):
   ```
   rice-theme apply-colors <c1> <c2> <c3> <c4>
   ```
   This writes `~/.config/rice/colors` (Quickshell re-themes **live** via
   `Theme.qml`'s FileView) and regenerates btop/hyprlock/fastfetch + the zsh
   prompt colours. No restart.
3. Only when the user says to keep it: `rice-theme save <name>` (snapshots the
   live palette into `~/.config/rice/themes/<name>.theme`). Equivalent:
   `rice-theme create <name> c1 c2 c3 c4`.

## Switching / listing (the user can also do this themselves)

- `rice-theme list` — saved themes (● = active)
- `rice-theme set <name>` — apply a saved theme
- `rice-theme next` — cycle (also bound to **Mod+Shift+T**)
- **Mod+T** — Quickshell picker overlay (swatch menu)
- `rice-theme status` — active theme name

Theme **#1 is `indigo`** — the palette the rice shipped with
(`#5b6ee0 #60a5fa #22d3ee #2dd4bf`).

## How it reaches each surface (so you know what to check)

- **Quickshell** (bars, sidebar, top bar, sysmon + flyout, calendar, weather,
  media, launcher, power flyout, volume OSD, network/bluetooth flyouts): all
  bind to `Theme.<token>` in `dotfiles/quickshell/Theme.qml`, which reads the
  4 colours live from `~/.config/rice/colors`. **Never hardcode a hex in QML** —
  add/relabel a token in `Theme.qml` instead, or the surface won't follow themes.
- **btop / hyprlock / fastfetch / zsh**: can't watch a file, so `rice-theme`
  GENERATES them from `dotfiles/rice/templates/*` (and inline for btop) into
  `~/.config` on every switch. btop/hyprlock/fastfetch reload on next launch;
  the zsh prompt sources `~/.config/rice/colors.sh` (new terminals pick it up).

## Not themed on purpose

App-brand dock tints (spotify green, discord blurple, steam blue, whatsapp
green), semantic colours (battery red `#f43f5e`, danger), and alacritty's
16-colour ANSI palette (functional terminal colours). Leave these alone unless
the user explicitly asks.

## Adding a NEW themed surface later

1. If it's QML: reference a `Theme.<token>`; if no token fits, add one to
   `theme/Theme.qml` (derive it from c1..c4 with `Qt.lighter/darker`). **Any
   file in `bars/` or `overlays/` must `import "../theme"`** — the `Theme`
   singleton lives in the `theme/` module and is NOT visible to submodule QML
   without that import (root-level singletons only reach root files).
2. If it's a generated config: add an `@TOKEN@` to its template in
   `dotfiles/rice/templates/` and emit the value in `scripts/rice-theme.sh`'s
   Python block.
3. Update `docs/THEMING.md`'s colour map.
