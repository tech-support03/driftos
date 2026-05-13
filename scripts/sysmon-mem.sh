#!/usr/bin/env bash
# sysmon-mem — icon-only RAM widget.
set -Eeuo pipefail

read -r total used free shared buffers cached _ <<<"$(free -m | awk '/^Mem:/ {print $2,$3,$4,$5,$6,$7}')"
pct=$(( total > 0 ? (100*used)/total : 0 ))
swap_used="$(free -m | awk '/^Swap:/ {print $3" / "$2" MiB"}')"

tt="RAM  ${used} / ${total} MiB (${pct}%)"
tt+="\\nFree   ${free} MiB"
tt+="\\nCached ${cached} MiB"
tt+="\\nSwap   ${swap_used}"

printf '{"text":"","tooltip":"%s","class":"pct-%d"}\n' "$tt" "$pct"
