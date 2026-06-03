// ~/.config/quickshell/shell.qml — entry point
// Wires up the TopBar (hover-reveal dashboard). Each component lives in
// its own file; this just instantiates them.
//
// The lock screen is NOT handled by Quickshell — it's gtklock, fired
// only by the Mod+L keybind in niri. Quickshell's WlSessionLock proved
// unstable, so per CLAUDE.md the approved fallback (gtklock) owns locking.
// No idle daemon — lock is manual-only.
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
    Bars.SideBar { }

    // --- overlays --------------------------------------------------------
    // Launchpad-style app grid. Triggered via `qs ipc call launcher toggle`
    // (wired to Mod+Space in niri).
    Overlays.Launcher { }

    // Power menu (lock / sign out / suspend / reboot / power off). Triggered
    // via `qs ipc call power toggle` (wired to Mod+Escape in niri).
    Overlays.PowerFlyout { }

    // Network manager (status / wifi toggle / scan / connect). Triggered via
    // `qs ipc call network toggle` (wired to the SideBar network button).
    Overlays.NetworkFlyout { }

    // Bluetooth manager (status / power toggle / scan / connect). Triggered via
    // `qs ipc call bluetooth toggle` (wired to the SideBar bluetooth button).
    Overlays.BluetoothFlyout { }

    // Volume OSD. Pops up on any volume change; the niri XF86Audio* binds
    // fire `qs ipc call audio show` right after nudging wpctl.
    Overlays.VolumeOSD { }

    // Theme picker "menu". Triggered via `qs ipc call theme toggle` (wired to
    // Mod+T in niri); Mod+Shift+T cycles directly via `rice-theme next`.
    Overlays.ThemePicker { }
}
