-- Vim-like navigation of WezTerm scrollback + "open path under cursor in nvim".
--
-- Usage from wezterm.lua:
--     require('wezterm-run').apply(config)
--
-- Dependencies:
--   * neovim-remote (`nvr`) on PATH:  `pip3 install neovim-remote` OR `nix-shell -p neovim-remote`
--
-- Keybindings created:
--   ALT+u        enter Copy Mode (already Vim-keyed: hjkl w b e 0 $ gg G v y / ?)
--   ALT+o        (inside Copy Mode) open the path under the cursor in nvim

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- small helpers --------------------------------------------------------------

local function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function shell_quote(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function expand_tilde(p)
	if p:sub(1, 1) == "~" then
		return wezterm.home_dir .. p:sub(2)
	end
	return p
end

local function to_abs_path(p)
	p = expand_tilde(p)
	local ok, stdout = wezterm.run_child_process({
		"sh",
		"-c",
		'realpath -- "$1" 2>/dev/null || printf "%s" "$1"',
		"--",
		p,
	})
	if ok and stdout and stdout ~= "" then
		return trim(stdout)
	end
	return p
end

local function path_exists(p)
	local ok = wezterm.run_child_process({ "sh", "-c", 'test -e "$1"', "--", p })
	return ok
end

-- Grabs the token (path) under (row, col) in `lines` (1-based array of strings).
-- Returns the raw token string or nil.
local function token_under_cursor(lines, row, col)
	local line = lines[row + 1]
	if not line or col >= #line then
		return nil
	end

	local function is_path_char(c)
		if not c or c == "" then
			return false
		end
		return c:match("[%w%._%-/~@%+%%]") ~= nil
	end

	local start_i, end_i = col + 1, col + 1
	while start_i > 1 and is_path_char(line:sub(start_i - 1, start_i - 1)) do
		start_i = start_i - 1
	end
	while end_i <= #line and is_path_char(line:sub(end_i, end_i)) do
		end_i = end_i + 1
	end
	local token = line:sub(start_i, end_i - 1)
	if token == "" then
		return nil
	end
	return token
end

-- Split "path:line:col" or "path:line" into its constituent parts.
local function split_line_col(token)
	local path, line, col = token:match("^(.-):(%d+):(%d+)$")
	if path then
		return path, tonumber(line), tonumber(col)
	end
	path, line = token:match("^(.-):(%d+)$")
	if path then
		return path, tonumber(line), nil
	end
	return token, nil, nil
end

-- Find a running nvim server whose cwd is a parent of abs_path.
local function find_nvim_for_path(abs_path)
	local handle = io.popen("nvr --serverlist 2>/dev/null")
	if not handle then
		return nil
	end
	for srv in handle:lines() do
		srv = trim(srv)
		if srv ~= "" then
			local cwd_handle =
				io.popen(string.format('nvr --servername %s --remote-expr "getcwd()" 2>/dev/null', shell_quote(srv)))
			if cwd_handle then
				local cwd = cwd_handle:read("*l")
				cwd_handle:close()
				if cwd and cwd ~= "" then
					cwd = trim(cwd)
					local prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
					if abs_path == cwd or abs_path:sub(1, #prefix) == prefix then
						return srv
					end
				end
			end
		end
	end
	handle:close()
	return nil
end

-- the action -----------------------------------------------------------------
-- TODO: refactor into get_path_under_cursor, find_running_nvim, and open_file
-- TODO: create wezterm-cfg-for-dev.lua (under same dir as this, resolve file path and use dofile)
local function open_path_under_cursor(window, pane)
	local text = pane:get_lines_as_text()
	if not text or text == "" then
		return
	end

	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, line)
	end

	local pos = pane:get_cursor_position()
	if not pos then
		return
	end

	local dims = pane:get_dimensions()
	local scrollback_top = dims and dims.scrollback_top or 0
	local row = pos.y + scrollback_top
	local col = pos.x

	local token = token_under_cursor(lines, row, col)
	if not token then
		window:toast_notification("wezterm", "No token under cursor", nil, 2000)
		return
	end

	local path_part, line_no, col_no = split_line_col(token)
	local abs_path = to_abs_path(path_part)

	if not path_exists(abs_path) then
		window:toast_notification("wezterm", "Not a file: " .. abs_path, nil, 3000)
		return
	end

	local server = find_nvim_for_path(abs_path)

	if server then
		if line_no then
			local cmd = string.format(":e %s<CR>", abs_path)
			cmd = cmd .. string.format(":call cursor(%d,%d)<CR>", line_no, col_no or 1)
			wezterm.run_child_process({
				"nvr",
				"--servername",
				server,
				"--remote-send",
				cmd,
			})
		else
			wezterm.run_child_process({
				"nvr",
				"--servername",
				server,
				"--remote",
				abs_path,
			})
		end
	else
		local args = {
			"wezterm",
			"cli",
			"split-pane",
			"--left",
			"--percent",
			"50",
			"--",
			"nvim",
		}
		if line_no then
			table.insert(args, string.format("+call cursor(%d,%d)", line_no, col_no or 1))
		end
		table.insert(args, abs_path)
		wezterm.run_child_process(args)
	end

	window:perform_action(act.CopyMode("Close"), pane)
end

-- public API

function M.apply(config)
	config.keys = config.keys or {}

	-- Enter Copy Mode from normal mode.
	table.insert(config.keys, {
		key = "u",
		mods = "ALT",
		action = act.ActivateCopyMode,
	})

	-- Copy-mode key table: add ALT+o there (Copy Mode uses its own table,
	-- so a top-level binding would not fire while navigating).
	config.key_tables = config.key_tables or {}
	local cm = config.key_tables.copy_mode or {}
	table.insert(cm, {
		key = "o",
		mods = "ALT",
		action = wezterm.action_callback(open_path_under_cursor),
	})
	config.key_tables.copy_mode = cm

	return config
end

return M
