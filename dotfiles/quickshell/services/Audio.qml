// ~/.config/quickshell/services/Audio.qml
// Singleton volume provider — the single source of truth for the default
// sink's level and mute state. Both the SideBar volume button and the
// VolumeOSD overlay bind to this, so there is exactly ONE wpctl poller.
//
// State is kept fresh two ways:
//   • a steady 250ms poll, so changes from any source (pavucontrol, media
//     keys hitting wpctl directly, `audio show` IPC) show up promptly;
//   • a 40ms "settle" re-probe right after WE issue a change, so the UI
//     snaps to the new value instead of waiting for the next poll tick.
//
// `bumped()` fires only on a real change (not on the first read), so the OSD
// can pop itself for scroll / pavucontrol changes without flashing at login.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: audio

    property int  volume: 0          // 0..100
    property bool muted:  false

    // Nerd-font speaker glyphs, tiered by level (matches the old SideBar set).
    readonly property string glyph: {
        if (muted)       return "󰸈"
        if (volume < 34) return "󰕿"
        if (volume < 67) return "󰖀"
        return "󰕾"
    }

    // Emitted on an observed change so passive consumers (the OSD) can react.
    signal bumped()

    // Suppresses bumped() on the very first read (0 → actual at startup).
    property bool _ready: false

    property Process _probe: Process {
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo 'Volume: 0.0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = (this.text || "").trim()
                const m = t.match(/Volume: ([0-9.]+)/)
                const newVol   = m ? Math.round(parseFloat(m[1]) * 100) : 0
                const newMuted = t.indexOf("[MUTED]") !== -1
                const changed  = audio._ready && (newVol !== audio.volume || newMuted !== audio.muted)
                audio.volume = newVol
                audio.muted  = newMuted
                audio._ready = true
                if (changed) audio.bumped()
            }
        }
    }

    // Steady poll.
    property Timer _poll: Timer {
        interval: 250; repeat: true; running: true; triggeredOnStart: true
        onTriggered: audio._probe.running = true
    }
    // Quick re-probe shortly after we issue a change.
    property Timer _settle: Timer {
        interval: 40
        onTriggered: audio._probe.running = true
    }

    function refresh() { _probe.running = true }

    // arg is a wpctl delta/value, e.g. "2%+", "5%-", "0.5". Capped at 100%.
    function setVolume(arg) {
        Quickshell.execDetached(["sh", "-c",
            "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ " + arg])
        _settle.restart()
    }
    function toggleMute() {
        Quickshell.execDetached(["sh", "-c",
            "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
        _settle.restart()
    }
}
