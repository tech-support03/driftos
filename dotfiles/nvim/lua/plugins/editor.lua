-- Small quality-of-life plugins grouped together: file explorer, git gutter,
-- statusline, keybind hints, and autopairs.
return {
	-- Oil: edit the filesystem like a normal buffer (a vim-native feel — no
	-- separate tree pane to manage). `-` opens the parent directory.
	{
		"stevearc/oil.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		lazy = false, -- so it can hijack netrw when you open a directory at startup
		opts = {
			default_file_explorer = true,
			view_options = { show_hidden = true },
		},
		keys = {
			{ "-", "<cmd>Oil<CR>", desc = "Open parent directory" },
		},
	},

	-- Gitsigns: signs in the gutter for added/changed/removed lines, plus
	-- hunk navigation and inline blame.
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			on_attach = function(buf)
				local gs = require("gitsigns")
				local function m(keys, fn, desc)
					vim.keymap.set("n", keys, fn, { buffer = buf, desc = "Git: " .. desc })
				end
				m("]c", function() gs.nav_hunk("next") end, "Next hunk")
				m("[c", function() gs.nav_hunk("prev") end, "Prev hunk")
				m("<leader>gp", gs.preview_hunk, "Preview hunk")
				m("<leader>gb", gs.blame_line, "Blame line")
				m("<leader>gr", gs.reset_hunk, "Reset hunk")
			end,
		},
	},

	-- Lualine: a clean statusline themed to catppuccin.
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		opts = {
			options = {
				theme = "catppuccin",
				section_separators = "",
				component_separators = "|",
				globalstatus = true,
			},
		},
	},

	-- which-key: pops up a cheatsheet of available binds after you press a
	-- prefix (e.g. <leader>). Invaluable while learning a new set of keymaps.
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			spec = {
				{ "<leader>f", group = "find" },
				{ "<leader>g", group = "git" },
				{ "<leader>b", group = "buffer" },
			},
		},
	},

	-- Autopairs: closes brackets/quotes as you type.
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {},
	},
}
