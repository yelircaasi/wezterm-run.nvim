local toplevel_functions = require("wezterm-run.toplevel")
local helpers = require("wezterm-run.helpers")

local map = vim.keymap.set
local pane_directions = { "left", "right", "up", "down", "next", "prev" }

---@param key         string
---@param direction   Direction
---@param prefix_send string
local function map_run_current(key, direction, keymap_prefix)
	-- shared logic here
	local sequence = keymap_prefix .. key
	local direction_lower = string.lower(direction)
	local send_opts = { direction = helpers.as_title(direction) }

	local function adhoc_map(mode, action, desc)
		vim.keymap.set(mode, sequence, action, { desc = desc })
	end

	-- visual mode only
	local visual_action = function()
		print("Sending selection " .. direction_lower .. ".")
		M.send_selection(send_opts)
	end
	adhoc_map("v", visual_action, "Send selection: WezTerm pane (" .. direction_lower .. ")")

	-- normal mode only
	local normal_action = function()
		print("Sending current node " .. direction_lower .. ".")
		M.send_node(send_opts)
	end
	adhoc_map("n", normal_action, "Send current block: WezTerm pane (" .. direction_lower .. ")")
end

---@param key           string
---@param direction     Direction
---@param keymap_prefix string
local function map_run_file(key, direction, keymap_prefix)
	local sequence = keymap_prefix .. key
	local direction_lower = string.lower(direction)
	local action = function()
		print("Executing file in " .. direction_lower .. " pane.")
		M.run_current_file({ direction = direction })
	end
	local desc = "Run current file: WezTerm pane (" .. direction_lower .. ")"
	map({ "n", "v" }, sequence, action, { desc = desc }) --, silent = true })
end

---@param key           string
---@param direction     Direction
---@param keymap_prefix string
local function map_retrieve_output(key, direction, keymap_prefix)
	print("TODO")
end

local M = {}

local function create_user_commands()
	-- WeztermSend
	vim.api.nvim_create_user_command(M.opts.command_prefix_run_current, function(cmd_opts)
		local direction = cmd_opts.args ~= "" and cmd_opts.args or options.default_direction
		if not direction then
			vim.notify("wezrun: no direction specified", vim.log.levels.WARN)
			return
		end
		direction = helpers.as_title(direction)
		if cmd_opts.range > 0 then
			M.send_selection(direction)
		else
			M.send_node(direction)
		end
	end, {
		range = true,
		nargs = "?", -- 0 or 1 argument
		complete = function()
			return pane_directions
		end,
	})

	-- WeztermRunFile (TODO)
	vim.api.nvim_create_user_command(M.opts.command_prefix_run_file, function(cmd_opts)
		M.run_current_file()
	end, {})

	-- WeztermRetrieve (TODO)
	vim.api.nvim_create_user_command(M.opts.command_prefix_output, function(cmd_opts)
		local args = vim.split(cmd_opts.args, "%s+", { trimempty = true })

		local local_opts = {}
		for _, arg in ipairs(args) do
			if arg:match("^ansi$") then
				local_opts.include_ansi_codes = true
			elseif arg:match("^[Ll]eft$|^[Rr]ight$|^[Uu]p$|^[Dd]own$|^[Nn]ext$|^[Pp]rev$") then
				local_opts.direction = arg:sub(1, 1):upper() .. arg:sub(2):lower()
				-- else
				-- 	-- anything else is treated as a match pattern
				-- 	local_opts.pattern = arg
			end
		end
		print(vim.inspect(local_opts))

		M.retrieve_and_deliver(local_opts)
	end, {
		nargs = "*",
		complete = function(arg_lead)
			local candidates = { "ansi", table.unpack(pane_directions) } -- TODO: valid? optimal?
			return vim.tbl_filter(function(c)
				return c:find(arg_lead, 1, true) == 1
			end, candidates)
		end,
	})

	-- Cleaner style
	-- TODO: make commands like
	--     WeztermRetrieve Right ansi
	--     WeztermRetrieve Left -> implicit non-ansi
	vim.api.nvim_create_user_command("SendCleanerExample", function(cmd_opts)
		local args = vim.split(cmd_opts.args, "%s+", { trimempty = true })

		local direction = args[1]
		if not direction then
			vim.notify("WezrunSend: direction is required", vim.log.levels.WARN)
			return
		end
		direction = direction:sub(1, 1):upper() .. direction:sub(2):lower()

		local match = args[2] -- optional, nil if not provided

		M.send_text(text, { direction = direction, match = match })
	end, {
		nargs = "+", -- 1 or more arguments
		complete = function(arg_lead, cmd_line)
			local args = vim.split(cmd_line, "%s+", { trimempty = true })
			if #args <= 2 then
				-- completing the first positional: direction
				return vim.tbl_filter(function(c)
					return c:find(arg_lead, 1, true) == 1
				end, pane_directions)
			else
				-- completing the optional second: match pattern suggestions
				return { "python", "bash", "node" }
			end
		end,
	})
end

M.opts = require("wezterm-run.config")

---@alias F fun(...):...

-- ---@param  new_opts WeztermRuntimeOpts
-- ---@param  f F
-- ---@return F
-- local function wrap_opts(f)
-- 	return function(...)
-- 		local args = { ... }
-- 		local n = #args
-- 		if n == 0 then
-- 			return f(M.opts)
-- 		end
-- 		args[n] = helpers.merge_opts(M.opts, args[n])
-- 		print(vim.inspect(opts))
-- 		return f(unpack(args or {}))
-- 	end
-- end

-- M.send_text = wrap_opts(toplevel_functions.send_text)
-- M.make_current_file_command = wrap_opts(toplevel_functions.make_current_file_command)
-- M.run_current_file = wrap_opts(toplevel_functions.run_current_file)
-- M.send_selection = wrap_opts(toplevel_functions.send_selection)
-- M.send_node = wrap_opts(toplevel_functions.send_node)
-- M.retrieve_output = wrap_opts(toplevel_functions.retrieve_output)
-- M.retrieve_and_deliver = wrap_opts(toplevel_functions.retrieve_and_deliver)

local function with_defaults(new_opts)
	return helpers.merge_opts(M.opts, new_opts)
end

function M.send_text(text, opts)
	return toplevel_functions.send_text(text, with_defaults(opts))
end

function M.send_selection(opts)
	return toplevel_functions.send_selection(with_defaults(opts))
end

function M.send_node(opts)
	return toplevel_functions.send_node(with_defaults(opts))
end

function M.run_current_file(opts)
	return toplevel_functions.run_current_file(with_defaults(opts))
end

function M.make_current_file_command(opts)
	return toplevel_functions.make_current_file_command(with_defaults(opts))
end

function M.retrieve_output(opts)
	return toplevel_functions.retrieve_output(with_defaults(opts))
end

function M.retrieve_and_deliver(opts)
	return toplevel_functions.retrieve_and_deliver(with_defaults(opts))
end

M.open_scratch = toplevel_functions.open_scratch

---@param config? WeztermRunSetupOpts
function M.setup(config)
	if not toplevel_functions.is_wezterm() then
		print(
			"Not setting up plugin wezterm-integration.nvim because not running in WezTerm."
				.. " Info: $TERM_PROGRAM is '"
				.. tostring(vim.env.TERM_PROGRAM)
				.. "' (expected "
				.. "'WezTerm')."
		)
		return
	else
		M.opts = helpers.merge_opts(M.opts, config)

		if M.opts.create_keymaps then
			local prefix_current = M.opts.prefix .. M.opts.suffix_key_run_current
			local prefix_file = M.opts.prefix .. M.opts.suffix_key_run_file
			local prefix_output = M.opts.prefix .. M.opts.suffix_key_output

			local command_send = M.opts.command_prefix_run_selection
			local command_file = M.opts.command_prefix_run_file
			local command_output = M.opts.command_prefix_output

			for k, d in pairs(M.opts.direction_keys) do
				map_run_current(k, d, prefix_current)
				map_run_file(k, d, prefix_file)
				map_retrieve_output(k, d, prefix_output)
			end

			create_user_commands(M.opts)

			-- TODO: clean up
			map("v", prefix_current .. "w", function()
				M.send_selection({ pick = true })
			end, { desc = "Send selection: pick WezTerm pane", silent = true })

			map("v", prefix_file .. "r", function()
				M.send_selection({ pick = true })
			end, { desc = "Run file: pick WezTerm pane", silent = true })

			map("n", prefix_output .. "o", function()
				M.retrieve_and_deliver()
			end, { desc = "Wezterm: retrieve and deliver pane output" })

			-- Toggle capture mode on the fly.
			map("n", M.opts.prefix .. "tc", function()
				M.opts.capture = (M.opts.capture == "auto") and "explicit" or "auto"
				vim.notify("wezterm-run.nvim: capture mode = " .. options.capture, vim.log.levels.INFO)
			end, { desc = "wezterm-run.nvim: toggle capture mode (auto/explicit)" })
		end
		if M.opts.create_commands then
			create_user_commands(M.opts)
		end
	end
end

return M
