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

# Pick the first downloaded wallpaper for both regreet login + lock screen.
# Falls back silently if every download failed (e.g. no network).
first_wp="$(find "$WP_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -n1)"

if [[ -n "$first_wp" ]]; then
    # Pre-blur the wallpaper for swaylock so the lock screen looks riced
    # without depending on live GL effects (which fail in VMs without 3D
    # acceleration). ImageMagick's `-blur 0x18` matches the swaylock-effects
    # `effect-blur=18x4` aesthetic closely.
    log "pre-blurring lock-screen background"
    sudo install -d -m 0755 /var/lib/lockscreen
    if command -v magick >/dev/null 2>&1; then
        sudo magick "$first_wp" -resize 1920x1080^ -gravity center -extent 1920x1080 \
            -blur 0x18 -modulate 85,90 /var/lib/lockscreen/bg.jpg
    elif command -v convert >/dev/null 2>&1; then
        sudo convert "$first_wp" -resize 1920x1080^ -gravity center -extent 1920x1080 \
            -blur 0x18 -modulate 85,90 /var/lib/lockscreen/bg.jpg
    else
        warn "no ImageMagick — copying unblurred wallpaper as lock background"
        sudo install -Dm644 "$first_wp" /var/lib/lockscreen/bg.jpg
    fi
    ok "lock-screen background written to /var/lib/lockscreen/bg.jpg"
fi

ok "wallpapers staged at $WP_DIR"
