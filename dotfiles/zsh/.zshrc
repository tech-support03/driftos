# ~/.zshrc — interactive zsh for the rice. Linked from dotfiles/zsh/.zshrc by
# 08-link-dotfiles.sh. The headline feature is fish-style autocomplete:
# grey inline suggestions (zsh-autosuggestions) + as-you-type syntax colours
# (zsh-syntax-highlighting) + zsh's menu completion fleshed out by
# zsh-completions. Packages come from 01-base-packages.sh.

# ~/.local/bin on PATH — interactive scripts (rice-profile, wallpaper-next,
# etc.) are installed there by 08-link-dotfiles.sh. Set before the interactive
# guard so it always applies. Guard against double-prepend on nested shells.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Skip the rest for non-interactive shells (scp, scripts sourcing this, etc.).
[[ $- == *i* ]] || return

# ── History ──────────────────────────────────────────────────────────────
# Autosuggestions pull from history, so a generous, deduped, shared history
# makes the grey suggestions far more useful.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY        # timestamp each entry
setopt INC_APPEND_HISTORY      # write as you go, not just on exit
setopt SHARE_HISTORY           # share across live sessions
setopt HIST_IGNORE_ALL_DUPS    # collapse duplicate commands
setopt HIST_IGNORE_SPACE       # a leading space hides the command from history
setopt HIST_REDUCE_BLANKS

# ── Navigation / quality-of-life ──────────────────────────────────────────
setopt AUTO_CD                 # `..` / a bare dir name cd's into it
setopt AUTO_PUSHD              # cd maintains a directory stack
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS    # allow # comments at the prompt

# ── Completion (the "tab" half of autocomplete) ───────────────────────────
# zsh-completions installs extra compdef functions into a site-functions dir
# that is already on $fpath via the package; just init the completion system.
autoload -Uz compinit
# Cache the dump so new shells start fast; rebuild at most once a day.
_zcompdump="$HOME/.cache/zsh/zcompdump-$ZSH_VERSION"
mkdir -p "${_zcompdump:h}"
if [[ -n $_zcompdump(#qN.mh+24) ]]; then
    compinit -d "$_zcompdump"
else
    compinit -C -d "$_zcompdump"
fi

zstyle ':completion:*' menu select                      # arrow-key menu
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}   # colourised matches
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{#5b6ee0}%d%f'  # accent headers
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END

# ── Autosuggestions (the grey inline "ghost text") ────────────────────────
# Source order matters: autosuggestions before syntax-highlighting.
_autosuggest=/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
if [[ -r $_autosuggest ]]; then
    source "$_autosuggest"
    # Suggestion colour = Theme.qml fg2 (#8e8e96) so it matches the rice.
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#8e8e96'
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    # → / End accept the whole suggestion (zsh default forward-char binds to
    # the widget); Ctrl-→ / Alt-f accept one word at a time.
    bindkey '^[[1;5C' forward-word                 # Ctrl-→ : accept a word
    bindkey '^ '      autosuggest-accept           # Ctrl-Space : accept all
fi

# ── Syntax highlighting (must be sourced LAST per upstream docs) ──────────
_syntax=/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ── Tooling already installed in 01-base-packages.sh ──────────────────────
# fzf history search (Ctrl-R) + path completion; zoxide smart cd; eza/bat as
# nicer ls/cat. These lean on packages the rice already ships, no new deps.
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

alias ls='eza --group-directories-first --icons=auto'
alias ll='eza -l --group-directories-first --icons=auto --git'
alias la='eza -la --group-directories-first --icons=auto --git'
alias cat='bat --paging=never'
alias grep='grep --color=auto'
# `new` — clear the screen and reprint the fastfetch banner (ported from bash).
alias new='clear && fastfetch'

# ── Prompt (Powerline / agnoster style) ───────────────────────────────────
# Segmented blocks with triangle separators + a pink→teal rainbow tail, like
# the reference screenshot. NEEDS A NERD FONT for the glyphs — alacritty uses
# JetBrains Mono Nerd Font (01-base-packages.sh), so they render. The `@` in
# user@host is a `|` per request.  is the powerline separator (U+E0B0),
#  is the Arch logo (U+F303).
#
# Each separator's foreground = the segment it trails, painted on the next
# segment's background — that's what makes the blocks interlock.
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats '%b'
precmd() { vcs_info }
setopt PROMPT_SUBST

# Built in an anonymous function so the palette vars stay local; only PROMPT
# (assigned without `local`) escapes to the global scope.
() {
    local sep=$'' icon=$''   #
    local fg='#f4f4f6'                   # light text — readable on the dark blocks
    local seg1='#5b6ee0' seg2='#3d4bb8'  # user|host , directory  (indigo/blue)
    # short tail, blue → cyan → teal (no pink)
    local g1='#4f8fe6' g2='#3fc0d6' g3='#37d6b8'

    PROMPT="%K{$seg1}%F{$fg} $icon %n|%m %f"          # icon + user|host
    PROMPT+="%K{$seg2}%F{$seg1}$sep%f"                  #  seg1 → seg2
    PROMPT+="%K{$seg2}%F{$fg} %~ %f"                   # directory
    PROMPT+="%K{$g1}%F{$seg2}$sep%f"                    #  seg2 → tail
    PROMPT+="%K{$g2}%F{$g1}$sep%f"
    PROMPT+="%K{$g3}%F{$g2}$sep%f"
    PROMPT+="%k%F{$g3}$sep%f "                           # close to terminal bg
}

# Syntax highlighting sourced here, last, after all other widgets/bindings.
[[ -r $_syntax ]] && source "$_syntax"

# ── Greeting ──────────────────────────────────────────────────────────────
# fastfetch on every new interactive terminal (ported from bash). `new`
# reprints it. Only when stdout is a tty, so it stays out of piped/captured
# zsh invocations.
[[ -t 1 ]] && command -v fastfetch >/dev/null && fastfetch
