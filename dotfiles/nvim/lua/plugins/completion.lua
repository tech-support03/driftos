-- Completion: blink.cmp — a single batteries-included engine (sources, fuzzy
-- matcher, signature help, snippets). Pinned to a release tag so lazy pulls the
-- prebuilt fuzzy-matcher binary instead of needing a Rust toolchain to build it.
return {
	"saghen/blink.cmp",
	version = "1.*",
	event = "InsertEnter",
	dependencies = { "rafamadriz/friendly-snippets" },
	opts = {
		keymap = {
			preset = "default", -- <C-y> accept, <C-n>/<C-p> cycle, <C-space> open
			["<CR>"] = { "accept", "fallback" },
			["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
			["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
		},
		appearance = { nerd_font_variant = "mono" }, -- JetBrains Mono Nerd Font is installed
		completion = {
			documentation = { auto_show = true, auto_show_delay_ms = 200 },
			menu = { border = "rounded" },
		},
		signature = { enabled = true },
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
	},
}
