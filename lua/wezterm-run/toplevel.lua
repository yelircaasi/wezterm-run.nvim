local helpers = require("wezterm-run.helpers")
local wez = require("wezterm-run.wezterm-interaction")
local selection = require("wezterm-run.selection")

local _notify = print -- vim.notify

local M = {}

-- public API -------------------------------------------------------------------------------------

--- Send arbitrary text to a WezTerm pane.
---@param text string
---@param opts WeztermRuntimeOpts
function M.send_text(text, opts)
	print("CALLING toplevel.send_text")
	if opts.pick then
		wez.pick_pane(function(pane_id)
			if pane_id then
				local ok, err = wez.send_to_pane(pane_id, text)
				if not ok then
					notify("wezterm_send: " .. (err or "unknown error"), vim.log.levels.ERROR)
				else
					notify(("wezterm_send: sent to pane %s"):format(pane_id), vim.log.levels.INFO)
				end
			end
		end)
		return
	end

	local pane_id, err = wez.resolve_pane(opts)
	if not pane_id then
		_notify("wezterm_send: " .. (err or "unknown error"), vim.log.levels.WARN)
		return
	end

	local ok, send_err = wez.send_to_pane(pane_id, text)
	if not ok then
		_notify("wezterm_send: " .. (send_err or "unknown error"), vim.log.levels.ERROR)
	else
		_notify(("wezterm_send: sent to pane %s"):format(pane_id), vim.log.levels.INFO)
	end
end

-- TODO: make configurable rather than hard-coded (but with good defaults).
--- Prepare the command to execute the current file.
---@param opts? WeztermRuntimeOpts
function M.make_current_file_command(opts)
	print("CALLING toplevel.make_current_file_command")
	local file_path = vim.api.nvim_buf_get_name(0)
	local file_type = vim.bo.filetype

	local runner = opts.file_runners[file_type]
	if not runner then
		_notify("wezterm_send: no runner configured for filetype: " .. file_type, vim.log.levels.WARN)
		return nil
	elseif type(runner) == "function" then
		return runner()
	else
		local parts = { runner.prefix, file_path }
		if runner.suffix ~= "" then
			table.insert(parts, runner.suffix)
		end
		return table.concat(parts, " ")
	end
end

function M.run_current_file(opts)
	print("CALLING toplevel.run_current_file")
	print(vim.inspect(opts))
	local command = M.make_current_file_command(opts)
	if not command then
		return
	end

	-- Prefer a pane that looks like a shell (title matches sh/bash/zsh/fish)
	local shell_pane = wez.pane_by_pattern(opts.pattern or "bash")
		or wez.pane_by_pattern("zsh")
		or wez.pane_by_pattern("fish")
		or wez.pane_by_pattern("sh")

	if shell_pane then
		local ok, err = wez.send_to_pane(shell_pane, command)
		if not ok then
			_notify("wezterm_send: " .. (err or "unknown error"), vim.log.levels.ERROR)
		end
	else
		-- No shell pane found: spawn one to the right, then send
		local spawn_out, code = helpers.run({ "wezterm", "cli", "split-pane", "--right", "--percent", "40" })
		if code ~= 0 then
			_notify("wezterm_send: could not open a new pane", vim.log.levels.ERROR)
			return
		end
		local new_pane_id = vim.trim(spawn_out)
		-- Brief pause to let the shell initialise before sending
		vim.defer_fn(function()
			local ok, err = wez.send_to_pane(new_pane_id, command)
			if not ok then
				_notify("wezterm_send: " .. (err or "unknown error"), vim.log.levels.ERROR)
			end
		end, 300)
	end
end

---@param is_selection bool
local function make_send_current(is_selection)
	print("CALLING make_send_current")
	local text_getter, text_type
	if is_selection then
		text_getter = selection.get_visual_selection
		text_type = "selection"
	else
		text_getter = selection.get_current_block
		text_type = "node"
	end

	--- Send the current visual selection to a WezTerm pane.
	--- Auto-snapshots before sending so retrieve_output works without a separate step.
	--- If opts.capture == "auto", polls for completion and delivers output immediately.
	---@param opts? WeztermRuntimeOpts
	---@return nil
	local function inner_send_current(opts)
		print("CALLING inner_send_current")
		local text = text_getter()
		if text == "" then
			_notify("wezterm-run.nvim: empty " .. text_type, vim.log.levels.WARN)
			return
		end

		local pane_id, err = wez.resolve_pane(opts)
		if not pane_id then
			_notify("wezterm-run.nvim: " .. (err or "unknown error"), vim.log.levels.WARN)
			return
		end
		opts.pane_id = pane_id

		-- Snapshot before sending so retrieve_output can diff against it
		wez.snapshot_pane(opts)
		M.send_text(text, opts)

		if opts.capture == "auto" then
			local pre_lines = wez._snapshots[pane_id]
			output_complete(pane_id, pre_lines, function(post_lines)
				local output = M.retrieve_output(opts)
				if output then
					wez.deliver_output(output, opts.capture_target)
				end
			end, { interval_ms = opts.poll_interval_ms })
		end
	end
	return inner_send_current
end

---@class ScratchWindowInfo
---@field id string?
---@field path string?

---@param window_info ScratchWindowInfo
function M.open_scratch(window_info)
	print("CALLING toplevel.open_scratch")
	-- use window ID and/or path to create/identify window and file location
	-- cases:
	--     id and path: validate
	--     id: search for id, otherwise create
	--     path: create file at path; open new buffer
	--     => (should I check existing buffers for path and select that buffer if it exists?)
end

M.send_selection = make_send_current(true)
M.send_node = make_send_current(false)
M.retrieve_output = wez.retrieve_output
M.retrieve_and_deliver = wez.retrieve_and_deliver
M.is_wezterm = wez.is_wezterm

return M
