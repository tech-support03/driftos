# nvim

Curated from-scratch Neovim config. Lua, managed by **lazy.nvim** (which
bootstraps itself on first launch — no extra system package). Leader is
`<Space>`.

## Layout

```
init.lua                      bootstrap lazy, load options/keymaps, load plugins
lua/config/options.lua        editor behaviour (vim.opt)
lua/config/keymaps.lua        global keybinds + yank-highlight autocmd
lua/plugins/colorscheme.lua   catppuccin-mocha (lavender, matches rice accent)
lua/plugins/treesitter.lua    parser-driven highlighting/indent
lua/plugins/lsp.lua           mason + lspconfig (lua_ls, bashls by default)
lua/plugins/completion.lua    blink.cmp (prebuilt binary, no Rust toolchain)
lua/plugins/telescope.lua     fuzzy finder (ripgrep + fd + fzf-native)
lua/plugins/editor.lua        oil, gitsigns, lualine, which-key, autopairs
```

Plugins are pinned by `lazy-lock.json` (committed after first launch) so a
reinstall restores the exact same versions — same philosophy as the rest of
this repo.

## Key binds (beyond stock vim)

| Bind | Action |
|---|---|
| `<Space>` | leader |
| `<leader>w` / `<leader>q` | save / quit |
| `<leader><leader>` / `<leader>ff` | find files (Telescope) |
| `<leader>fg` | live grep |
| `<leader>fb` / `<leader>fr` | buffers / recent files |
| `<leader>fd` | diagnostics |
| `-` | open parent dir (Oil file browser) |
| `gd` / `gr` / `gI` | LSP definition / references / implementation |
| `K` | hover docs |
| `<leader>rn` / `<leader>ca` | rename symbol / code action |
| `<leader>e` · `[d` / `]d` | line diagnostic · prev/next diagnostic |
| `[c` / `]c` · `<leader>gp` / `<leader>gb` | prev/next hunk · preview / blame |
| `<C-h/j/k/l>` | focus split (inside one nvim) |
| `<S-h>` / `<S-l>` | prev / next buffer |
| `<CR>` / `<BS>` (normal) | grow / shrink treesitter selection |

Forget a bind? Press `<Space>` and wait — **which-key** shows the menu.

## First launch

Open `nvim` once with a network connection: lazy clones itself and the plugins,
Treesitter compiles its parsers, and mason downloads `lua_ls` / `bashls`. Run
`:checkhealth` afterwards to confirm everything resolved.
