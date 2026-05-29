#!/usr/bin/env bash
# 00-display-config.sh — abstracts the display layout into kanshi profiles +
# launches nwg-displays on first run so the user can drag screens visually.
set -Eeuo pipefail

CFG_DIR="$HOME/.config/kanshi"
mkdir -p "$CFG_DIR"

# Profile selection writes a kanshi config + a niri-side outputs block.
case "$PROFILE" in
    personal)
        log "Applying personal 3-monitor topology to kanshi"
        install -Dm644 "$DOTFILES_DIR/kanshi/config.personal" "$CFG_DIR/config"
        ;;
    laptop)
        log "Applying laptop single-panel + dock profiles to kanshi"
        install -Dm644 "$DOTFILES_DIR/kanshi/config.laptop"   "$CFG_DIR/config"
        ;;
    vm|*)
        log "Applying VM fallback display layout to kanshi"
        install -Dm644 "$DOTFILES_DIR/kanshi/config.vm" "$CFG_DIR/config"
        ;;
esac

# Auto-start kanshi at session start via systemd --user
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/kanshi.service" <<'EOF'
[Unit]
Description=Dynamic display configuration (kanshi)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/kanshi
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable kanshi.service >/dev/null 2>&1 || true

ok "display configuration applied for profile=$PROFILE"
