local wezterm = require("wezterm")
local config = wezterm.config_builder()

local wezrun = dofile("/home/isaac/repos/wezterm-run.nvim/for_wezterm/wezterm-run.lua")
wezrun.apply(config)

return config

--TODO: add path identification, highlighting, and alt-n/alt-N keybinds for jumping
