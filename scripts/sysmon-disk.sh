#!/usr/bin/env bash
# sysmon-disk — icon-only disk widget. Tooltip shows root usage plus any
# additional locally-mounted filesystems (e.g. /home if it's a separate FS,
# external drives, NVMe mounts).
set -Eeuo pipefail

# Root mount usage in human units.
read -r size used avail pcent <<<"$(df -h --output=size,used,avail,pcent / | awk 'NR==2 {print $1,$2,$3,$4}')"

tt="Disk  ${used} / ${size} (${pcent})"
tt+="\\nFree  ${avail}"

# Additional real mounts (skip pseudo filesystems and the root we already showed).
extras="$(df -h -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x fuse.portal \
              --output=target,size,used,avail,pcent 2>/dev/null \
          | awk 'NR>1 && $1!="/" {printf "\\n%s  %s / %s (%s)", $1, $3, $2, $5}')"
tt+="${extras}"

# pct-N class for optional styling (e.g. tint red when >90%).
pct_int="${pcent%\%}"
pct_int="${pct_int# }"
printf '{"text":"󰋊","tooltip":"%s","class":"pct-%d"}\n' "$tt" "$pct_int"
