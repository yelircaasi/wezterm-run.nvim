# wezterm-run.nvim

Neovim plugin that simplifies code execution and output retrieval in Wezterm, focused on integration with neighboring panes.

Alternative name ideas:

- `wezterminator.nvim`
- `wezrepl.nvim` (if I expand REPL support)

## Scratch

- [ ] add the following to format info for picker:

```lua
format_item = function(p)
  local cwd_short = p.cwd:gsub("^file://[^/]*/", "/"):gsub("^/home/[^/]*/", "~/")
  return ("[win:%s tab:%s pane:%s] %s  %s"):format(
    p.window_id, p.tab_id, p.pane_id, p.title, cwd_short
  )
end,
```

- [ ] add `open_scratchpad()` to top-level, with default location and window ID, or allowing
      on-the-fly specification of path and/or window ID (scratch: shell file containing commands)
- [ ] clean up by moving top-level code from init.lua to api.lua
- [ ] configure (and make default) stripping of ansi formatting codes from output
- [ ] send line if in normal mode -> use treesitter to get block?
- [ ] package as plugin and call it wezterm-native.nvim (wezterm-integration.nvim?)
- [ ] add guard to detect whether in wezterm; no-op if not -> maybe not best idea; may want to send
      wezterm anyway; add setup option to control whether to setup even on non-wezterm
- [ ] add option to add output as virtual text?
- [ ] make user commands take arguments: e.g. `WeztermRunFile left` instead of `WeztermRunFileLeft`
- [ ] support other wezterm windows and 
https://github.com/willothy/flatten.nvim
https://github.com/mikesmithgh/kitty-scrollback.nvim -> adapt for wezterm

```lua
--[[
Some name ideas:

wezterm-integrate.nvim 
wezterm-integration.nvim
- wezterm-weave.nvim - wezterm + neovim, to weave them together
- warp.nvim - send text across pane boundaries
- conduit.nvim - a pipe between editors and terminals
- relay.nvim - relay text to another pane
- sling.nvim - sling text across to a pane
- wez.nvim - short and direct
- pane.nvim - simple, describes the domain
- repane.nvim - send/re-route to a pane
]]

--[[ USAGE:

-- manual setup
local wts = require("wezterm_send")

map_explicit({
    mode = "v",
    sequence = "<leader>wr",
    action = function()
  wts.send_selection({ direction = "Right" })
end,
})

map_explicit({
    mode = "v",
    sequence = "<leader>wp",
    action = function()
  wts.send_selection({ pattern = "python" })  -- matches title or cwd
end,
})

-- with default keymaps
require("wezterm_send").setup()
-- or customise:
require("wezterm_send").setup({ prefix = "<leader>s" })
]]

--- wezterm_send.lua
--- Send the current (or last) visual selection to a WezTerm pane.
---
--- Two targeting strategies are supported:
---   1. Direction  – send to the pane immediately Left/Right/Up/Down/Next/Prev
---                   relative to the nvim pane.
---   2. Search     – scan all panes and pick the first one whose title or cwd
---                   matches a pattern (e.g. "python", "ipython", "julia").
---
--- Quick-start (lazy.nvim / manual require):
---
---   local wts = require("wezterm_send")
---
---   -- Send selection to the pane on the right
---   vim.keymap.set("v", "<leader>wr", function()
---     wts.send_selection({ direction = "Right" })
---   end, { desc = "Send to WezTerm pane (right)" })
---
---   -- Send selection to a pane running python/ipython
---   vim.keymap.set("v", "<leader>wp", function()
---     wts.send_selection({ pattern = "python" })
---   end, { desc = "Send to WezTerm python pane" })
---
---   -- Interactive picker (vim.ui.select over all panes)
---   vim.keymap.set("v", "<leader>ww", function()
---     wts.send_selection({ pick = true })
---   end, { desc = "Pick WezTerm pane and send" })
```

## Roadmap / Brainstorming

### Feature ideas

- Pane/layout management
    - Smart split: open a terminal pane sized proportionally, remember it per-project, reuse it on subsequent opens rather than spawning a new one
    - Save and restore pane layouts per project/session — complementing things like `resession.nvim`
    - Focus the Neovim pane from a WezTerm keymap after running a command (round-trip focus)

- REPL integration
    - Detect the filetype and auto-attach to an appropriate REPL (already partially sketched in `run_current_file`)
    - Send the current cell (in a notebook-style workflow) — detect `# %%` markers
    - Bracketed paste awareness — detect if the target pane has a REPL that benefits from bracketed paste vs raw send

- Diagnostic / output integration
    - Parse output from the adjacent pane and populate the quickfix list — e.g. capture pytest/compiler output and `:copen` it automatically
    - Watch a pane for error patterns and surface them as Neovim diagnostics in real time using `vim.diagnostic`

- Navigation
    - `cd` the WezTerm pane's working directory to match the current Neovim buffer's directory, and vice versa
    - Jump to file:line references appearing in the terminal pane output — similar to what `vim-rhubarb` does for URLs

    **Visual**
    - Dim or style inactive panes via WezTerm's `set_right_status` / window decoration API when Neovim is focused
    - Show Neovim mode (normal/insert/visual) in the WezTerm tab title or status bar

### Sister WezTerm plugin (Lua)

WezTerm's config is already Lua, so a companion plugin is a natural fit.

- Pros

    - WezTerm's Lua API has things the CLI simply can't expose: `window:active_pane()`, `pane:get_foreground_process_info()`, `pane:get_lines_as_text()` with full metadata, event hooks like `mux-is-process-stateful`. We can't get foreground process info from `wezterm cli list` alone — the sister plugin closes that gap.
    - Bidirectional eventing becomes possible: WezTerm can *push* events to Neovim (via user vars or a socket) rather than Neovim having to poll via CLI calls. This enables things like "terminal command finished, refocus Neovim automatically."
    - Cleaner tab/status bar integration — we can render Neovim state (filename, mode, git branch) natively in WezTerm's tab bar without hacks.

- Cons

    - Two repos to maintain, version-lock between them, and document. Users have to configure both sides.
    - WezTerm's Lua API has no package manager — the sister plugin would be a manual `require` dropped into the user's `wezterm.lua`, which is a friction point.
    - Most of what a sister plugin enables can be approximated through the CLI or OSC escape sequences (e.g. setting user vars via `printf "\033]1337;SetUserVar=..."`), keeping everything on the Neovim side.
    - WezTerm's Lua API surface is less stable than Neovim's and more likely to break between releases.

- Conslusion

    A thin sister plugin is worth it for two specific things: foreground process detection (to know what's running in a pane without parsing titles) and push-based eventing (to trigger Neovim actions when a pane becomes idle). Everything else is better handled on the Neovim side via CLI calls, keeping the user-facing API surface in one place.


### Additional Notes

Wezterm does not support executing arbitrary Lua via the CLI — `wezterm cli` is purely a command/control interface (spawn, send-text, list, etc.), not a Lua REPL.

However there are a few approaches for bridging the gap:

#### Unix domain socket

WezTerm exposes a socket at the path in `$WEZTERM_UNIX_SOCKET`. The protocol is not publicly documented and is considered internal, but  it has been reverse-engineered.
It's fragile — likely to break between releases — so not a good foundation for a plugin.

#### User vars (OSC 1337)

The idiomatic WezTerm IPC mechanism going the *other* direction — Neovim → WezTerm — is setting user vars via an escape sequence:

```lua
io.write("\033]1337;SetUserVar=" .. base64(key) .. "=" .. base64(value) .. "\007")
```

WezTerm fires the `user-var-changed` event in its Lua config when this is received, which is where the sister plugin would live. This is the officially supported push channel and is stable.

**Going the other direction (WezTerm → Neovim)**
This is better handled via Neovim's own RPC socket (`$NVIM` env var):

```bash
nvim --server $NVIM --remote-send "<cmd>lua ...<cr>"
# or for proper RPC:
nvim --server $NVIM --remote-expr "luaeval('...')"
```

So the practical architecture for tight bidirectional integration is:
- **Neovim → WezTerm**: OSC user vars, consumed by `user-var-changed` in `wezterm.lua`
- **WezTerm → Neovim**: `nvim --server $NVIM --remote-expr` from within a WezTerm Lua callback

That gives me a clean bidirectional channel without touching the internal socket protocol.


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

- [ ] read: [lua options](https://wezterm.org/config/lua/general.html)
- [ ] read: [wezterm](https://wezterm.org/config/lua/wezterm/index.html)
- [ ] read: [pane](https://wezterm.org/config/lua/pane/index.html)
- [ ] read: [window](https://wezterm.org/config/lua/window/index.html)
- [ ] read: [run_child_process](https://wezterm.org/config/lua/wezterm/run_child_process.html)
- [ ] read: [background_child_process](https://wezterm.org/config/lua/wezterm/background_child_process.html)
- [ ] read: [read](https://wezterm.org/config/key-tables.html)
- [ ] read: [read](https://wezterm.org/config/lua/keyassignment/QuickSelect.html)
- [ ] read: [read](https://wezterm.org/quickselect.html)
- [ ] read: [read](https://wezterm.org/config/lua/keyassignment/QuickSelectArgs.html)
- [ ] read: [read](https://wezterm.org/config/lua/config/quick_select_patterns.html)
- [ ] read: [read](https://wezterm.org/config/lua/window/toast_notification.html)
- [ ] read: [read](https://wezterm.org/config/lua/keyassignment/index.html)
- [ ] TODO: use this: [Url](https://wezterm.org/config/lua/wezterm.url/Url.html)
