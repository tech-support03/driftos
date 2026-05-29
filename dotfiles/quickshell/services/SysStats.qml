// ~/.config/quickshell/services/SysStats.qml
// Singleton system-stats provider. Polls a single shell script every 1.5s
// and exposes reactive properties for CPU / Memory / GPU / Disk used by the
// SideBar's SystemMonitor widget.
//
// One Process per poll, not four — keeps CPU overhead negligible.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: stats

    // ---- percentages (0..100) -----------------------------------------------
    property int cpuPct: 0
    property int memPct: 0
    property int gpuPct: 0
    property int diskPct: 0

    // ---- CPU detail ---------------------------------------------------------
    property string cpuModel: ""         // e.g. "Ryzen 7 7800X3D"
    property string cpuFreq:  ""         // e.g. "4.8 GHz"
    property string cpuTemp:  ""         // e.g. "62°C"
    property string cpuThreads: ""       // e.g. "16 threads"

    // ---- Memory detail ------------------------------------------------------
    property string memTotal: ""         // e.g. "32 GB"
    property string memUsed:  ""         // e.g. "20.0 / 32 GB"
    property string memRate:  ""         // e.g. "6000 MT/s" (best-effort, may be empty)

    // ---- GPU detail ---------------------------------------------------------
    property string gpuModel: ""         // e.g. "RX 7800 XT"
    property string gpuFreq:  ""         // e.g. "2.4 GHz"
    property string gpuTemp:  ""         // e.g. "54°C"
    property string gpuVram:  ""         // e.g. "VRAM 4.1/16"

    // ---- Disk detail --------------------------------------------------------
    property string diskMount: "/"
    property string diskSource: ""       // e.g. "(nvme0n1p2)"
    property string diskUsed:   ""       // e.g. "4 / 931 GB"
    property string diskFs:     ""       // e.g. "ext4"
    property string diskKind:   ""       // e.g. "nvme"

    // Bundled poll script. Emits a single JSON object — we parse it once and
    // fan out into the per-field properties below.
    readonly property Process _proc: Process {
        command: ["sysmon-all"]
        stdout: StdioCollector {
            onStreamFinished: stats._ingest(this.text)
        }
    }

    readonly property Timer _tick: Timer {
        interval: 1500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: stats._proc.running = true
    }

    function _ingest(raw) {
        try {
            const j = JSON.parse(raw)
            cpuPct     = j.cpu_pct      | 0
            memPct     = j.mem_pct      | 0
            gpuPct     = j.gpu_pct      | 0
            diskPct    = j.disk_pct     | 0

            cpuModel   = j.cpu_model    || ""
            cpuFreq    = j.cpu_freq     || ""
            cpuTemp    = j.cpu_temp     || ""
            cpuThreads = j.cpu_threads  || ""

            memTotal   = j.mem_total    || ""
            memUsed    = j.mem_used     || ""
            memRate    = j.mem_rate     || ""

            gpuModel   = j.gpu_model    || ""
            gpuFreq    = j.gpu_freq     || ""
            gpuTemp    = j.gpu_temp     || ""
            gpuVram    = j.gpu_vram     || ""

            diskMount  = j.disk_mount   || "/"
            diskSource = j.disk_source  || ""
            diskUsed   = j.disk_used    || ""
            diskFs     = j.disk_fs      || ""
            diskKind   = j.disk_kind    || ""
        } catch (e) {
            // Malformed line — skip silently; next tick will replace.
        }
    }
}
