#!/usr/bin/env bash
# sysmon-all — one-shot JSON emitter for the Quickshell SystemMonitor widget.
# Replaces the four waybar sysmon-* scripts. Emits ONE JSON object so the QML
# service only spawns a single process per poll instead of four.
#
# Fields (all best-effort; missing values become ""):
#   cpu_pct, cpu_model, cpu_freq, cpu_temp, cpu_threads
#   mem_pct, mem_total, mem_used, mem_rate
#   gpu_pct, gpu_model, gpu_freq, gpu_temp, gpu_vram
#   disk_pct, disk_mount, disk_source, disk_used, disk_fs, disk_kind
set -Eeuo pipefail

# ---- CPU ----------------------------------------------------------------------
read -r _ u1 n1 s1 i1 _ < /proc/stat
sleep 0.3
read -r _ u2 n2 s2 i2 _ < /proc/stat
cpu_total=$(( (u2+n2+s2+i2) - (u1+n1+s1+i1) ))
cpu_idle=$((  i2 - i1 ))
cpu_pct=$(( cpu_total > 0 ? (100*(cpu_total-cpu_idle))/cpu_total : 0 ))

cpu_model="$(awk -F: '/^model name/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' /proc/cpuinfo \
            | sed -E 's/\(R\)//g; s/\(TM\)//g; s/CPU//g; s/[Pp]rocessor//g; s/[0-9]+-Core//g; s/  +/ /g; s/^ +| +$//g')"
cpu_threads_num="$(nproc 2>/dev/null || echo 0)"
cpu_threads="${cpu_threads_num} threads"

# Average frequency across all cores, in GHz with one decimal.
cpu_freq_mhz="$(awk '/cpu MHz/ {sum+=$4; n++} END {if (n>0) printf "%d", sum/n; else print 0}' /proc/cpuinfo)"
cpu_freq=""
if (( cpu_freq_mhz > 0 )); then
    cpu_freq="$(awk -v m="$cpu_freq_mhz" 'BEGIN { printf "%.1f GHz", m/1000 }')"
fi

cpu_temp=""
for hwmon in /sys/class/hwmon/hwmon*/temp1_input; do
    [[ -r "$hwmon" ]] || continue
    label="$(cat "$(dirname "$hwmon")/name" 2>/dev/null || echo)"
    if [[ "$label" =~ ^(coretemp|k10temp|zenpower)$ ]]; then
        cpu_temp="$(($(cat "$hwmon")/1000))°C"
        break
    fi
done

# ---- Memory -------------------------------------------------------------------
read -r mem_total_kib mem_avail_kib < <(awk '
    /^MemTotal:/     {t=$2}
    /^MemAvailable:/ {a=$2}
    END {print t, a}' /proc/meminfo)
mem_total_kib="${mem_total_kib:-0}"
mem_avail_kib="${mem_avail_kib:-0}"
mem_used_kib=$(( mem_total_kib - mem_avail_kib ))
mem_pct=0
(( mem_total_kib > 0 )) && mem_pct=$(( (100 * mem_used_kib) / mem_total_kib ))

mem_total_gb="$(awk -v k="$mem_total_kib" 'BEGIN { printf "%d", (k+524288)/1048576 }')"
mem_used_gb_one="$(awk  -v k="$mem_used_kib"  'BEGIN { printf "%.1f", k/1048576 }')"
mem_total="${mem_total_gb} GB"
mem_used="${mem_used_gb_one} / ${mem_total_gb} GB"

# DRAM rate, best-effort. dmidecode needs root, so try cached /sys path first.
mem_rate=""
for f in /sys/devices/system/memory/configured_clock_speed; do
    [[ -r "$f" ]] || continue
    v="$(cat "$f" 2>/dev/null)"
    [[ -n "$v" && "$v" -gt 0 ]] && mem_rate="${v} MT/s" && break
done

# ---- GPU ----------------------------------------------------------------------
gpu_pct=0; gpu_model=""; gpu_freq=""; gpu_temp=""; gpu_vram=""

# Pick the AMD discrete GPU if present (largest VRAM among amdgpu cards).
amd_card=""; amd_vram_max=0
for card in /sys/class/drm/card[0-9]*; do
    [[ -e "$card/device/uevent" ]] || continue
    grep -q '^DRIVER=amdgpu$' "$card/device/uevent" 2>/dev/null || continue
    vram="$(cat "$card/device/mem_info_vram_total" 2>/dev/null || echo 0)"
    if (( vram > amd_vram_max )); then
        amd_vram_max="$vram"
        amd_card="$card"
    fi
done

if [[ -n "$amd_card" ]]; then
    pci="$(basename "$(readlink -f "$amd_card/device")")"        # e.g. 0000:03:00.0
    gpu_pct="$(cat "$amd_card/device/gpu_busy_percent" 2>/dev/null || echo 0)"

    # Friendly model name from lspci, trimmed to the "RX 7800 XT" tail.
    raw_name="$(lspci -mm 2>/dev/null | awk -v p="${pci#0000:}" '$1==p { for(i=4;i<=NF;i++) printf "%s ", $i; print "" }' | tr -d '"')"
    # Common shapes: "Navi 32 [Radeon RX 7800 XT]"  →  "RX 7800 XT"
    gpu_model="$(printf '%s' "$raw_name" | sed -nE 's/.*\[Radeon[[:space:]]+([^]]*)\].*/\1/p')"
    [[ -z "$gpu_model" ]] && gpu_model="$(printf '%s' "$raw_name" | sed -E 's/[[:space:]]+\(rev [^)]+\)//; s/^[[:space:]]+|[[:space:]]+$//g')"

    # Find the hwmon entry whose device symlink matches this PCI slot.
    for h in /sys/class/hwmon/hwmon*; do
        [[ "$(cat "$h/name" 2>/dev/null)" == "amdgpu" ]] || continue
        [[ "$(basename "$(readlink -f "$h/device")")" == "$pci" ]] || continue
        if [[ -r "$h/temp1_input" ]]; then
            gpu_temp="$(($(cat "$h/temp1_input")/1000))°C"
        fi
        if [[ -r "$h/freq1_input" ]]; then
            gpu_freq="$(awk -v hz="$(cat "$h/freq1_input")" \
                'BEGIN { mhz = hz/1e6; if (mhz >= 1000) printf "%.1f GHz", mhz/1000; else printf "%d MHz", mhz }')"
        fi
        break
    done

    vram_total="$(cat "$amd_card/device/mem_info_vram_total" 2>/dev/null || echo 0)"
    vram_used="$( cat "$amd_card/device/mem_info_vram_used"  2>/dev/null || echo 0)"
    if (( vram_total > 0 )); then
        gpu_vram="$(awk -v u="$vram_used" -v t="$vram_total" \
            'BEGIN { printf "VRAM %.1f/%.0f", u/1073741824, t/1073741824 }')"
    fi
elif command -v nvidia-smi >/dev/null 2>&1; then
    line="$(nvidia-smi --query-gpu=name,utilization.gpu,clocks.gr,temperature.gpu,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | head -n1)"
    if [[ -n "$line" ]]; then
        IFS=',' read -r n_name n_util n_clock n_temp n_memu n_memt <<<"$line"
        gpu_model="$(printf '%s' "$n_name" | sed -E 's/NVIDIA[[:space:]]+//; s/GeForce[[:space:]]+//; s/^[[:space:]]+|[[:space:]]+$//g')"
        gpu_pct="$(printf '%s' "$n_util" | tr -d ' ')"
        gpu_freq="$(awk -v c="$(printf '%s' "$n_clock" | tr -d ' ')" 'BEGIN { printf "%.1f GHz", c/1000 }')"
        gpu_temp="$(printf '%s' "$n_temp" | tr -d ' ')°C"
        gpu_vram="$(awk -v u="$(printf '%s' "$n_memu" | tr -d ' ')" -v t="$(printf '%s' "$n_memt" | tr -d ' ')" \
            'BEGIN { printf "VRAM %.1f/%.0f", u/1024, t/1024 }')"
    fi
fi

# ---- Disk (root mount) --------------------------------------------------------
read -r d_total d_used d_pcent < <(df -B1 --output=size,used,pcent / | awk 'NR==2 {print $1, $2, $3}')
disk_pct="${d_pcent%\%}"
disk_total_gb="$(awk -v b="${d_total:-0}" 'BEGIN { printf "%d", b/1000000000 }')"
disk_used_gb="$( awk -v b="${d_used:-0}"  'BEGIN { printf "%d", b/1000000000 }')"
disk_used="${disk_used_gb} / ${disk_total_gb} GB"

disk_src_path="$(findmnt -no SOURCE / 2>/dev/null || echo)"
disk_fs="$(findmnt -no FSTYPE / 2>/dev/null || echo)"
disk_source="$(basename "$disk_src_path")"

disk_kind=""
if [[ "$disk_source" == nvme* ]]; then
    disk_kind="nvme"
elif [[ -r "/sys/block/$(echo "$disk_source" | sed -E 's/[0-9]+$//; s/p$//')/queue/rotational" ]]; then
    rot="$(cat "/sys/block/$(echo "$disk_source" | sed -E 's/[0-9]+$//; s/p$//')/queue/rotational" 2>/dev/null)"
    [[ "$rot" == "0" ]] && disk_kind="ssd" || disk_kind="hdd"
fi

# ---- emit ---------------------------------------------------------------------
# Use jq if available for clean escaping; otherwise hand-roll. jq is in base-devel
# territory and almost always present, but fall back regardless.
if command -v jq >/dev/null 2>&1; then
    jq -nc \
        --argjson cpu_pct  "$cpu_pct"  --arg cpu_model   "$cpu_model"  --arg cpu_freq "$cpu_freq" \
        --arg cpu_temp     "$cpu_temp" --arg cpu_threads "$cpu_threads" \
        --argjson mem_pct  "$mem_pct"  --arg mem_total   "$mem_total"  --arg mem_used "$mem_used" \
        --arg mem_rate     "$mem_rate" \
        --argjson gpu_pct  "$gpu_pct"  --arg gpu_model   "$gpu_model"  --arg gpu_freq "$gpu_freq" \
        --arg gpu_temp     "$gpu_temp" --arg gpu_vram    "$gpu_vram" \
        --argjson disk_pct "$disk_pct" --arg disk_mount  "/"           --arg disk_source "$disk_source" \
        --arg disk_used    "$disk_used" --arg disk_fs    "$disk_fs"   --arg disk_kind   "$disk_kind" \
        '{cpu_pct:$cpu_pct, cpu_model:$cpu_model, cpu_freq:$cpu_freq, cpu_temp:$cpu_temp, cpu_threads:$cpu_threads,
          mem_pct:$mem_pct, mem_total:$mem_total, mem_used:$mem_used, mem_rate:$mem_rate,
          gpu_pct:$gpu_pct, gpu_model:$gpu_model, gpu_freq:$gpu_freq, gpu_temp:$gpu_temp, gpu_vram:$gpu_vram,
          disk_pct:$disk_pct, disk_mount:$disk_mount, disk_source:$disk_source, disk_used:$disk_used,
          disk_fs:$disk_fs, disk_kind:$disk_kind}'
else
    esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    printf '{"cpu_pct":%d,"cpu_model":"%s","cpu_freq":"%s","cpu_temp":"%s","cpu_threads":"%s",' \
        "$cpu_pct" "$(esc "$cpu_model")" "$(esc "$cpu_freq")" "$(esc "$cpu_temp")" "$(esc "$cpu_threads")"
    printf '"mem_pct":%d,"mem_total":"%s","mem_used":"%s","mem_rate":"%s",' \
        "$mem_pct" "$(esc "$mem_total")" "$(esc "$mem_used")" "$(esc "$mem_rate")"
    printf '"gpu_pct":%d,"gpu_model":"%s","gpu_freq":"%s","gpu_temp":"%s","gpu_vram":"%s",' \
        "$gpu_pct" "$(esc "$gpu_model")" "$(esc "$gpu_freq")" "$(esc "$gpu_temp")" "$(esc "$gpu_vram")"
    printf '"disk_pct":%d,"disk_mount":"/","disk_source":"%s","disk_used":"%s","disk_fs":"%s","disk_kind":"%s"}\n' \
        "$disk_pct" "$(esc "$disk_source")" "$(esc "$disk_used")" "$(esc "$disk_fs")" "$(esc "$disk_kind")"
fi
