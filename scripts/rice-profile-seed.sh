#!/usr/bin/env bash
# rice-profile-seed — run once at niri startup (spawn-at-startup, BEFORE
# quickshell) to pick the initial visual profile from the kernel command line:
#
#     ...  rice.profile=light      → light profile
#     ...  rice.profile=full       → full profile
#     (absent)                     → keep an existing choice, else default full
#
# This is what makes the MacBook's GRUB entry ("driftOS — light") come up light
# automatically while the laptop's "full" entry comes up full, with no manual
# step on first boot. After that, `rice-profile` (Mod+Shift+P) overrides live
# and persists, and a later boot WITHOUT rice.profile= on the cmdline respects
# that saved choice rather than resetting it.
set -Eeuo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_FILE="$CFG/rice/profile"

# Parse rice.profile= from the kernel cmdline (last occurrence wins).
cmdline_profile() {
    local tok val=""
    for tok in $(cat /proc/cmdline 2>/dev/null); do
        case "$tok" in
            rice.profile=light) val=light ;;
            rice.profile=full)  val=full ;;
        esac
    done
    printf '%s' "$val"
}

want="$(cmdline_profile)"

if [[ -z "$want" ]]; then
    # No cmdline directive. Respect a previously saved choice; only default to
    # full if nothing has ever been set.
    if [[ -r "$STATE_FILE" ]]; then
        exit 0
    fi
    want=full
fi

# Delegate the actual switch (niri regen + state write) to rice-profile so there
# is exactly one code path that knows how to apply a profile.
exec rice-profile "$want"
