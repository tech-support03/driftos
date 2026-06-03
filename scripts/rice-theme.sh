#!/usr/bin/env bash
# rice-theme — apply a 4-colour palette across the WHOLE rice, live.
#
#   rice-theme status            print the active theme name
#   rice-theme list              list saved themes (● = active)
#   rice-theme set <name>        apply a saved theme
#   rice-theme apply-colors c1 c2 c3 c4   apply 4 colours LIVE, without saving
#   rice-theme next              cycle to the next saved theme (+ notification)
#   rice-theme create <name> c1 c2 c3 c4   write a new theme from 4 colours
#   rice-theme save <name>       snapshot the CURRENT live palette as <name>
#   rice-theme apply             re-apply the active theme (used at boot)
#
# A "theme" is four colours (c1=accent/hero, c2=blue, c3=cyan, c4=teal). Every
# other shade — bright/dim/muted accents, the album-art tint, btop's gradients —
# is DERIVED here, so you only ever choose four. Design mirrors `rice-profile`:
#   • Quickshell reads ~/.config/rice/colors LIVE (Theme.qml FileView) → no restart.
#   • btop / gtklock / fastfetch / zsh can't watch a file, so they're GENERATED
#     from templates into ~/.config and pick up the change on next launch.
set -Eeuo pipefail

RICE_DIR="$HOME/.config/rice"
THEMES_DIR="$RICE_DIR/themes"
TPL_DIR="$RICE_DIR/templates"
ACTIVE_FILE="$RICE_DIR/theme"
COLORS_FILE="$RICE_DIR/colors"     # 4 hex lines — Quickshell Theme.qml reads this live
COLORS_SH="$RICE_DIR/colors.sh"    # shell vars — ~/.zshrc sources this for the prompt

BTOP_THEME="$HOME/.config/btop/themes/driftos.theme"
GTKLOCK_CSS="$HOME/.config/gtklock/style.css"
FASTFETCH_CFG="$HOME/.config/fastfetch/config.jsonc"

c_info() { printf '\033[34m::\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31mrice-theme:\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# Parse c1..c4 (and name) out of a theme file into globals C1..C4 / TNAME.
load_theme_file() {
    local f="$1" k v
    [[ -r "$f" ]] || die "no such theme: $f"
    TNAME="$(basename "$f" .theme)"; C1=""; C2=""; C3=""; C4=""
    while IFS='=' read -r k v; do
        k="${k// /}"; v="${v// /}"
        case "$k" in
            name) TNAME="$v" ;;
            c1) C1="$v" ;; c2) C2="$v" ;; c3) C3="$v" ;; c4) C4="$v" ;;
        esac
    done < <(grep -vE '^\s*#|^\s*$' "$f")
    [[ "$C1$C2$C3$C4" =~ ^(#[0-9a-fA-F]{6}){4}$ ]] || \
        die "theme '$TNAME' must define 4 hex colours c1..c4 (got: $C1 $C2 $C3 $C4)"
}

# Replace a possible symlink target with a real file (never write through the
# repo symlink) — same trick 08-link-dotfiles.sh uses for niri's config.kdl.
write_real() { local dst="$1"; mkdir -p "$(dirname "$dst")"; [[ -L "$dst" ]] && rm -f "$dst"; cat > "$dst"; }

active_name() { [[ -r "$ACTIVE_FILE" ]] && tr -d ' \n' < "$ACTIVE_FILE" || echo ""; }
themes_list() { find "$THEMES_DIR" -maxdepth 1 -name '*.theme' -printf '%f\n' 2>/dev/null | sed 's/\.theme$//' | sort; }

# ---- the core: apply C1..C4 everywhere --------------------------------------
apply_palette() {
    mkdir -p "$RICE_DIR"
    # 1) Quickshell — live via Theme.qml's FileView. Four hex lines, c1..c4.
    printf '%s\n%s\n%s\n%s\n' "$C1" "$C2" "$C3" "$C4" > "$COLORS_FILE"

    # 2) Everything that can't watch a file: derive shades + render in Python.
    C1="$C1" C2="$C2" C3="$C3" C4="$C4" \
    TPL_DIR="$TPL_DIR" BTOP_THEME="$BTOP_THEME" GTKLOCK_CSS="$GTKLOCK_CSS" \
    FASTFETCH_CFG="$FASTFETCH_CFG" COLORS_SH="$COLORS_SH" \
    python3 - "$@" <<'PY'
import os, colorsys, re

def hex2rgb(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))
def rgb2hex(r): return '#%02x%02x%02x' % tuple(max(0,min(255,round(x))) for x in r)
def _hsv(h):
    r,g,b=[x/255 for x in hex2rgb(h)]; return colorsys.rgb_to_hsv(r,g,b)
def _back(hue,s,v):
    r,g,b=colorsys.hsv_to_rgb(hue,max(0,min(1,s)),max(0,min(1,v))); return rgb2hex((r*255,g*255,b*255))
def lighter(h,f):                      # ~ Qt.lighter: scale value, ease saturation as it clamps
    hue,s,v=_hsv(h); nv=v*f
    if nv>1: s=s/ (nv); nv=1.0
    return _back(hue,s,nv)
def darker(h,f):
    hue,s,v=_hsv(h); return _back(hue,s,v/f)
def sgr(h): r,g,b=hex2rgb(h); return "38;2;%d;%d;%d"%(r,g,b)

c1=os.environ['C1']; c2=os.environ['C2']; c3=os.environ['C3']; c4=os.environ['C4']
P=dict(
    accent=c1, accent_bright=lighter(c1,1.30), accent_dim=darker(c1,1.45),
    accent_muted=darker(c1,1.95), surface_tint=darker(c1,4.20),
    blue=c2, blue_bright=lighter(c2,1.30), cyan=c3, teal=c4,
)

# --- gtklock + fastfetch: substitute @TOKEN@ in the templates ---------------
def render(tpl, dst, repl):
    with open(tpl) as f: s=f.read()
    for k,v in repl.items(): s=s.replace(k,v)
    d=os.path.dirname(dst)
    if d: os.makedirs(d, exist_ok=True)
    # never write through a symlink into the repo
    if os.path.islink(dst): os.unlink(dst)
    with open(dst,'w') as f: f.write(s)

tpl=os.environ['TPL_DIR']
render(os.path.join(tpl,'gtklock-style.css.tmpl'), os.environ['GTKLOCK_CSS'],
       {'@ACCENT@': P['accent']})
render(os.path.join(tpl,'fastfetch-config.jsonc.tmpl'), os.environ['FASTFETCH_CFG'],
       {'@ACCENT_SGR@': sgr(P['accent']), '@CYAN_SGR@': sgr(P['cyan'])})

# --- btop driftos.theme: emit the whole thing (it's all colour) -------------
def ramp(base, lo=1.7, hi=1.30): return (darker(base,lo), darker(base,1.18), base) if hi==1.30 else (darker(base,lo), base, lighter(base,hi))
acc_lo,acc_mid,acc_hi = darker(P['accent'],1.7), P['accent'], P['accent_bright']
btop=f"""# driftos — generated by `rice-theme`. Edit the THEME (4 colours), not this.
theme[main_bg]=""
theme[main_fg]="#f4f4f6"
theme[title]="#f4f4f6"
theme[hi_fg]="{P['accent']}"
theme[selected_bg]="{P['accent']}"
theme[selected_fg]="#12131a"
theme[inactive_fg]="#5e5e66"
theme[graph_text]="#f4f4f6"
theme[meter_bg]="#23232c"
theme[proc_misc]="{P['accent']}"
theme[cpu_box]="{P['accent']}"
theme[mem_box]="{P['blue']}"
theme[net_box]="{P['teal']}"
theme[proc_box]="{P['accent']}"
theme[div_line]="#2a2a35"
theme[temp_start]="{P['accent_dim']}"
theme[temp_mid]="{P['accent']}"
theme[temp_end]="{P['cyan']}"
theme[cpu_start]="{P['accent_dim']}"
theme[cpu_mid]="{P['accent']}"
theme[cpu_end]="{P['accent_bright']}"
theme[free_start]="{darker(P['teal'],1.7)}"
theme[free_mid]="{darker(P['teal'],1.18)}"
theme[free_end]="{P['teal']}"
theme[cached_start]="{darker(P['blue'],1.7)}"
theme[cached_mid]="{darker(P['blue'],1.18)}"
theme[cached_end]="{P['blue']}"
theme[available_start]="{darker(P['cyan'],1.7)}"
theme[available_mid]="{darker(P['cyan'],1.18)}"
theme[available_end]="{P['cyan']}"
theme[used_start]="{P['accent_dim']}"
theme[used_mid]="{P['blue']}"
theme[used_end]="{P['cyan']}"
theme[download_start]="{P['accent_dim']}"
theme[download_mid]="{P['accent']}"
theme[download_end]="{P['accent_bright']}"
theme[upload_start]="{darker(P['teal'],1.7)}"
theme[upload_mid]="{darker(P['teal'],1.18)}"
theme[upload_end]="{P['teal']}"
theme[process_start]="#5e5e66"
theme[process_mid]="{P['accent']}"
theme[process_end]="{P['accent_bright']}"
"""
# write btop via the same de-symlink helper the shell uses (handled in bash)
with open('/tmp/.rice-btop-theme','w') as f: f.write(btop)

# --- zsh prompt colours -----------------------------------------------------
with open(os.environ['COLORS_SH'],'w') as f:
    f.write("# generated by rice-theme — sourced by ~/.zshrc\n")
    for k in ('accent','accent_bright','accent_dim','accent_muted','blue','blue_bright','cyan','teal'):
        f.write('export RICE_%s="%s"\n' % (k.upper(), P[k]))
PY

    # btop theme written to a tmp file by python; place it (de-symlinking).
    write_real "$BTOP_THEME" < /tmp/.rice-btop-theme && rm -f /tmp/.rice-btop-theme
}

# ---- subcommands ------------------------------------------------------------
cmd_set() {
    local name="$1"
    load_theme_file "$THEMES_DIR/$name.theme"
    apply_palette
    echo "$TNAME" > "$ACTIVE_FILE"
    c_info "theme → $TNAME ($C1 $C2 $C3 $C4)"
}

cmd_next() {
    local cur all arr i n; cur="$(active_name)"
    mapfile -t arr < <(themes_list)
    [[ ${#arr[@]} -gt 0 ]] || die "no themes in $THEMES_DIR"
    n=${#arr[@]}; i=0
    for ((j=0;j<n;j++)); do [[ "${arr[$j]}" == "$cur" ]] && i=$j; done
    local nxt="${arr[$(((i+1)%n))]}"
    cmd_set "$nxt"
    command -v notify-send >/dev/null && \
        notify-send -t 2500 "Theme → $nxt" "$C1  $C2  $C3  $C4" || true
}

cmd_create() {
    local name="$1" c1="$2" c2="$3" c3="$4" c4="$5"
    [[ "$c1$c2$c3$c4" =~ ^(#[0-9a-fA-F]{6}){4}$ ]] || die "need 4 #rrggbb colours"
    mkdir -p "$THEMES_DIR"
    cat > "$THEMES_DIR/$name.theme" <<EOF
# rice theme — c1=accent/hero c2=blue c3=cyan c4=teal (shades derived by rice-theme)
name=$name
c1=$c1
c2=$c2
c3=$c3
c4=$c4
EOF
    c_info "created theme '$name'"
}

cmd_save() {  # snapshot current live palette under a new name
    local name="$1"
    [[ -r "$COLORS_FILE" ]] || die "no live palette yet — run 'rice-theme set <name>' first"
    mapfile -t L < <(grep -oE '#[0-9a-fA-F]{6}' "$COLORS_FILE")
    [[ ${#L[@]} -ge 4 ]] || die "live palette incomplete"
    cmd_create "$name" "${L[0]}" "${L[1]}" "${L[2]}" "${L[3]}"
}

cmd_list() {
    local cur; cur="$(active_name)"
    while read -r t; do
        [[ -z "$t" ]] && continue
        if [[ "$t" == "$cur" ]]; then printf '  ● %s (active)\n' "$t"; else printf '  ○ %s\n' "$t"; fi
    done < <(themes_list)
}

main() {
    local cmd="${1:-status}"; shift || true
    case "$cmd" in
        status) active_name; echo ;;
        list)   cmd_list ;;
        set)    [[ $# -ge 1 ]] || die "usage: rice-theme set <name>"; cmd_set "$1" ;;
        apply-colors)  # apply 4 colours LIVE without saving a named theme
                [[ $# -eq 4 ]] || die "usage: rice-theme apply-colors c1 c2 c3 c4"
                [[ "$1$2$3$4" =~ ^(#[0-9a-fA-F]{6}){4}$ ]] || die "need 4 #rrggbb colours"
                C1="$1" C2="$2" C3="$3" C4="$4"; apply_palette
                echo "custom" > "$ACTIVE_FILE"
                c_info "applied custom palette (NOT saved — 'rice-theme save <name>' to keep it)" ;;
        next)   cmd_next ;;
        create) [[ $# -eq 5 ]] || die "usage: rice-theme create <name> c1 c2 c3 c4"; cmd_create "$@" ;;
        save)   [[ $# -ge 1 ]] || die "usage: rice-theme save <name>"; cmd_save "$1" ;;
        apply)  local a; a="$(active_name)"; [[ -n "$a" ]] || a="indigo"; cmd_set "$a" ;;
        *) die "unknown command: $cmd (try: status|list|set|next|create|save|apply)" ;;
    esac
}
main "$@"
