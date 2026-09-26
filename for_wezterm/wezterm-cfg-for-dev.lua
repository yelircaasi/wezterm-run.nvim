local wezterm = require("wezterm")
local config = wezterm.config_builder()

local wezrun = dofile("/home/isaac/repos/wezterm-run.nvim/for_wezterm/wezterm-run.lua")
local wezterm_config = wezrun.defaults

wezrun.apply(config, wezterm_config)

return config

--TODO: add path identification, highlighting, and alt-n/alt-N keybinds for jumping
