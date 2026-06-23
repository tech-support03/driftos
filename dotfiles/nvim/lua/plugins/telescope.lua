-- Telescope: fuzzy finder for files, live grep, buffers, help, diagnostics.
-- Uses ripgrep + fd (already in the base package list). fzf-native is a small
-- C extension compiled with make (base-devel) for much faster sorting.
return {
	"nvim-telescope/telescope.nvim",
	cmd = "Telescope",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
	},
	keys = {
		{ "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
		{ "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live grep" },
		{ "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
		{ "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help tags" },
		{ "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "Recent files" },
		{ "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Diagnostics" },
		{ "<leader>fw", "<cmd>Telescope grep_string<CR>", desc = "Grep word under cursor" },
		{ "<leader><leader>", "<cmd>Telescope find_files<CR>", desc = "Find files" },
	},
	config = function()
		local telescope = require("telescope")
		telescope.setup({
			defaults = {
				layout_strategy = "horizontal",
				layout_config = { prompt_position = "top" },
				sorting_strategy = "ascending",
				path_display = { "truncate" },
			},
		})
		pcall(telescope.load_extension, "fzf")
	end,
}
