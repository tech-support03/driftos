// ~/.config/quickshell/services/Profile.qml
// Runtime visual profile: "full" (desktop / Ryzen laptop) or "light" (4GB
// MacBook Air, Intel HD 5000). The single source of truth is the one-word text
// file ~/.config/rice/profile, written by the `rice-profile` CLI. We watch it,
// so `rice-profile toggle` re-flows the shell live with NO restart — every
// consumer just binds to `Profile.light`.
//
// "light" is purely cosmetic/perf; no widget is removed:
//   • TopBar  — skips the cava subprocess + 30fps simulated waveform (TopBar.qml)
//   • SysStats — slows the system-monitor poll 1.5s → 5s (SysStats.qml)
//   • surfaces — drawn opaque instead of translucent (no blur to hide behind)
// Everything else (sysmon detail popover, launcher, flyouts, clocks) is identical.
//
// The boot seed (rice-profile-seed, run at niri startup) reads the kernel
// cmdline `rice.profile=` and writes the file before Quickshell starts, so the
// MacBook's GRUB entry comes up light automatically.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: profile

    // Default to "full" until the file is read; flips reactively on any write.
    property string name: "full"
    readonly property bool light: name === "light"

    // Convenience tokens consumers can bind to so the full/light decision lives
    // here, not scattered across widgets.
    readonly property real surfaceAlpha: light ? 1.0 : 0.32   // opaque vs translucent
    readonly property int  animFast: light ? 120 : 180
    readonly property int  animMed:  light ? 160 : 240
    readonly property int  animSlow: light ? 230 : 380

    property FileView _file: FileView {
        // blockLoading so `light` is correct on the first frame (no flash of the
        // full theme before the file is read on a light machine).
        path: Quickshell.env("HOME") + "/.config/rice/profile"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded:     profile.name = (text().trim() === "light") ? "light" : "full"
        onLoadFailed: profile.name = "full"   // missing file ⇒ full
    }
}
