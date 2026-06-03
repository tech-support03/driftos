// ~/.config/quickshell/Theme.qml — single source of truth for color.
//
// The palette is FOUR base colors read LIVE from ~/.config/rice/colors (written
// by the `rice-theme` CLI). Every shade the UI needs is DERIVED here, so a
// theme switch re-flows the whole shell with no restart — exactly like the
// Profile singleton watches ~/.config/rice/profile. Consumers must bind to the
// semantic tokens below (Theme.accent, Theme.blue, …) and NEVER hardcode a hex,
// or they won't follow a theme change.
//
// File format of ~/.config/rice/colors: four lines, one #rrggbb each, in order
//   c1 = accent / hero
//   c2 = blue
//   c3 = cyan
//   c4 = teal
// Missing/invalid file ⇒ the built-in "indigo" defaults below.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme

    // --- base palette (defaults = the built-in "indigo" theme) -------------
    property color c1: "#5b6ee0"   // accent / hero
    property color c2: "#60a5fa"   // blue
    property color c3: "#22d3ee"   // cyan
    property color c4: "#2dd4bf"   // teal

    // --- semantic accents (bind to THESE, not c1..c4) ----------------------
    readonly property color accent:       c1
    readonly property color accentBright: Qt.lighter(c1, 1.30)   // big text, gradient peaks
    readonly property color accentDim:    Qt.darker(c1, 1.45)    // borders, gradient starts
    readonly property color accentMuted:  Qt.darker(c1, 1.95)    // placeholders
    readonly property color blue:         c2
    readonly property color blueBright:   Qt.lighter(c2, 1.30)
    readonly property color cyan:         c3
    readonly property color teal:         c4
    // Very dark, accent-tinted fill (album-art placeholder, etc.).
    readonly property color surfaceTint:  Qt.darker(c1, 4.20)
    // Back-compat aliases for older refs.
    readonly property color accent2:      c2
    readonly property color accent3:      c3

    // --- neutrals / danger (not themed) ------------------------------------
    readonly property color danger:   "#e87575"
    readonly property color fg0:      "#f4f4f6"
    readonly property color fg1:      "#c9c9d0"
    readonly property color fg2:      "#8e8e96"
    readonly property color fg3:      "#5e5e66"
    readonly property color line:     Qt.rgba(1,1,1,0.09)

    // --- translucency ------------------------------------------------------
    readonly property real  alpha:    0.32
    readonly property color surface:  Qt.rgba(0.086, 0.086, 0.110, alpha)
    readonly property color surface2: Qt.rgba(0.110, 0.110, 0.133, alpha + 0.18)
    readonly property color surface3: Qt.rgba(1,1,1,0.05)
    readonly property int   blur:     32

    // --- shape -------------------------------------------------------------
    readonly property int radius:      18
    readonly property int radiusSmall: 12
    readonly property int gap:         12
    readonly property int sidebarW:    72

    // --- animation ---------------------------------------------------------
    readonly property int  animFast: 180
    readonly property int  animMed:  240
    readonly property int  animSlow: 380
    readonly property var  easeOut:  [0.2, 0.85, 0.25, 1.0]

    // --- fonts -------------------------------------------------------------
    readonly property string fontSans: "Inter"
    readonly property string fontMono: "JetBrainsMono Nerd Font"

    // --- live palette file (mirrors services/Profile.qml) ------------------
    // Parse out up to four #rrggbb tokens, in order → c1..c4. A bad line just
    // leaves that slot at its previous (default) value, so a malformed file can
    // never strand the shell with no colors.
    function _apply(txt) {
        var hexes = (txt || "").match(/#[0-9a-fA-F]{6}/g) || [];
        if (hexes.length > 0) theme.c1 = hexes[0];
        if (hexes.length > 1) theme.c2 = hexes[1];
        if (hexes.length > 2) theme.c3 = hexes[2];
        if (hexes.length > 3) theme.c4 = hexes[3];
    }

    property FileView _file: FileView {
        path: Quickshell.env("HOME") + "/.config/rice/colors"
        watchChanges: true
        onFileChanged: reload()
        onLoaded:     theme._apply(text())
        // onLoadFailed intentionally omitted ⇒ keep the indigo defaults.
    }
}
