#!/usr/bin/env bash
# theme-ly.sh — sync the ly login greeter to the active rice palette on an
# ALREADY-INSTALLED system. ly 1.x renders 24-bit colour (0xSSRRGGBB), so it
# takes the real rice colours: accent box border, dark accent-tinted background,
# light text, semantic-red errors. Also sets the on-brand static touches
# (12-hour clock per the rice's 12h rule, bullet password mask).
#
#     sudo scripts/theme-ly.sh                 # derive from ~/.config/rice/colors
#     sudo scripts/theme-ly.sh c1 c2 c3 c4     # explicit #rrggbb palette
#
# Why a separate, root, opt-in command (and NOT part of `rice-theme set`):
#   /etc/ly/config.ini is root-owned and read only when the greeter starts (at
#   boot or after logout), so there's nothing to update live. Like the boot menu
#   (scripts/theme-limine.sh), you resync this on demand; rice-theme reminds you
#   when it has drifted. Counterpart of that script — no signing, just config.
#
# Safety: edits ONLY the colour/appearance keys in /etc/ly/config.ini in place
# (idempotent), leaving every other ly setting and all comments untouched, and
# never rewrites the file wholesale — so it survives ly version bumps and can't
# strand the greeter. ly reads it fresh next start; a bad value can't lock you
# out of an already-running session.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo $0 $*" >&2; exit 1; }
CFG=/etc/ly/config.ini
[[ -f "$CFG" ]] || { echo "ERROR: $CFG missing — is ly installed?" >&2; exit 1; }

# ---- 1) resolve the 4 palette colours -------------------------------------
# Priority: explicit args > the invoking user's rice palette > indigo default.
if [[ $# -eq 4 ]]; then
    C1="$1" C2="$2" C3="$3" C4="$4"
else
    USER_HOME="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
    COLORS="$USER_HOME/.config/rice/colors"
    if [[ -r "$COLORS" ]]; then
        mapfile -t _c < <(grep -oE '#[0-9a-fA-F]{6}' "$COLORS")
        C1="${_c[0]:-#5b6ee0}" C2="${_c[1]:-#60a5fa}" C3="${_c[2]:-#22d3ee}" C4="${_c[3]:-#2dd4bf}"
        echo ">> palette from $COLORS"
    else
        C1="#5b6ee0" C2="#60a5fa" C3="#22d3ee" C4="#2dd4bf"
        echo ">> no rice palette found — using indigo default"
    fi
fi
[[ "$C1$C2$C3$C4" =~ ^(#[0-9a-fA-F]{6}){4}$ ]] || { echo "ERROR: need 4 #rrggbb colours (got: $C1 $C2 $C3 $C4)" >&2; exit 1; }

# ---- 2) derive the dark, accent-tinted background -------------------------
# Same darker(accent, 6.5) model as scripts/theme-limine.sh, so the login
# background matches the boot menu's.
BG="$(python3 - "$C1" <<'PY'
import sys, colorsys
h=sys.argv[1].lstrip('#'); r,g,b=[int(h[i:i+2],16)/255 for i in (0,2,4)]
hue,s,v=colorsys.rgb_to_hsv(r,g,b)
r,g,b=colorsys.hsv_to_rgb(hue,s,v/6.5)
print('%02x%02x%02x'%tuple(max(0,min(255,round(x*255))) for x in (r,g,b)))
PY
)"
ACCENT="${C1#\#}"      # box border = accent
FG="f4f4f6"            # light text for legibility
RED="f43f5e"           # semantic error — NOT themed (CLAUDE.md §13)

# ---- 3) apply keys in place (idempotent; matches commented or live lines) --
set_key() {
    local k="$1" v="$2"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${k}[[:space:]]*=" "$CFG"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${k}[[:space:]]*=.*|${k} = ${v}|" "$CFG"
    else
        printf '%s = %s\n' "$k" "$v" >> "$CFG"
    fi
}
set_key bg        "0x00${BG}"
set_key fg        "0x00${FG}"
set_key border_fg "0x00${ACCENT}"
set_key error_fg  "0x01${RED}"      # 0x01 = TB_BOLD
set_key clock     "%I:%M %p"        # 12-hour, per the rice's 12h-everywhere rule
set_key asterisk  "0x2022"          # bullet password mask

# ---- 4) stamp the synced palette so rice-theme can detect drift -----------
# A comment line (ly ignores '#' lines), same marker the boot menu uses.
sed -i '/^# rice-synced-colors:/d' "$CFG"
printf '# rice-synced-colors: %s %s %s %s\n' "$C1" "$C2" "$C3" "$C4" >> "$CFG"

echo ">> ly themed:  bg=0x00$BG  fg=0x00$FG  border=0x00$ACCENT  error=0x01$RED  clock=12h"
echo ">> takes effect at the next greeter (reboot, or log out of niri)."
