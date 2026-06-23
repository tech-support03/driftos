-- init.lua — entry point.
--
-- Curated from-scratch config (not a distro). Reading order:
--   1. config.options  — editor behaviour (vim.opt)
--   2. config.keymaps  — global keybinds (plugin-specific binds live with
--                        their plugin spec under lua/plugins/)
--   3. lazy.nvim       — bootstrapped below, then loads every spec in
--                        lua/plugins/*.lua
--
-- Leader must be set BEFORE lazy loads so that <leader> mappings in plugin
-- specs resolve correctly.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.keymaps")

-- Bootstrap lazy.nvim (clones itself on first launch; no system package).
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local repo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = { { import = "plugins" } },
	install = { colorscheme = { "catppuccin" } },
	checker = { enabled = false }, -- don't auto-check for updates; run :Lazy update by hand
	change_detection = { notify = false },
	ui = { border = "rounded" },
})
