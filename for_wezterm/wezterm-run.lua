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

-- helpers to sort --------------------------------------------------------------

local helpers = {
	-- This is deliberately broad.  The Lua parser below decides whether the
	-- resulting match is actually a filesystem path.
	PATH_LOCATION_SEARCH_REGEX = [[
(?:
    File\s+["'][^"']+["']\s*,\s*line\s+\d+
  |
    [^ \t\n"'<>|]+:\d+(?::\d+)?
  |
    [^ \t\n"'<>|]+\(\d+(?:,\d+)?\)
)
]],

	PATH_LOCATION_REGEX = [[
(?x)
(?:
    # Python traceback:
    #   File "/foo/bar.py", line 42
    File \s+ ["'] (?<python_path>[^"']+) ["']
        , \s* line \s+ (?<python_line>\d+)

  |

    # C/C++/Rust/GCC/etc:
    #   foo/bar.rs:42
    #   foo/bar.rs:42:17
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

    # MSVC / Rust-ish:
    #   foo.cpp(42)
    #   foo.cpp(42,17)
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

    # Plain paths. Keep this last because the location patterns
    # should consume the :line / (line,col) suffix.
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
]],
	parse_location = function(text)
		if not text then
			return nil
		end

		text = text:gsub("^%s+", ""):gsub("%s+$", "")

		-------------------------------------------------------------------------
		-- Python traceback
		--
		-- File "/home/me/foo.py", line 42
		-------------------------------------------------------------------------

		local path, line = text:match([[File%s+["']([^"']+)["']%s*,%s*line%s+(%d+)]])

		if path then
			return {
				path = path,
				line = tonumber(line),
			}
		end

		-------------------------------------------------------------------------
		-- path:line:column
		-------------------------------------------------------------------------

		path, line, col = text:match("^(.+):(%d+):(%d+)$")

		if path then
			return {
				path = path,
				line = tonumber(line),
				column = tonumber(col),
			}
		end

		-------------------------------------------------------------------------
		-- path:line
		-------------------------------------------------------------------------

		path, line = text:match("^(.+):(%d+)$")

		if path then
			return {
				path = path,
				line = tonumber(line),
			}
		end

		-------------------------------------------------------------------------
		-- path(line,column)
		-------------------------------------------------------------------------

		path, line, col = text:match("^(.+)%((%d+),(%d+)%)$")

		if path then
			return {
				path = path,
				line = tonumber(line),
				column = tonumber(col),
			}
		end

		-------------------------------------------------------------------------
		-- path(line)
		-------------------------------------------------------------------------

		path, line = text:match("^(.+)%((%d+)%)$")

		if path then
			return {
				path = path,
				line = tonumber(line),
			}
		end

		-------------------------------------------------------------------------
		-- Plain path
		-------------------------------------------------------------------------

		return {
			path = text,
		}
	end,

	normalize_path = function(path, cwd)
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

		-- Absolute path.
		if path:sub(1, 1) == "/" then
			return path
		end

		-- Relative path.
		if cwd:sub(-1) == "/" then
			return cwd .. path
		end

		return cwd .. "/" .. path
	end,

	path_exists = function(path)
		local success = wezterm.run_child_process({
			"test",
			"-e",
			path,
		})

		return success
	end,

	search_next_path = function(wz_act)
		return wz_act.Search({
			Regex = PATH_LOCATION_SEARCH_REGEX,
		})
	end,

	trim = function(s)
		return (s:gsub("^%s*(.-)%s*$", "%1"))
	end,

	path_exists = function(p)
		local ok = wezterm.run_child_process({ "sh", "-c", 'test -e "$1"', "--", p })
		return ok
	end,

	to_abs_path = function(p, cwd)
		p = expand_tilde(p)

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
	end,

	shell_quote = function(s)
		return "'" .. s:gsub("'", "'\\''") .. "'"
	end,

	expand_tilde = function(p)
		if p:sub(1, 1) == "~" then
			return wezterm.home_dir .. p:sub(2)
		end
		return p
	end,
}

local domain_helpers = {
	token_under_cursor = function(line, col)
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

		-- If the cursor is beyond the end of the line, there's no token.
		if byte_pos > #line + 1 then
			return nil
		end

		-- If the cursor is on the cell immediately after the token, use
		-- the preceding character as the starting point.
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
	end,

	-- Split "path:line:col" or "path:line" into its constituent parts.
	split_line_col = function(token)
		local path, line, col = token:match("^(.-):(%d+):(%d+)$")
		if path then
			return path, tonumber(line), tonumber(col)
		end
		path, line = token:match("^(.-):(%d+)$")
		if path then
			return path, tonumber(line), nil
		end
		return token, nil, nil
	end,

	-- Find a running nvim server whose cwd is a parent of abs_path.
	find_nvim_for_path = function(abs_path)
		local handle = io.popen("nvr --serverlist 2>/dev/null")
		if not handle then
			return nil
		end
		for srv in handle:lines() do
			srv = trim(srv)
			if srv ~= "" then
				local cwd_handle = io.popen(
					string.format('nvr --servername %s --remote-expr "getcwd()" 2>/dev/null', shell_quote(srv))
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
	end,

	get_cursor_line = function(pane)
		local pos = pane:get_cursor_position()
		if not pos then
			return nil, nil, nil
		end

		local dims = pane:get_dimensions()
		if not dims then
			return nil, nil, nil
		end

		-- pos.y is already a stable row index.
		local line = pane:get_text_from_region(0, pos.y, dims.cols - 1, pos.y)

		return line, pos.x, pos.y
	end,

	get_path_under_cursor = function(window, pane)
		local line, col = get_cursor_line(pane)

		if not line then
			return nil
		end

		local token = token_under_cursor(line, col)

		if not token then
			window:toast_notification("wezterm", "No token under cursor", nil, 2000)
			return nil
		end

		wezterm.log_info("cursor token = " .. token)

		local path_part, line_no, col_no = split_line_col(token)

		local cwd_uri = pane:get_current_working_dir()

		if not cwd_uri then
			return nil
		end

		local cwd = cwd_uri.file_path

		if not cwd then
			return nil
		end

		local abs_path = to_abs_path(path_part, cwd)

		return abs_path, line_no, col_no
	end,

	open_path = function(wz, abs_path, nvim_server, line_no, col_no)
		if nvim_server then
			if line_no then
				local cmd = string.format(":e %s<CR>", abs_path)

				cmd = cmd .. string.format(":call cursor(%d,%d)<CR>", line_no, col_no or 1)

				wz.run_child_process({
					"nvr",
					"--servername",
					nvim_server,
					"--remote-send",
					cmd,
				})
			else
				wz.run_child_process({
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

			wz.run_child_process(args)
		end
	end,
}

-- public API

local M = {}

function M.apply(wezterm, config)
	print("applying")
	config.keys = config.keys or {}
	local act = wezterm.action
	local copy_mode = wezterm.gui.default_key_tables().copy_mode or {}

	local function open_path_under_cursor(window, pane, wezterm_action)
		local abs_path, line_no, col_no = get_path_under_cursor(window, pane)

		if not abs_path then
			return
		end

		if not path_exists(abs_path) then
			window:toast_notification("wezterm", "Not a file: " .. abs_path, nil, 3000)
			return
		end

		local nvim_server = find_nvim_for_path(abs_path)

		open_path(abs_path, nvim_server, line_no, col_no)

		window:perform_action(act.CopyMode("Close"), pane)
	end

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

	local set_copy_mode_keybinds = function(cm)
		table.insert(cm, {
			key = "o",
			mods = "ALT",
			action = wezterm.action_callback(open_path_under_cursor),
		})

		-- table.insert(copy_mode, {
		-- 	key = "n",
		-- 	mods = "ALT",
		-- 	action = act.CopyMode("NextMatch"),
		-- })

		-- table.insert(copy_mode, {
		-- 	key = "N",
		-- 	mods = "ALT",
		-- 	action = act.CopyMode("PriorMatch"),
		-- })

		-- table.insert(copy_mode, {
		-- 	key = "p",
		-- 	mods = "ALT",
		-- 	action = act.Search({
		-- 		Regex = PATH_LOCATION_SEARCH_REGEX,
		-- 	}),
		-- })

		-- table.insert(copy_mode, {
		-- 	key = "o",
		-- 	mods = "NONE",

		-- 	action = act.QuickSelectArgs({
		-- 		label = "open path/location in nvim",

		-- 		patterns = {
		-- 			[[File\s+["'][^"']+["']\s*,\s*line\s+\d+]],
		-- 			[[[^ \t\n"'<>|]+:\d+(?::\d+)?]],
		-- 			[[[^ \t\n"'<>|]+\(\d+(?:,\d+)?\)]],
		-- 			[[(?:/|%./|%.%./|~/)[^ \t\n"'<>|]+]],
		-- 		},

		-- 		scope_lines = 1000,

		-- 		action = wezterm.action_callback(function(window, pane)
		-- 			open_location(window, pane)
		-- 		end),
		-- 	}),
		-- })
		return cm
	end
	config.key_tables.copy_mode = set_copy_mode_keybinds(cm)

	return config
end

return M
