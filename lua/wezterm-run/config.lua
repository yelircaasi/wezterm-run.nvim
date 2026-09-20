---@enum DirectionKeys
local direction_keys = {
	h = "Left",
	l = "Right",
	j = "Down",
	k = "Up",
	n = "Next",
	p = "Prev",
}

---@class CommandSandwich
---@field prefix? string
---@field suffix? string

---@class ReplInfo
---@field command? string    Command used to start the REPL when opening a new pane.
---@field pattern? string    Lua pattern or substring used to match against pane title when no direction is specified.

---@alias RunnerCallback fun():str

---@class WeztermRunSetupOpts
---@field direction_keys?            DirectionKeys
---@field create_keymaps?            boolean   Enable default keymaps (default: true)
---@field default_direction          string                           (default: "Right")
---@field prefix?                    string    Keymap prefix          (default: "<leader>w")
---@field suffix_key_run_current?    string    Keymap suffix          (default: "s")
---@field suffix_key_run?            string    Keymap suffix          (default: "r")
---@field suffix_key_output?         string    Keymap suffix          (default: "o")
---@field file_runners?              table<string, CommandSandwich|RunnerCallback>
---@field repls?                     table<string, ReplInfo>
---@field clipvoard                  string                           (default: "wl-clipboard")
M = {
	direction_keys = direction_keys,
	create_keymaps = true,
	default_direction = "Right",

	prefix = "<leader>w",
	suffix_key_run_current = "s",
	suffix_key_run_file = "r",
	suffix_key_output = "o",

	command_prefix_run_current = "WeztermSend",
	command_prefix_run_file = "WeztermRunFile",
	command_prefix_output = "WeztermRetrieve",

	capture = "explicit", -- "auto" | "explicit" | "none"
	capture_target = "clipboard", -- "clipboard" | "scratch" | "quickfix"
	file_runners = {
		python = { prefix = "python3", suffix = "" },
		lua = { prefix = "lua", suffix = "" },
		javascript = { prefix = "node", suffix = "" },
		typescript = { prefix = "npx ts-node", suffix = "" },
		rust = { prefix = "cargo run --manifest-path", suffix = "" },
		haskell = { prefix = "runghc", suffix = "" },
		sh = { prefix = "sh", suffix = "" },
		bash = { prefix = "bash", suffix = "" },
		ruby = { prefix = "ruby", suffix = "" },
	},
	repls = {},
	clipboard = "wl-clipboard",

	include_ansi_codes = false,
}

return M
