---@tag wezterm-run.nvim
---@config
---@brief [[
--- `wezterm-run.nvim` provides integration between Neovim and WezTerm, allowing
--- sending selections, code nodes, running files, and retrieving buffer output.
---]]

local toplevel_functions = require("wezterm-run.toplevel")
local helpers = require("wezterm-run.helpers")

local map = vim.keymap.set
local _notify = print -- vim.notify

---@type Direction[]
local pane_directions = { "left", "right", "up", "down", "next", "prev" }

-------------------------------------------------------------------------------
-- Types & Annotations
-------------------------------------------------------------------------------

---@alias Direction "left" | "right" | "up" | "down" | "next" | "prev" | "Left" | "Right" | "Up" | "Down" | "Next" | "Prev"
---@alias CaptureMode "auto" | "explicit"

---@class WeztermRunOpts
---@field direction?          Direction  Target pane direction.
---@field pick?               boolean    Prompt user to pick pane visually if true.
---@field include_ansi_codes? boolean    Preserve ANSI escape sequences when retrieving output.
---@field pattern?            string     Optional search or match pattern.

---@class WeztermRunModule
---@field opts                WeztermRunConfig   Active plugin configuration options.
local M = {}
M.opts = require("wezterm-run.config")

---Helper to merge user configuration with defaults.
---@param opts? WeztermRunOpts
---@return WeztermRunOpts
local function with_defaults(opts)
	print("CALLING with_defaults")
	return helpers.merge_opts(M.opts, opts or {})
end

-------------------------------------------------------------------------------
-- Internal Keymap Generators
-------------------------------------------------------------------------------

---@param key           string     Key mapping trigger suffix.
---@param direction     Direction  Direction to send to.
---@param keymap_prefix string     Full prefix string.
local function map_run_current(key, direction, keymap_prefix)
	print("CALLING map_run_current")
	local sequence = keymap_prefix .. key
	print("Mapping sequence " .. sequence)
	local direction_lower = string.lower(direction)
	local send_opts = { direction = helpers.as_title(direction) }

	-- Visual mode: send selection
	map("v", sequence, function()
		M.send_selection(send_opts)
	end, { desc = "Send selection: WezTerm pane (" .. direction_lower .. ")" })

	-- Normal mode: send treesitter node / code block
	map("n", sequence, function()
		M.send_node(send_opts)
	end, { desc = "Send current block: WezTerm pane (" .. direction_lower .. ")" })
end

---@param key            string
---@param direction      Direction
---@param keymap_prefix  string
local function map_run_file(key, direction, keymap_prefix)
	print("CALLING map_run_file")
	local sequence = keymap_prefix .. key
	local direction_lower = string.lower(direction)

	map("n", sequence, function()
		M.run_current_file({ direction = direction })
	end, { desc = "Run current file: WezTerm pane (" .. direction_lower .. ")" })
end

---@param key            string
---@param direction      Direction
---@param keymap_prefix  string
local function map_retrieve_output(key, direction, keymap_prefix)
	print("CALLING map_retrieve_output")
	local sequence = keymap_prefix .. key
	local direction_lower = string.lower(direction)

	map("n", sequence, function()
		M.retrieve_and_deliver({ direction = helpers.as_title(direction) })
	end, { desc = "Retrieve output: WezTerm pane (" .. direction_lower .. ")" })
end

-------------------------------------------------------------------------------
-- Command Registration
-------------------------------------------------------------------------------

local function create_user_commands()
	-- WeztermSend
	if M.opts.command_prefixes.run_current then
		vim.api.nvim_create_user_command(M.opts.command_prefixes.run_current, function(cmd_opts)
			local raw_dir = cmd_opts.args ~= "" and cmd_opts.args or M.opts.default_direction
			if not raw_dir then
				_notify("wezterm-run: no direction specified", vim.log.levels.WARN)
				return
			end
			local direction = helpers.as_title(raw_dir)

			if cmd_opts.range > 0 then
				M.send_selection({ direction = direction })
			else
				M.send_node({ direction = direction })
			end
		end, {
			range = true,
			nargs = "?",
			complete = function()
				return pane_directions
			end,
		})
	end

	-- WeztermRunFile
	if M.opts.command_prefixes.run_file then
		vim.api.nvim_create_user_command(M.opts.command_prefixes.run_file, function()
			M.run_current_file()
		end, {})
	end

	-- WeztermRetrieve
	if M.opts.command_prefixes.retrieve_output then
		vim.api.nvim_create_user_command(M.opts.command_prefixes.retrieve_output, function(cmd_opts)
			local args = vim.split(cmd_opts.args, "%s+", { trimempty = true })
			---@type WeztermRunOpts
			local local_opts = {}

			for _, arg in ipairs(args) do
				if arg:lower() == "ansi" then
					local_opts.include_ansi_codes = true
				elseif vim.tbl_contains(pane_directions, arg:lower()) then
					local_opts.direction = helpers.as_title(arg)
				end
			end

			M.retrieve_and_deliver(local_opts)
		end, {
			nargs = "*",
			complete = function(arg_lead)
				local candidates = vim.list_extend({ "ansi" }, pane_directions)
				return vim.tbl_filter(function(c)
					return c:find(arg_lead, 1, true) == 1
				end, candidates)
			end,
		})
	end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

---Send custom string to a target WezTerm pane.
---@param text   string
---@param opts?  WeztermRunOpts
function M.send_text(text, opts)
	print("CALLING M.send_text")
	return toplevel_functions.send_text(text, with_defaults(opts))
end

---Send visual selection to a target WezTerm pane.
---@param opts?  WeztermRunOpts
function M.send_selection(opts)
	print("CALLING M.send_selection")
	return toplevel_functions.send_selection(with_defaults(opts))
end

---Send current Treesitter node/block to a target WezTerm pane.
---@param opts?  WeztermRunOpts
function M.send_node(opts)
	print("CALLING M.send_node")
	return toplevel_functions.send_node(with_defaults(opts))
end

---Execute the current buffer file in a target WezTerm pane.
---@param opts?  WeztermRunOpts
function M.run_current_file(opts)
	print("CALLING M.run_current_file")
	return toplevel_functions.run_current_file(with_defaults(opts))
end

---Build command string for running the current file.
---@param opts?  WeztermRunOpts
---@return       string
function M.make_current_file_command(opts)
	print("CALLING M.make_current_file_command")
	return toplevel_functions.make_current_file_command(with_defaults(opts))
end

---Retrieve stdout text from a WezTerm target pane.
---@param opts?  WeztermRunOpts
---@return       string?
function M.retrieve_output(opts)
	print("CALLING M.retrieve_output")
	return toplevel_functions.retrieve_output(with_defaults(opts))
end

---Fetch output from target pane and insert/deliver into current buffer.
---@param opts?  WeztermRunOpts
function M.retrieve_and_deliver(opts)
	print("CALLING M.retrieve_and_deliver")
	return toplevel_functions.retrieve_and_deliver(with_defaults(opts))
end

---Open a dedicated scratchpad buffer for terminal outputs.
M.open_scratch = toplevel_functions.open_scratch

---Setup function to initialize plugin options, keymaps, and commands.
---@param config?  WeztermRunConfig  User configuration options.
function M.setup(config)
	print("CALLING M.setup")
	if not toplevel_functions.is_wezterm() then
		_notify(
			"wezterm-run.nvim: Skipping setup (not running inside WezTerm). $TERM_PROGRAM is '"
				.. tostring(vim.env.TERM_PROGRAM)
				.. "'",
			vim.log.levels.WARN
		)
		return
	end

	M.opts = helpers.merge_opts(M.opts, config or {})

	if M.opts.create_keymaps then
		local prefix_current = M.opts.prefix .. M.opts.suffix_keys.run_current
		local prefix_file = M.opts.prefix .. M.opts.suffix_keys.run_file
		local prefix_output = M.opts.prefix .. M.opts.suffix_keys.output

		for k, d in pairs(M.opts.direction_keys or {}) do
			map_run_current(k, d, prefix_current)
			map_run_file(k, d, prefix_file)
			map_retrieve_output(k, d, prefix_output)
		end

		map("v", prefix_current .. "w", function()
			M.send_selection({ pick = true })
		end, { desc = "Send selection: pick WezTerm pane", silent = true })

		map("v", prefix_file .. "r", function()
			M.send_selection({ pick = true })
		end, { desc = "Run file: pick WezTerm pane", silent = true })

		map("n", prefix_output .. "o", function()
			M.retrieve_and_deliver()
		end, { desc = "Wezterm: retrieve and deliver pane output" })

		-- Toggle capture mode on the fly
		map("n", M.opts.prefix .. "tc", function()
			M.opts.capture = (M.opts.capture == "auto") and "explicit" or "auto"
			_notify("wezterm-run.nvim: capture mode = " .. M.opts.capture, vim.log.levels.INFO)
		end, { desc = "wezterm-run.nvim: toggle capture mode (auto/explicit)" })
	end

	if M.opts.create_commands then
		create_user_commands()
	end
end

return M
