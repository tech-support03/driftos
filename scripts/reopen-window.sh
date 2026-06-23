#!/usr/bin/env bash
# reopen-window — Chrome-style "reopen last closed window" for niri.
#
# niri has no built-in for this, and it cannot snapshot an app's internal
# state — only which app a window belonged to (its app_id). So:
#   • browsers are relaunched with session restore, so the closed window's
#     tabs come back (the Ctrl+Shift+T equivalent);
#   • every other app is relaunched fresh.
#
# Two modes:
#   reopen-window watch   (default; spawned at niri startup)
#       Follows niri's event stream and keeps a stack of the app_ids of
#       closed windows in $XDG_RUNTIME_DIR/niri-reopen-stack.
#   reopen-window pop      (bound to Mod+Ctrl+T)
#       Pops the stack and relaunches the most-recently-closed window's app.
#
# The stack lives in the runtime dir, so it resets cleanly each login.
set -Eeuo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STACK="$RUNTIME/niri-reopen-stack"
LOCK="$RUNTIME/niri-reopen.lock"

launch() { setsid -f "$@" >/dev/null 2>&1 || true; }

reopen() {
    [[ -s "$STACK" ]] || exit 0

    local app
    app="$(tail -n 1 "$STACK")"
    # Pop the last entry.
    if [[ "$(wc -l < "$STACK")" -le 1 ]]; then
        : > "$STACK"
    else
        head -n -1 "$STACK" > "$STACK.tmp" && mv "$STACK.tmp" "$STACK"
    fi
    [[ -n "$app" ]] || exit 0

    # --restore-last-session reliably restores tabs only when the browser was
    # fully closed; with another window still open the running instance ignores
    # it and opens a blank window (use the browser's own Ctrl+Shift+T there).
    case "${app,,}" in
        chromium|chromium-browser|org.chromium.chromium)
            launch chromium --ozone-platform-hint=auto \
                --enable-features=WaylandWindowDecorations \
                --restore-last-session ;;
        google-chrome*|chrome)
            launch google-chrome-stable --ozone-platform-hint=auto \
                --enable-features=WaylandWindowDecorations \
                --restore-last-session ;;
        brave*)
            launch brave --restore-last-session ;;
        *)
            # Best-effort generic relaunch: app_id usually matches a .desktop
            # id; fall back to treating it as a binary via app-launch.
            if command -v gtk-launch >/dev/null 2>&1 && \
               gtk-launch "$app" >/dev/null 2>&1; then
                exit 0
            fi
            launch app-launch "${app,,}" ;;
    esac
}

watch() {
    # Single instance — a duplicate spawn-at-startup just exits.
    exec 9>"$LOCK"
    flock -n 9 || exit 0
    : > "$STACK"

    declare -A APP=()
    while IFS=$'\t' read -r ev id app; do
        case "$ev" in
            reset) APP=() ;;
            set)   [[ -n "$id" ]] && APP["$id"]="$app" ;;
            close)
                local a="${APP[$id]:-}"
                unset "APP[$id]"
                [[ -n "$a" ]] && printf '%s\n' "$a" >> "$STACK"
                ;;
        esac
    done < <(niri msg --json event-stream | jq --unbuffered -rc '
        if .WindowOpenedOrChanged then
            "set\t\(.WindowOpenedOrChanged.window.id)\t\(.WindowOpenedOrChanged.window.app_id // "")"
        elif .WindowsChanged then
            "reset", (.WindowsChanged.windows[] | "set\t\(.id)\t\(.app_id // "")")
        elif .WindowClosed then
            "close\t\(.WindowClosed.id)\t"
        else empty end
    ')
}

case "${1:-watch}" in
    watch)      watch ;;
    pop|reopen) reopen ;;
    *) echo "usage: reopen-window [watch|pop]" >&2; exit 2 ;;
esac
