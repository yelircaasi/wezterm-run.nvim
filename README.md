# wezterm-run.nvim
Neovim plugin that simplifies code execution and output retrieval in Wezterm, focused on integration with neighboring panes.


## Wezterm helper (`./for_wezterm/wezterm-run.lua`)

Provides vim-like navigation of WezTerm scrollback + "open path under cursor in nvim".

Usage from `wezterm.lua`:

```lua
require('wezterm-run').apply(config)
```

Dependencies:

- neovim-remote (`nvr`) on $PATH:  `pip3 install neovim-remote` or `nix-shell -p neovim-remote`

Keybindings created:

- `ALT+u`: enter Copy Mode (already Vim-keyed: hjkl w b e 0 $ gg G v y / ?)

- `ALT+o`: (inside Copy Mode) open the path under the cursor in nvim

## Running Wezterm with Development Configuration

```sh
wezterm --config-file $HOME/repos/wezterm-run.nvim/for_wezterm/wezterm-cfg-for-dev.lua
```

## Roadmap

- [ ] [read](https://wezterm.org/config/lua/keyassignment/QuickSelect.html)
- [ ] [read](https://wezterm.org/quickselect.html)
- [ ] [read](https://wezterm.org/config/lua/keyassignment/QuickSelectArgs.html)
- [ ] [read](https://wezterm.org/config/lua/config/quick_select_patterns.html)
- [ ] [read](https://wezterm.org/config/lua/window/toast_notification.html)
