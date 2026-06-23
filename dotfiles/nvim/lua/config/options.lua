-- config/options.lua — core editor behaviour. Plain vim.opt, no plugins.

local opt = vim.opt

-- Line numbers: absolute on the current line, relative elsewhere (fast motions).
opt.number = true
opt.relativenumber = true

-- Use the system clipboard for all yank/paste. wl-clipboard (installed by the
-- base package list) is the Wayland provider neovim auto-detects.
opt.clipboard = "unnamedplus"

opt.mouse = "a" -- mouse works in all modes (resize splits, scroll, select)
opt.termguicolors = true -- 24-bit colour; required by the catppuccin theme
opt.signcolumn = "yes" -- always show the sign gutter so text doesn't jump

-- Indentation: 4-space tabs by default. Treesitter / ftplugins narrow this per
-- language (e.g. 2 for lua/yaml) where it matters.
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true
opt.breakindent = true -- wrapped lines keep their indent

-- Search: case-insensitive unless you type a capital, highlight as you go.
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

-- Splits open where you expect (to the right / below).
opt.splitright = true
opt.splitbelow = true

opt.scrolloff = 8 -- keep 8 lines of context above/below the cursor
opt.sidescrolloff = 8
opt.cursorline = true
opt.wrap = false

-- Persistent undo: history survives closing a file.
opt.undofile = true
opt.swapfile = false

opt.updatetime = 250 -- faster CursorHold (diagnostics, gitsigns) — default 4000
opt.timeoutlen = 400 -- which-key popup delay
opt.confirm = true -- prompt to save instead of failing on :q with unsaved changes

-- Show whitespace that matters; nicer fillchars.
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Live substitute preview in a split.
opt.inccommand = "split"
