#!/usr/bin/env bash
# sysmon-cpu — icon-only CPU widget. Tooltip shows detailed per-core info.
set -Eeuo pipefail

read -r _ u1 n1 s1 i1 _ < /proc/stat
sleep 0.4
read -r _ u2 n2 s2 i2 _ < /proc/stat
total=$(( (u2+n2+s2+i2) - (u1+n1+s1+i1) ))
idle=$((  i2 - i1 ))
pct=$(( total > 0 ? (100*(total-idle))/total : 0 ))

freq_khz="$(awk '/cpu MHz/ {print int($4); exit}' /proc/cpuinfo 2>/dev/null || echo 0)"
temp=""
for hwmon in /sys/class/hwmon/hwmon*/temp1_input; do
    [[ -r "$hwmon" ]] || continue
    label="$(cat "$(dirname "$hwmon")/name" 2>/dev/null)"
    if [[ "$label" =~ ^(coretemp|k10temp|zenpower)$ ]]; then
        temp="$(($(cat "$hwmon")/1000))°C"
        break
    fi
done

tt="CPU  ${pct}%\\nFreq  ${freq_khz} MHz${temp:+\\nTemp  $temp}"
printf '{"text":"󰍛","tooltip":"%s","class":"pct-%d"}\n' "$tt" "$pct"
