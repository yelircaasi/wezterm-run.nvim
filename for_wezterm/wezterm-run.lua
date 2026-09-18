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

local function ALT_to_abs_path(p, cwd)
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
local function ALT_token_under_cursor(line, col)
    if not line then
        return nil
    end

    local function is_path_char(c)
        return c ~= nil
            and c ~= ""
            and c:match("[%w%._%-%/~@+%%:]") ~= nil
    end

    -- col is a terminal cell index, while Lua strings are byte-indexed.
    --
    -- For normal ASCII text these are identical.  We walk UTF-8
    -- characters so that the conversion remains correct when the line
    -- contains non-ASCII text before the path.

    local byte_pos = 1
    local cell_pos = 0

    while byte_pos <= #line and cell_pos < col do
        local byte = line:byte(byte_pos)

        local width

        if byte < 0x80 then
            width = 1
        elseif byte < 0xE0 then
            width = 2
        elseif byte < 0xF0 then
            width = 3
        else
            width = 4
        end

        byte_pos = byte_pos + width
        cell_pos = cell_pos + 1
    end

    local start_i = byte_pos
    local end_i = byte_pos

    while start_i > 1 do
        local c = line:sub(start_i - 1, start_i - 1)

        if not is_path_char(c) then
            break
        end

        start_i = start_i - 1
    end

    while end_i <= #line do
        local c = line:sub(end_i, end_i)

        if not is_path_char(c) then
            break
        end

        end_i = end_i + 1
    end

    local token = line:sub(start_i, end_i - 1)

    if token == "" then
        return nil
    end

    return token
end

local function token_under_cursor(line, col)
    if not line or col >= #line then
        return nil
    end

    local function is_path_char(c)
        return c ~= nil
            and c ~= ""
            and c:match("[%w%._%-%/~@+%%:]") ~= nil
    end

    local i = col + 1

    local start_i = i
    while start_i > 1 and is_path_char(line:sub(start_i - 1, start_i - 1)) do
        start_i = start_i - 1
    end

    local end_i = i
    while end_i <= #line and is_path_char(line:sub(end_i, end_i)) do
        end_i = end_i + 1
    end

    return line:sub(start_i, end_i - 1)
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

local function get_cursor_line(pane)
    local pos = pane:get_cursor_position()
    if not pos then
        return nil, nil, nil
    end

    local dims = pane:get_dimensions()
    if not dims then
        return nil, nil, nil
    end

    -- pos.y is already a stable row index.
    local line = pane:get_text_from_region(
        0,
        pos.y,
        dims.cols - 1,
        pos.y
    )

    return line, pos.x, pos.y
end

local function get_path_under_cursor(window, pane)
    local line, col = get_cursor_line(pane)

    if not line then
        return nil
    end

    local token = token_under_cursor(line, col)

    if not token then
        window:toast_notification(
            "wezterm",
            "No token under cursor",
            nil,
            2000
        )
        return nil
    end

    wezterm.log_info(
        "cursor token = " .. token
    )

    local path_part, line_no, col_no =
        split_line_col(token)

    local cwd_uri = pane:get_current_working_dir()

    if not cwd_uri then
        return nil
    end

    local cwd = cwd_uri.file_path

    if not cwd then
        return nil
    end

    local abs_path = to_abs_path(
        path_part,
        cwd
    )

    return abs_path, line_no, col_no
end

-- local function find_running_nvim()

-- end

local function open_path(abs_path, nvim_server, line_no, col_no)
    if nvim_server then
        if line_no then
            local cmd = string.format(
                ":e %s<CR>",
                abs_path
            )

            cmd = cmd .. string.format(
                ":call cursor(%d,%d)<CR>",
                line_no,
                col_no or 1
            )

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
            table.insert(
                args,
                string.format(
                    "+call cursor(%d,%d)",
                    line_no,
                    col_no or 1
                )
            )
        end

        table.insert(args, abs_path)

        wezterm.run_child_process(args)
    end
end

local function ALT_open_path_under_cursor(window, pane)
	local abs_path = get_path_under_cursor()

	if not path_exists(abs_path) then
		window:toast_notification("wezterm", "Not a file: " .. abs_path, nil, 3000)
		return
	end

	local nvim_server = find_nvim_for_path(abs_path)

	open_path(abs_path, nvim_server)

	window:perform_action(act.CopyMode("Close"), pane)
end

local function open_path_under_cursor(window, pane)
    local abs_path, line_no, col_no =
        get_path_under_cursor(window, pane)

    if not abs_path then
        return
    end

    if not path_exists(abs_path) then
        window:toast_notification(
            "wezterm",
            "Not a file: " .. abs_path,
            nil,
            3000
        )
        return
    end

    local nvim_server =
        find_nvim_for_path(abs_path)

    open_path(
        abs_path,
        nvim_server,
        line_no,
        col_no
    )

    window:perform_action(
        act.CopyMode("Close"),
        pane
    )
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
