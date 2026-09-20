local helpers = require("wezterm-run.helpers")

local M = {}

--- Get the visual selection as a string.
--- Works in both visual mode (live) and after leaving visual mode ('' mark pair).
---@return string
function M.get_visual_selection()
	local mode = vim.fn.mode()
	local start_pos, end_pos

	if mode == "v" or mode == "V" or mode == "\22" then
		-- Called via <Cmd> mapping: still in visual mode, marks not set yet.
		-- 'v' is the anchor point, '.' is the cursor (either can be the "start").
		start_pos = vim.fn.getpos("v")
		end_pos = vim.fn.getpos(".")
		-- Normalise so start_pos is always the earlier position
		if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
			start_pos, end_pos = end_pos, start_pos
		end
	else
		-- Called after visual mode was exited normally; marks are reliable.
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
		if start_pos[2] == 0 then
			return ""
		end
	end

	local start_line = start_pos[2] - 1
	local start_col = start_pos[3] - 1
	local end_line = end_pos[2] - 1
	local end_col = end_pos[3]

	local line_len = #vim.api.nvim_buf_get_lines(0, end_line, end_line + 1, true)[1]
	end_col = math.min(end_col, line_len)

	local lines = vim.api.nvim_buf_get_text(0, start_line, start_col, end_line, end_col, {})
	return table.concat(lines, "\n")
end

--- If in normal mode, check for treesitter and if it is available, send current 'block'; otherwise fall back to sending line.
function M.get_current_block()
	-- Attempt treesitter first
	local ok, node = pcall(vim.treesitter.get_node)
	if ok and node then
		-- Walk up the tree to find a meaningful top-level block:
		--   a statement, definition, declaration, or expression at the root's direct child level.
		-- These type fragments cover most languages' top-level constructs.
		local block_types = {
			-- generic
			"block",
			"chunk",
			"body",
			-- statements / definitions
			"function_definition",
			"function_declaration",
			"method_definition",
			"class_definition",
			"class_declaration",
			"if_statement",
			"for_statement",
			"while_statement",
			"do_statement",
			"try_statement",
			"with_statement",
			"match_statement",
			"return_statement",
			"expression_statement",
			-- Lua-specific
			"local_function",
			"local_variable_declaration",
			"assignment_statement",
			-- Python-specific
			"decorated_definition",
			-- Rust-specific
			"impl_item",
			"function_item",
			"struct_item",
			"enum_item",
			"mod_item",
			-- Haskell-specific
			"function",
			"type_signature",
		}

		local block_type_set = {}
		for _, t in ipairs(block_types) do
			block_type_set[t] = true
		end

		-- Walk upward; stop when the parent is the root (depth 1 node) or we hit a recognised block type, whichever comes first.
		local candidate = node
		local parent = candidate:parent()
		while parent do
			local grandparent = parent:parent()
			if block_type_set[candidate:type()] and (grandparent == nil or grandparent:parent() == nil) then
				break
			end
			-- Also stop if the parent is the root: candidate is already top-level.
			if grandparent == nil then
				candidate = parent
				break
			end
			candidate = parent
			parent = grandparent
		end

		local start_row, start_col, end_row, end_col = candidate:range()
		local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
		if #lines > 0 then
			return table.concat(lines, "\n")
		end
	end

	-- Treesitter unavailable or returned nothing: fall back to current line.
	local line = vim.api.nvim_get_current_line()
	return line
end

return M
