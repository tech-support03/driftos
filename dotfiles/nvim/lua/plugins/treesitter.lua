-- Treesitter: parser-driven syntax highlighting + indentation. Far more
-- accurate than regex highlighting and powers the textobjects below.
-- Parsers compile on install via the C toolchain from base-devel.
return {
	"nvim-treesitter/nvim-treesitter",
	build = ":TSUpdate",
	event = { "BufReadPost", "BufNewFile" },
	main = "nvim-treesitter.configs",
	opts = {
		-- Languages likely on this box (Arch dotfiles, scripts, web mockup).
		ensure_installed = {
			"lua", "vim", "vimdoc", "bash", "python", "c",
			"markdown", "markdown_inline", "json", "jsonc", "yaml",
			"toml", "html", "css", "javascript", "kdl", "diff", "gitcommit",
		},
		auto_install = true, -- grab a parser the first time you open an unknown filetype
		highlight = { enable = true },
		indent = { enable = true },
		incremental_selection = {
			enable = true,
			keymaps = {
				init_selection = "<CR>",
				node_incremental = "<CR>",
				node_decremental = "<BS>",
			},
		},
	},
}
