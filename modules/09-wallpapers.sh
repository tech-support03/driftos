#!/usr/bin/env bash
# 09-wallpapers.sh — populate wallpaper directory with sample paths via swww.
set -Eeuo pipefail

WP_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WP_DIR"

# Five diverse high-quality samples (CC0 / unsplash-hosted; download once, idempotent).
declare -A WALLS=(
    [01-dark-mountain.jpg]="https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=3840&q=90"
    [02-deep-purple-nebula.jpg]="https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=3840&q=90"
    [03-aurora-fjord.jpg]="https://images.unsplash.com/photo-1483728642387-6c3bdd6c93e5?w=3840&q=90"
    [04-warm-desert-dunes.jpg]="https://images.unsplash.com/photo-1547235001-d703406d3a5a?w=3840&q=90"
    [05-foggy-pine-forest.jpg]="https://images.unsplash.com/photo-1448375240586-882707db888b?w=3840&q=90"
)

for name in "${!WALLS[@]}"; do
    target="$WP_DIR/$name"
    if [[ ! -s "$target" ]]; then
        log "downloading wallpaper: $name"
        curl -fL --retry 3 -o "$target.part" "${WALLS[$name]}" && mv "$target.part" "$target" || \
            warn "failed to download $name (will skip)"
    fi
done

# Drop a wallpaper rotation/init script the niri config calls at startup.
install -Dm755 "$SCRIPTS_DIR/wallpaper-init.sh" "$HOME/.local/bin/wallpaper-init"

# Seed regreet's login-screen wallpaper from whichever was downloaded first.
# Falls back silently if every download failed (e.g. no network on first run).
first_wp="$(find "$WP_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -n1)"
if [[ -n "$first_wp" ]]; then
    sudo install -Dm644 "$first_wp" /var/lib/regreet/wallpaper.jpg
    ok "regreet login wallpaper seeded from $(basename "$first_wp")"
fi

ok "wallpapers staged at $WP_DIR"
