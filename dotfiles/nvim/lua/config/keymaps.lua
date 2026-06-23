-- config/keymaps.lua — global keybinds. Leader is <Space> (set in init.lua).
-- Plugin-specific binds (Telescope, Oil, LSP) live in their own specs so the
-- bind and the feature stay together.

local map = vim.keymap.set

-- Clear search highlight with <Esc>.
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Save / quit.
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "Quit window" })

-- Window navigation with Ctrl + hjkl (works alongside niri's own tiling binds —
-- these only move focus *inside* a single neovim instance).
map("n", "<C-h>", "<C-w>h", { desc = "Focus window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Focus window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Focus window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Focus window right" })

-- Buffer cycling.
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

-- Move selected lines up/down, keeping selection and re-indenting.
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Keep the cursor centred when half-page scrolling and jumping search results.
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Stay in visual mode after indenting.
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Paste over a selection without clobbering the unnamed register.
map("x", "<leader>p", [["_dP]], { desc = "Paste without yanking selection" })

-- Diagnostics: open the floating message / location list.
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, { desc = "Prev diagnostic" })
map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, { desc = "Next diagnostic" })

-- Highlight on yank — a tiny visual confirmation of what got copied.
vim.api.nvim_create_autocmd("TextYankPost", {
	group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
	callback = function() vim.highlight.on_yank() end,
})
