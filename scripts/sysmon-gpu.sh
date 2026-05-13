#!/usr/bin/env bash
# sysmon-gpu — icon-only GPU widget. Detects NVIDIA, AMD, Intel; emits empty
# tooltip lines for fields the driver doesn't expose.
set -Eeuo pipefail

vendor=""; util=""; temp=""; clock=""; fan=""

if command -v nvidia-smi >/dev/null 2>&1; then
    vendor="NVIDIA"
    read -r util temp clock fan <<<"$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,clocks.gr,fan.speed --format=csv,noheader,nounits | head -n1 | tr ',' ' ')"
    util="${util}%"; temp="${temp}°C"; clock="${clock} MHz"; fan="${fan}%"
elif [[ -d /sys/class/drm/card0/device ]] && grep -qi amdgpu /sys/class/drm/card0/device/uevent 2>/dev/null; then
    vendor="AMD"
    util="$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null)%"
    for h in /sys/class/hwmon/hwmon*/temp1_input; do
        n="$(cat "$(dirname "$h")/name" 2>/dev/null)"
        [[ "$n" == "amdgpu" ]] && temp="$(($(cat "$h")/1000))°C"
    done
elif [[ -d /sys/class/drm/card0 ]] && lspci -k 2>/dev/null | grep -qi 'VGA.*Intel'; then
    vendor="Intel"
    util="—"
fi

tt="GPU  ${vendor:-Unknown}"
[[ -n "$util"  ]] && tt+="\\nUtil  $util"
[[ -n "$temp"  ]] && tt+="\\nTemp  $temp"
[[ -n "$clock" ]] && tt+="\\nClock $clock"
[[ -n "$fan"   ]] && tt+="\\nFan   $fan"

printf '{"text":"󰢮","tooltip":"%s"}\n' "$tt"
