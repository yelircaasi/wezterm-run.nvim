local wezterm = require("wezterm")

-- This is deliberately broad.
-- The Lua parser below decides whether the resulting match is actually a filesystem path.
PATH_LOCATION_SEARCH_REGEX = "(?x)(?:"
	.. table.concat({
		[[File[ \t]+["'][^"'\n]+["'][ \t]*,[ \t]*line[ \t]+\d+]],
		[[[^ \t\n"'<>|]+:\d+(?::\d+)?]],
		[[[^ \t\n"'<>|]+\(\d+(?:,\d+)?\)]],
		[[[^ \t\n"'<>|]+?/[^ \t\n"'<>|]+]],
	}, "|")
	.. ")"

print(PATH_LOCATION_SEARCH_REGEX)

-- Path types:
--   1. Python traceback
--   2. C/C++/Rust/GCC/etc: `foo/bar.rs:42` / `foo/bar.rs:42:17`
--   3. MSVC / Rust-ish: `foo.cpp(42)` / `foo.cpp(42,17)`
--   4. Plain paths. Keep this last because the location patterns
--      should consume the :line / (line,col) suffix.
PATH_LOCATION_REGEX = [[
(?x)
(?:
	# 1. Python traceback
	File \s+ ["'] (?<python_path>[^"']+) ["'] , \s* line \s+ (?<python_line>\d+)

  |
	# 2. path:line[:col]
	(?<colon_path>
		(?:
			  /[^ \t\n"'<>|:]+
			| \.?\.?/[^ \t\n"'<>|:]+
			| ~\/[^ \t\n"'<>|:]+
			| [A-Za-z0-9_./-]+
		)
	)
	:
	(?<colon_line>\d+)
	(?:
		:
		(?<colon_col>\d+)
	)?

  |
	# 3. path(line[,col])
	(?<paren_path>
		(?:
			  /[^ \t\n"'<>|()]+
			| \.?\.?/[^ \t\n"'<>|()]+
			| ~\/[^ \t\n"'<>|()]+
			| [A-Za-z0-9_./-]+
		)
	)
	\(
		(?<paren_line>\d+)
		(?:
			,
			(?<paren_col>\d+)
		)?
	\)

  |
	# 4. plain path (kept last: only reached once the :line
	#    and (line,col) forms above have failed to match)
	(?<plain_path>
		(?:
			  /[^ \t\n"'<>|]+
			| \.?\.?/[^ \t\n"'<>|]+
			| ~\/[^ \t\n"'<>|]+
			| [A-Za-z0-9_./-]+/[A-Za-z0-9_./-]+
			| [A-Za-z0-9_.-]+\.[A-Za-z0-9_.-]+
		)
	)
)
]]

-- ================================================================================================
-- HELPERS
-- ================================================================================================

local helpers = {}

function helpers.get_key_table(config, table_name)
	key_table = config.key_tables[table_name] or wezterm.gui.default_key_tables()[table_name]

	assert(key_table ~= nil)
	return key_table
end

function helpers.update_table(tbl, to_insert)
	for _, new_element in ipairs(to_insert) do
		table.insert(tbl, new_element)
	end

	return tbl
end

function helpers.parse_location(text)
	if not text then
		return nil
	end

	text = text:gsub("^%s+", ""):gsub("%s+$", "")

	-- Python traceback
	--
	-- File "/home/me/foo.py", line 42
	local path, line = text:match([[[Ff]ile%s+["']([^"']+)["']%s*,%s*line%s+(%d+)]])
	if path then
		return {
			path = path,
			line = tonumber(line),
		}
	end

	-- path:line:column
	local path, line, col = text:match("^(.+):(%d+):(%d+)$")
	if path then
		return {
			path = path,
			line = tonumber(line),
			column = tonumber(col),
		}
	end

	-- path:line
	local path, line = text:match("^(.+):(%d+)$")
	if path then
		return {
			path = path,
			line = tonumber(line),
		}
	end

	-- path(line,column)
	path, line, col = text:match("^(.+)%((%d+),(%d+)%)$")
	if path then
		return {
			path = path,
			line = tonumber(line),
			column = tonumber(col),
		}
	end

	-- path(line)
	path, line = text:match("^(.+)%((%d+)%)$")
	if path then
		return {
			path = path,
			line = tonumber(line),
		}
	end

	-- plain path
	return {
		path = text,
	}
end

function helpers.normalize_path(path, cwd)
	-- Strip common compiler punctuation.
	path = path:gsub("^[\"'`(<[]+", "")
	path = path:gsub("[\"'`)>],;]+$", "")

	-- ~/foo
	if path == "~" then
		return wezterm.home_dir
	end

	if path:sub(1, 2) == "~/" then
		path = wezterm.home_dir .. path:sub(2)
	end

	-- absolute path
	if path:sub(1, 1) == "/" then
		return path
	end

	-- relative path
	if cwd:sub(-1) == "/" then
		return cwd .. path
	end

	return cwd .. "/" .. path
end

function helpers.path_exists(path)
	local success = wezterm.run_child_process({
		"test",
		"-e",
		path,
	})

	return success
end

function helpers.search_next_path(wz_act)
	return wz_act.Search({
		Regex = PATH_LOCATION_SEARCH_REGEX,
	})
end

function helpers.trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function helpers.to_abs_path(p, cwd)
	p = helpers.expand_tilde(p)

	if p:sub(1, 1) ~= "/" then
		p = cwd .. "/" .. p
	end

	local ok, stdout = wezterm.run_child_process({
		"realpath",
		"--",
		p,
	})

	if ok and stdout and stdout ~= "" then
		return helpers.trim(stdout)
	end

	return p
end

function helpers.shell_quote(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

function helpers.expand_tilde(p)
	if p:sub(1, 1) == "~" then
		return wezterm.home_dir .. p:sub(2)
	end
	return p
end

-- ================================================================================================
-- DOMAIN HELPERS
-- ================================================================================================

local domain = {}

-- Copy Mode has no exposed cursor-coordinate API. pane:get_cursor_position()
-- always reports the real PTY cursor, not wherever hjkl has navigated to in
-- Copy Mode. So instead of reading a position, we anchor a selection at the
-- cursor and grow it, using the selected text to detect where the path-like
-- token starts and ends.
function domain:token_under_copy_cursor(window, pane)
	local act = wezterm.action

	local function selected()
		return window:get_selection_text_for_pane(pane) or ""
	end

	local function is_path_char(c)
		return c ~= "" and c:match("[%w%._%-%/~@+%%:]") ~= nil
	end

	window:perform_action(act.CopyMode({ SetSelectionMode = "Cell" }), pane)

	local text = selected()
	if not is_path_char(text) then
		window:perform_action(act.ClearSelection, pane)
		return nil
	end

	-- Grow left.
	while true do
		window:perform_action(act.CopyMode("MoveLeft"), pane)
		local candidate = selected()
		if candidate == text or not is_path_char(candidate:sub(1, 1)) then
			window:perform_action(act.CopyMode("MoveRight"), pane)
			break
		end
		text = candidate
	end

	-- Swap the active selection end so further movement grows to the
	-- right of the original cursor cell instead of continuing left.
	window:perform_action(act.CopyMode("MoveToSelectionOtherEnd"), pane)

	-- Grow right.
	while true do
		window:perform_action(act.CopyMode("MoveRight"), pane)
		local candidate = selected()
		if candidate == text or not is_path_char(candidate:sub(-1)) then
			window:perform_action(act.CopyMode("MoveLeft"), pane)
			break
		end
		text = candidate
	end

	window:perform_action(act.ClearSelection, pane)

	return text
end

-- TODO: delete
function domain:token_under_cursor(line, col)
	if not line or line == "" or col < 0 then
		return nil
	end

	is_path_char = function(c)
		return c ~= "" and c:match("[%w%._%-%/~@+%%:]") ~= nil
	end

	-- Convert terminal cell column to a Lua byte position.
	-- WezTerm columns are 0-based; Lua string positions are 1-based
	-- byte offsets. This walks UTF-8 codepoints so non-ASCII text
	-- before the token doesn't throw off the position.
	local byte_pos = 1
	local cell_pos = 0

	while byte_pos <= #line and cell_pos < col do
		local byte = line:byte(byte_pos)

		local width = byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4

		byte_pos = byte_pos + width
		cell_pos = cell_pos + 1
	end

	-- No token if the cursor is beyond the end of the line.
	if byte_pos > #line + 1 then
		return nil
	end

	-- If the cursor is on the cell immediately after the token, use the
	-- preceding character as the starting point.
	if byte_pos > #line then
		byte_pos = #line
	end

	-- Expand backwards over path characters.
	local start_pos = byte_pos

	while start_pos > 1 and is_path_char(line:sub(start_pos - 1, start_pos - 1)) do
		start_pos = start_pos - 1
	end

	-- Expand forwards over path characters.
	local end_pos = byte_pos

	while end_pos <= #line and is_path_char(line:sub(end_pos, end_pos)) do
		end_pos = end_pos + 1
	end

	local token = line:sub(start_pos, end_pos - 1)

	return token ~= "" and token or nil
end

-- Split "path:line:col" or "path:line" into its constituent parts.
function domain:split_line_col(token)
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
function domain:find_nvim_for_path(abs_path)
	local handle = io.popen("nvr --serverlist 2>/dev/null")
	if not handle then
		return nil
	end
	for srv in handle:lines() do
		srv = trim(srv)
		if srv ~= "" then
			local cwd_handle = io.popen(
				string.format('nvr --servername %s --remote-expr "getcwd()" 2>/dev/null', helpers.shell_quote(srv))
			)
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

function domain:get_cursor_line(window, pane)
	local pos = pane:get_cursor_position()

	if not pos then
		window:toast_notification("wezterm", "`get_cursor_position()`: pos is nil", nil, 2000)
		return nil, nil, nil
	end

	wezterm.log_info("cursor position: " .. wezterm.to_string(pos))

	local dims = pane:get_dimensions()

	if not dims then
		window:toast_notification("wezterm", "`get_dimensions()`: dims is nil", nil, 2000)
		return nil, nil, nil
	end

	wezterm.log_info("cursor dims: " .. wezterm.to_string(dims))

	local line = pane:get_text_from_region(0, pos.y, dims.cols - 1, pos.y)

	wezterm.log_info(string.format("cursor y=%s x=%s line=%q", tostring(pos.y), tostring(pos.x), line))

	return line, pos.x, pos.y
end

function domain:get_path_under_cursor(window, pane)
	local token = domain:token_under_copy_cursor(window, pane)

	if not token then
		window:toast_notification("wezterm", "No token under cursor", nil, 2000)
		return nil
	end

	local path_part, line_no, col_no = domain:split_line_col(token)

	local cwd_uri = pane:get_current_working_dir()
	if not cwd_uri then
		return nil
	end

	local cwd = cwd_uri.file_path
	if not cwd then
		return nil
	end

	local abs_path = helpers.to_abs_path(path_part, cwd)

	return abs_path, line_no, col_no
end

function domain:OLD_get_path_under_cursor(window, pane)
	local line, col, row = domain:get_cursor_line(window, pane)

	wezterm.log_info(
		"get_path_under_cursor: " .. "line=" .. tostring(line) .. " col=" .. tostring(col) .. " row=" .. tostring(row)
	)

	if not line then
		window:toast_notification("wezterm", "get_cursor_line returned nil line", nil, 2000)
		return nil
	end

	local token = domain:token_under_cursor(line, col)

	wezterm.log_info("token_under_cursor returned: " .. tostring(token))

	if not token then
		window:toast_notification("wezterm", "No token under cursor", nil, 2000)
		return nil
	end

	wezterm.log_info("cursor token = " .. token)

	local path_part, line_no, col_no = domain:split_line_col(token)

	local cwd_uri = pane:get_current_working_dir()
	if not cwd_uri then
		return nil
	end

	local cwd = cwd_uri.file_path
	if not cwd then
		return nil
	end

	local abs_path = helpers.to_abs_path(path_part, cwd)

	return abs_path, line_no, col_no
end

function domain:open_path(abs_path, nvim_server, line_no, col_no)
	if nvim_server then
		if line_no then
			local cmd = string.format(":e %s<CR>", abs_path)

			cmd = cmd .. string.format(":call cursor(%d,%d)<CR>", line_no, col_no or 1)

			wezterm.run_child_process({
				"nvr",
				"--servername",
				nvim_server,
				"--remote-send",
				cmd,
			})
		else
			wezterm.run_child_process({
				"nvr",
				"--servername",
				nvim_server,
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
end

-- ================================================================================================
-- public API
-- ================================================================================================

local M = {}

function M.apply(config)
	local act = wezterm.action

	print("applying wezterm-run")
	config.keys = config.keys or {}
	config.key_tables = config.key_tables or {}

	local function open_path_under_cursor(window, pane)
		local abs_path, line_no, col_no = domain:get_path_under_cursor(window, pane)

		if not abs_path then
			return
		end

		if not helpers.path_exists(abs_path) then
			window:toast_notification("wezterm", "Not a file: " .. abs_path, nil, 3000)
			return
		end

		local nvim_server = domain:find_nvim_for_path(abs_path)

		domain:open_path(abs_path, nvim_server, line_no, col_no)

		window:perform_action(act.CopyMode("Close"), pane)
	end

	-- Global keybinds --------------------------------------------------------

	local config_keys = config.keys

	local global_binds = {
		{
			key = "u",
			mods = "ALT",
			action = act.ActivateCopyMode,
		},
		{
			key = "p",
			mods = "ALT",
			action = act.Search({ Regex = PATH_LOCATION_SEARCH_REGEX }),
		},
	}

	config.keys = helpers.update_table(config_keys, global_binds)

	-- CopyMode keybinds ------------------------------------------------------

	local copy_mode = helpers.get_key_table(config, "copy_mode")

	local copy_mode_binds = {
		{
			key = "o",
			mods = "ALT",
			action = wezterm.action_callback(open_path_under_cursor),
		},
		{
			key = "n",
			mods = "ALT",
			action = act.CopyMode("NextMatch"),
		},
		{
			key = "N",
			mods = "ALT",
			action = act.CopyMode("PriorMatch"),
		},
		{
			key = "p",
			mods = "ALT",
			action = act.Search({
				Regex = PATH_LOCATION_SEARCH_REGEX,
			}),
		},
		{
			key = "o",
			mods = "NONE",

			action = act.QuickSelectArgs({
				label = "open path/location in nvim",

				patterns = {
					[[File\s+["'][^"']+["']\s*,\s*line\s+\d+]],
					[[[^ \t\n"'<>|]+:\d+(?::\d+)?]],
					[[[^ \t\n"'<>|]+\(\d+(?:,\d+)?\)]],
					[[(?:/|%./|%.%./|~/)[^ \t\n"'<>|]+]],
				},

				scope_lines = 1000,

				action = wezterm.action_callback(function(window, pane)
					open_location(window, pane)
				end),
			}),
		},
	}

	config.key_tables.copy_mode = helpers.update_table(copy_mode, copy_mode_binds)

	-- SearchMode keybinds ----------------------------------------------------

	local search_mode = helpers.get_key_table(config, "search_mode")

	local search_mode_binds = {
		-- Accept the current search match and immediately hand off to the
		-- path-opening pipeline. This is the "search, then open" fast path:
		-- Alt+u in global mode -> type a pattern -> Alt+o here -> nvim opens
		-- at the matched location.

		-- {
		-- 	key = "o",
		-- 	mods = "ALT",
		-- 	action = wezterm.action_callback(function(window, pane)
		-- 		-- Commit the search so Copy Mode is positioned at the match
		-- 		-- and the selection/match is materialized.
		-- 		window:perform_action(act.CopyMode("AcceptPattern"), pane)

		-- 		-- Now the Copy Mode cursor sits on the match. Delegate to the
		-- 		-- same callback Copy Mode uses, so behavior is identical.
		-- 		open_path_under_cursor(window, pane)
		-- 	end),
		-- },

		{
			key = "n",
			mods = "ALT",
			action = act.CopyMode("NextMatch"),
		},
		{
			key = "N",
			mods = "ALT",
			action = act.CopyMode("PriorMatch"),
		},
		{
			key = "p",
			mods = "ALT",
			action = act.Search({ Regex = PATH_LOCATION_SEARCH_REGEX }),
		},
		{
			key = "o",
			mods = "ALT",
			action = act.Multiple({
				act.CopyMode("Close"),
				wezterm.action_callback(open_path_under_cursor),
			}),
		},
	}

	config.key_tables.search_mode = helpers.update_table(search_mode, search_mode_binds)

	-- For debugging ----------------------------------------------------------

	local function get_keys(t)
		local keys = {}
		for key, _ in pairs(t) do
			table.insert(keys, key)
		end
		return keys
	end
	print(get_keys(wezterm.gui.default_key_tables()))

	return config
end

return M
