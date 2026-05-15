#!/usr/bin/env bash
# 08-link-dotfiles.sh — symlink dotfiles into ~/.config (idempotent).
set -Eeuo pipefail

link() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" || -e "$dst" ]]; then
        if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
            return 0
        fi
        local bak="${dst}.bak.$(date +%s)"
        warn "backing up existing $dst → $bak"
        mv "$dst" "$bak"
    fi
    ln -s "$src" "$dst"
    ok "linked $dst"
}

# Niri compositor
link "$DOTFILES_DIR/niri/config.kdl"            "$HOME/.config/niri/config.kdl"

# Side panel = waybar; top bar = quickshell (Caelestia-style hover dashboard)
link "$DOTFILES_DIR/waybar-side"                "$HOME/.config/waybar-side"
link "$DOTFILES_DIR/quickshell"                 "$HOME/.config/quickshell"

# Side terminal, launcher, notifications, audio visualizer
link "$DOTFILES_DIR/foot/foot.ini"              "$HOME/.config/foot/foot.ini"
link "$DOTFILES_DIR/fuzzel/fuzzel.ini"          "$HOME/.config/fuzzel/fuzzel.ini"
link "$DOTFILES_DIR/mako/config"                "$HOME/.config/mako/config"
link "$DOTFILES_DIR/cava/config"                "$HOME/.config/cava/config"
link "$DOTFILES_DIR/fastfetch/config.jsonc"     "$HOME/.config/fastfetch/config.jsonc"
link "$DOTFILES_DIR/swaylock/config"            "$HOME/.config/swaylock/config"

# Regreet runs as the `greeter` user, so its config must live under
# /etc/greetd, not the user's home. Copy (not symlink) so the greeter user
# can read it without traversing the user's homedir.
log "Installing regreet config to /etc/greetd"
sudo install -Dm644 "$DOTFILES_DIR/regreet/regreet.toml" /etc/greetd/regreet.toml
sudo install -Dm644 "$DOTFILES_DIR/regreet/regreet.css"  /etc/greetd/regreet.css

# Scripts → both ~/.local/bin (interactive shell) AND /usr/local/bin (every
# PAM/systemd session). niri's spawn-at-startup uses bare names like
# `wallpaper-init` and `power-menu`; those resolve via the session PATH which
# greetd/login(1) bootstraps from /etc/profile, and that path does NOT
# include ~/.local/bin on Arch. Installing to /usr/local/bin (which IS in
# the default PATH) means niri can always find them.
mkdir -p "$HOME/.local/bin"
for s in "$SCRIPTS_DIR"/*.sh; do
    name="$(basename "$s")"
    install -m755 "$s" "$HOME/.local/bin/${name%.sh}"
    sudo install -m755 "$s" "/usr/local/bin/${name%.sh}"
    ok "installed script: ${name%.sh}"
done

# Fail loudly if the linked niri config doesn't parse on the installed niri
# version. Without this, parse errors only surface when the user logs in via
# greetd, which then bounces them straight back to the greeter — a confusing
# loop to debug from a cold install.
if command -v niri >/dev/null 2>&1; then
    log "Validating niri config against installed niri"
    # `niri validate` (no args) reads the user's default config location, which
    # is the symlink we just placed at ~/.config/niri/config.kdl. Long-form
    # --config is supported on all niri versions; -c is not.
    if ! niri validate >/tmp/niri-validate.log 2>&1; then
        warn "niri config failed to validate:"
        sed 's/^/    /' /tmp/niri-validate.log
        warn "Fix dotfiles/niri/config.kdl and re-run install.sh."
        exit 1
    fi
    ok "niri config validates"
fi

ok "dotfiles linked"
