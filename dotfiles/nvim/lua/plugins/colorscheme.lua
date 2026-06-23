-- Colorscheme: Catppuccin Mocha. Dark-only (matches the rice's no-light-theme
-- rule) and its lavender hue sits right next to the rice accent #c5b3ff, so the
-- editor reads as part of the same desktop. priority 1000 loads it before any
-- other UI plugin can paint with the wrong palette.
return {
	"catppuccin/nvim",
	name = "catppuccin",
	lazy = false,
	priority = 1000,
	opts = {
		flavour = "mocha",
		transparent_background = false, -- alacritty already provides translucency
		integrations = {
			gitsigns = true,
			treesitter = true,
			telescope = true,
			which_key = true,
			blink_cmp = true,
			mason = true,
			native_lsp = { enabled = true },
		},
	},
	config = function(_, opts)
		require("catppuccin").setup(opts)
		vim.cmd.colorscheme("catppuccin")
	end,
}
