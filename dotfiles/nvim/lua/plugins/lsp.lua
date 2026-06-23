-- LSP: the headline reason to switch from vim. mason.nvim installs language
-- servers into neovim's own data dir (self-contained — no pacman packages),
-- mason-lspconfig bridges them to nvim-lspconfig, and the LspAttach autocmd
-- wires the keybinds only on buffers that actually have a server.
return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		{ "williamboman/mason.nvim", opts = {} },
		{ "williamboman/mason-lspconfig.nvim" },
		-- Surfaces mason / lazy progress in the bottom-right while servers load.
		{ "j-hui/fidget.nvim", opts = {} },
	},
	config = function()
		-- Keybinds attach per-buffer once a server connects.
		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("lsp_attach", { clear = true }),
			callback = function(event)
				local function m(keys, fn, desc)
					vim.keymap.set("n", keys, fn, { buffer = event.buf, desc = "LSP: " .. desc })
				end
				m("gd", vim.lsp.buf.definition, "Go to definition")
				m("gr", vim.lsp.buf.references, "References")
				m("gI", vim.lsp.buf.implementation, "Go to implementation")
				m("K", vim.lsp.buf.hover, "Hover docs")
				m("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
				m("<leader>ca", vim.lsp.buf.code_action, "Code action")
				m("<leader>D", vim.lsp.buf.type_definition, "Type definition")
			end,
		})

		-- Servers to install automatically. lua_ls makes editing this config
		-- pleasant; bashls covers the install scripts. Add more here or with
		-- :Mason on demand.
		require("mason-lspconfig").setup({
			ensure_installed = { "lua_ls", "bashls" },
		})

		-- Tell lua_ls that `vim` is a global so it stops warning in configs.
		vim.lsp.config("lua_ls", {
			settings = {
				Lua = {
					diagnostics = { globals = { "vim" } },
					workspace = { checkThirdParty = false },
				},
			},
		})
	end,
}
