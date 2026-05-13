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

# Waybar (top + side panel use separate config dirs, launched explicitly)
link "$DOTFILES_DIR/waybar-top"                 "$HOME/.config/waybar-top"
link "$DOTFILES_DIR/waybar-side"                "$HOME/.config/waybar-side"

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

# Scripts → ~/.local/bin (in PATH for most shells via XDG)
mkdir -p "$HOME/.local/bin"
for s in "$SCRIPTS_DIR"/*.sh; do
    name="$(basename "$s")"
    install -m755 "$s" "$HOME/.local/bin/${name%.sh}"
    ok "installed script: ${name%.sh}"
done

ok "dotfiles linked"
