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

---@class SuffixKeys
---@field run_current?               string    Keymap suffix          (default: "s")
---@field run?                       string    Keymap suffix          (default: "r")
---@field output?                    string    Keymap suffix          (default: "o")

---@class CommandSuffixes
---@field run_file?                  string    Keymap suffix          (default: "WeztermRunFile")
---@field send?                      string    Keymap suffix          (default: "WeztermSend")
---@field output?                    string    Keymap suffix          (default: "WeztermRetrieve")

-- formerly WeztermRunSetupOpts
---@class WeztermRunConfig
---@field direction_keys?            DirectionKeys
---@field create_keymaps?            boolean   Enable default keymaps (default: true)
---@field default_direction          string                           (default: "Right")
---@field prefix                     string    Keymap prefix          (default: "<leader>w")
---@field suffix_keys                SuffixKeys
---@field command_prefixes           CommandPrefixes
---@field file_runners?              table<string, CommandSandwich|RunnerCallback>
---@field repls?                     table<string, ReplInfo>
---@field clipboard                  string                           (default: "wl-clipboard")

---@class WeztermRunConfig
---@field default_direction          Direction Default WezTerm pane direction.
---@field create_keymaps             boolean Automatically bind default keymaps.
---@field create_commands            boolean Automatically create user commands.
---@field direction_keys             table<string, Direction>  Map of key suffixes to directions.
---@field capture                    CaptureMode               Capture strategy mode.
M = {
	direction_keys = direction_keys,
	create_keymaps = true,
	default_direction = "Right",

	prefix = "<leader>w",
	suffix_keys = {
		run_current = "s",
		run_file = "r",
		output = "o",
	},

	command_prefixes = {
		run_file = "WeztermRunFile",
		run_current = "WeztermSend", -- name field `send`?
		retrieve_output = "WeztermRetrieve",
	},

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
