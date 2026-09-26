local M = {}

--- Run a shell command and return stdout (trimmed), together with exit code.
---@param cmd string[]
---@return string output, integer exit_code
function M.run(cmd)
print("CALLING helpers.run")
	local out = {}
	local obj = vim.system(cmd, { text = true }):wait()
	return vim.trim(obj.stdout or ""), obj.code
end

--- Escape text so that it can be passed as a single shell argument.
--- We write via stdin -> this is only needed for the command list itself.
---@param  s  string
---@return    string
function M.shell_escape(s)
print("CALLING helpers.shell_escape")
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Ensure the text ends with a newline, so that REPLs execute it.
---@param text string
---@return     string
function M.ensure_newline(text)
print("CALLING helpers.ensure_newline")
	if text:sub(-1) ~= "\n" then
		return text .. "\n"
	end
	return text
end

---@param old  WeztermRunSetupOpts
---@param new? WeztermRunSetupOpts
---@return     WeztermRunSetupOpts
function M.merge_opts(old, new)
print("CALLING helpers.merge_opts")
	return vim.tbl_deep_extend("force", old, new or {})
end

function M.as_title(s)
print("CALLING helpers.as_title")
	return s:sub(1, 1):upper() .. s:sub(2):lower()
end

return M
