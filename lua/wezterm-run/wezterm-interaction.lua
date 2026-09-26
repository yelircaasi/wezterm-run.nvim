local helpers = require("wezterm-run.helpers")

local M = { _snapshots = {} }

local _notify = print -- vim.notify

function M.is_wezterm()
print("CALLING wez.is_wezterm")
	return vim.env.WEZTERM_PANE ~= nil
end

---@alias PaneDirection "Left"|"Right"|"Up"|"Down"|"Next"|"Prev"

---@class PaneRecord
---@field pane_id   string
---@field window_id string
---@field tab_id    string
---@field title     string
---@field cwd       string
---@field workspace string

---@class WeztermRuntimeOpts
---@field direction?   PaneDirection
---@field pattern?     string   Pattern matched against pane title / cwd
---@field pane_id?     string   Explicit pane id (overrides everything else)
---@field pick?        boolean  Show interactive picker (async)
---@field add_newline? boolean  Ensure trailing newline (default true)

--- Retrieve $WEZTERM_PANE (env var set by WezTerm for the current pane).
---@return string|nil
function M.current_pane_id()
print("CALLING wez.current_pane_id")
	local id = vim.env.WEZTERM_PANE
	if id and id ~= "" then
		return id
	end
	return nil
end

--- Get the pane_id of an adjacent pane by direction.
---@param direction PaneDirection
---@return string|nil pane_id
function M.pane_by_direction(direction)
print("CALLING wez.pane_by_direction")
	local pane_id = M.current_pane_id()
	local cmd = { "wezterm", "cli", "get-pane-direction", direction }
	if pane_id then
		vim.list_extend(cmd, { "--pane-id", pane_id })
	end
	local out, code = helpers.run(cmd)
	if code == 0 and out ~= "" then
		return out
	end
	return nil
end

--- List all WezTerm panes as a table of records.
---@return table[PaneRecord]
function M.list_panes()
print("CALLING wez.list_panes")
	local out, code = helpers.run({ "wezterm", "cli", "list", "--format", "json" })
	if code ~= 0 or out == "" then
		return {}
	end
	local ok, panes = pcall(vim.json.decode, out)
	if not ok or type(panes) ~= "table" then
		return {}
	end

	-- Normalise field names (wezterm uses snake_case already, but let's be safe)
	local result = {}
	for _, p in ipairs(panes) do
		table.insert(result, {
			pane_id = tostring(p.pane_id),
			window_id = tostring(p.window_id),
			tab_id = tostring(p.tab_id),
			title = p.title or "",
			cwd = p.cwd or "",
			workspace = p.workspace or "",
		})
	end
	return result
end

--- Find the first pane whose title or cwd matches `pattern` (case-insensitive).
--- Excludes the current nvim pane if its id is known.
---@param pattern string (Lua pattern or plain substring)
---@return string|nil pane_id
function M.pane_by_pattern(pattern)
print("CALLING wez.pane_by_pattern")
	local this_pane = M.current_pane_id()
	pattern = pattern:lower()

	for _, p in ipairs(M.list_panes()) do
		if p.pane_id ~= this_pane then
			local title_lowercase = p.title:lower()
			local cwd_lowercase = p.cwd:lower()
			if title_lowercase:find(pattern, 1, true) or cwd_lowercase:find(pattern, 1, true) then
				return p.pane_id
			end
		end
	end
	return nil
end

---Open a vim.ui.select picker over all panes. Resolves to a pane_id.
---@param callback fun(pane_id: string|nil)
---@return string
function M.pick_pane(callback)
print("CALLING wez.pick_pane")
	local my_id = M.current_pane_id()
	local panes = M.list_panes()

	-- Filter out ourselves so we don't accidentally send to nvim
	local choices = {}
	for _, p in ipairs(panes) do
		if p.pane_id ~= my_id then
			table.insert(choices, p)
		end
	end

	if #choices == 0 then
		_notify("wezterm_send: no other panes found", vim.log.levels.WARN)
		callback(nil)
		return
	end

	vim.ui.select(choices, {
		prompt = "Send to WezTerm pane:",
		format_item = function(p)
			local cwd_short = p.cwd:gsub("^file://[^/]*/", "/"):gsub("^/home/[^/]*/", "~/")
			return ("[%s] %s  %s"):format(p.pane_id, p.title, cwd_short)
		end,
	}, function(choice)
		callback(choice and choice.pane_id or nil)
	end)
end

--- Resolve a target pane_id from opts (sync paths only; pick is handled separately).
---@param opts WeztermRuntimeOpts
---@return string|nil pane_id, string|nil err
function M.resolve_pane(opts)
print("CALLING wez.resolve_pane")
	if not opts then
		opts = { direction = "Right" }
	end

	if opts.pane_id then
		return opts.pane_id, nil
	end

	if opts.pattern then
		local id = M.pane_by_pattern(opts.pattern)
		if not id then
			return nil, ("No pane matched '%s'"):format(opts.pattern)
		end
		return id, nil
	end

	local direction = opts.direction or "Right" -- TODO: use opts.default_direction
	local id = M.pane_by_direction(direction)
	if not id then
		-- TODO: USE WEZTERM CLI TO OPEN PANE TO THE RIGHT!
		-- OLD: return nil, ("No pane found in direction '%s'"):format(direction)

		local cmd = { "wezterm", "cli", "split-pane", "--right" }
		local output = vim.fn.system(cmd)
		if vim.v.shell_error ~= 0 then
			return nil, ("Failed to create pane to the right: %s"):format(output)
		end
		id = tonumber(vim.trim(output))
		if not id then
			return nil, ("Could not parse pane ID from wezterm CLI output: %s"):format(output)
		end
	end
	return id, nil

	-- return nil, "No targeting strategy given (use direction, pattern, pane_id, or pick)"
end

--- Send `text` to WezTerm pane `pane_id` via stdin.
---@param pane_id string
---@param text string
---@return boolean success, string? err
function M.send_to_pane(pane_id, text)
print("CALLING wez.send_to_pane")
	text = helpers.ensure_newline(text)

	-- wezterm cli send-text reads from stdin when no positional TEXT arg is given
	local cmd = { "wezterm", "cli", "send-text", "--no-paste", "--pane-id", pane_id }
	local obj = vim.system(cmd, {
		text = true,
		stdin = text,
	}):wait()

	if obj.code ~= 0 then
		local err = vim.trim(obj.stderr or "")
		return false, ("wezterm exited: exit code %d: %s"):format(obj.code, err)
	end
	return true
end

-- LATEST =========================================================================================

--- To be called just before sending text.
---@return nil
function M.snapshot_pane(opts)
print("CALLING wez.snapshot_pane")
	local pane_id, err = M.resolve_pane(opts)
	if not pane_id then
		_notify("wezterm-run.nvim: " .. (err or "unknown error"), vim.log.levels.WARN)
		return
	end

	local output = M.retrieve_output({ pane_id = pane_id }) or ""
	-- Store the pre-snapshot keyed by pane_id
	M._snapshots[pane_id] = vim.split(output, "\n", { plain = true })
	_notify("wezterm-run.nvim: pane snapshot taken", vim.log.levels.INFO)
end

-- NEXT

--- Explicit retrieval: user calls this when ready
---@param output string
---@param target string|nil
---@return nil
function M.deliver_output(output, target)
print("CALLING wez.deliver_output")
	if target == "clipboard" then
		vim.fn.setreg("+", output)
		vim.fn.setreg('"', output)
		_notify("wezterm-run.nvim: output copied to clipboard", vim.log.levels.INFO)
	elseif target == "scratch" then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].filetype = "text"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n", { plain = true }))
		vim.cmd.split()
		vim.api.nvim_win_set_buf(0, buf)
	elseif target == "quickfix" then
		local items = {}
		for _, line in ipairs(vim.split(output, "\n", { plain = true })) do
			table.insert(items, { text = line })
		end
		vim.fn.setqflist(items, "r")
		vim.cmd.copen()
	end
end

--- Explicit retrieval: user calls this when ready
---@param opts WeztermRuntimeOpts
---@return nil
function M.retrieve_and_deliver(opts)
print("CALLING wez.retrieve_and_deliver")
	local output = M.retrieve_output(opts)
	if output then
		M.deliver_output(output, opts.capture_target)
	end
end

--- Retrieve output from a pane, diffing against the pre-send snapshot if one exists.
--- If a snapshot exists: returns only lines added since mark_pane was called.
--- If no snapshot exists: returns the last `opts.lines` lines of scrollback raw.
---@param opts WeztermRuntimeOpts
---@return string|nil
function M.retrieve_output(opts)
print("CALLING wez.retrieve_output")
	local pane_id, err = M.resolve_pane(opts)
	if not pane_id then
		_notify("wezterm-run.nvim: " .. (err or "unknown error"), vim.log.levels.WARN)
		return nil
	end
	local retrieval_command = {
		"wezterm",
		"cli",
		"get-text",
		"--pane-id",
		pane_id,
	}
	if opts.include_ansi_codes then
		table.insert(retrieval_command, "--escapes")
	end
	print(vim.inspect(retrieval_command))

	-- Fetch full pane text via CLI
	local out, code = helpers.run(retrieval_command)
	if code ~= 0 then
		_notify("wezterm-run.nvim: get-text failed for pane " .. pane_id, vim.log.levels.ERROR)
		return nil
	end

	local post_lines = vim.split(out, "\n", { plain = true })
	local pre_lines = M._snapshots[pane_id]

	if pre_lines then
		-- Snapshot exists: diff against it, returning only new lines
		local pre_tail = pre_lines[#pre_lines]
		for i = #post_lines, 1, -1 do
			if post_lines[i] == pre_tail then
				local new_lines = vim.list_slice(post_lines, i + 1)
				M._snapshots[pane_id] = nil
				return table.concat(new_lines, "\n")
			end
		end
		-- pre_tail scrolled out of view: fall through to raw tail below
		M._snapshots[pane_id] = nil
	end

	-- No snapshot (or scrollback displaced it): return last `lines` lines
	local limit = opts.lines or opts.default_lines or 50
	local tail = vim.list_slice(post_lines, math.max(1, #post_lines - limit + 1))
	return table.concat(tail, "\n")
end

--- Poll a pane until it differs from the pre-send snapshot and its output has
--- 	stabilised (unchanged across two consecutive polls).
---@param pane_id      string
---@param pre_lines    string[]   snapshot taken before the command was sent
-- @param callback     fun(post_lines: string[])  called when output is complete
---@param opts?        { interval_ms?: integer, max_attempts?: integer }
local function autoretrieve_output(pane_id, pre_lines, opts)
print("CALLING autoretrieve_output")
	-- TODO: add options to config (scour this whole file)
	local interval_ms = opts.interval_ms or opts.poll_interval_ms or 500
	local max_attempts = opts.max_attempts or 20 -- 20 * 500ms = 10 seconds

	local attempts = 0
	local prev_snap = nil -- last poll's content, for stability check

	local function poll()
print("CALLING poll")
		attempts = attempts + 1

		if attempts > max_attempts then
			_notify("wezterm-run.nvim: timed out waiting for output to stabilise", vim.log.levels.WARN)
			return
		end

		local raw = M.retrieve_output({ pane_id = pane_id }) or ""
		local current = vim.split(raw, "\n", { plain = true })

		local differs_from_pre = (raw ~= table.concat(pre_lines, "\n"))
		local stable_across_polls = prev_snap ~= nil and (raw == prev_snap)

		if differs_from_pre and stable_across_polls then
			return current
		end

		prev_snap = raw
		vim.defer_fn(poll, interval_ms)
	end

	vim.defer_fn(poll, interval_ms)
end

return M
