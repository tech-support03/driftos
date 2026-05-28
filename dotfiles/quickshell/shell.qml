// ~/.config/quickshell/shell.qml — entry point
// Wires up the TopBar (hover-reveal dashboard). Each component lives in
// its own file; this just instantiates them.
//
// The lock screen is NOT handled by Quickshell — it's gtklock (see
// niri config Mod+L and swayidle). Quickshell's WlSessionLock proved
// unstable, so per CLAUDE.md the approved fallback (gtklock) owns locking.
//
// IMPORTANT: keep this file thin. Logic goes in services/, UI goes in
// bars/. Theme tokens come from Theme.qml — never hardcode a color here.

import QtQuick
import Quickshell
import "bars" as Bars
import "overlays" as Overlays

ShellRoot {
    id: root

    // --- panels (one per output handled inside each component) ---
    Bars.TopBar { }

    // --- overlays --------------------------------------------------------
    // Launchpad-style app grid. Triggered via `qs ipc call launcher toggle`
    // (wired to Mod+Space in niri).
    Overlays.Launcher { }
}
