# rex-types

Lua type definitions for [Rex](https://www.superlogical.com/rex)'s `rex` API, so your editor
treats `~/.config/rex/init.lua` like typed code: completion for every method and action name,
Rex's own documentation on hover, jump to definition, and a diagnostic when a field is wrong.

```
rex.bind("ctrl+a>s", "pane.
                     ┌──────────────────────────────────────────────┐
                     │ "pane.split"            Split Pane           │
                     │ "pane.split.auto"       Split Pane Best Fit  │
                     │ "pane.focus"            Focus Pane           │
                     │ "pane.zoom"             Zoom Pane            │
                     │ "pane.send_key"         Send Key             │
                     └──────────────────────────────────────────────┘

local r = rex.block.call("com.superlogical.terminal", "process", {})
r.foreground.
             ┌───────────────────────────────────────────────────────┐
             │ argv0?   string  The first argument as the process …  │
             │ cwd?     string  The process's working directory …    │
             │ name     string  The file name of the executable …    │
             └───────────────────────────────────────────────────────┘
```

Half of it is hand-written from the [Lua API reference](https://www.superlogical.com/rex/docs/reference/lua-api.md).
The other half is **generated from your own server** — `rex api call help.all` and
`rex actions --json` — so it describes the Rex you're running, not the Rex that was current when
this repo was written.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash
```

That clones this repo to `~/.local/share/rex-types`, links it into your Rex config as `types/`,
writes a `.luarc.json` if you don't have one, and regenerates the API half against your server.
([Read the script](install.sh) first if you like.) Then open `~/.config/rex/init.lua` and type
`rex.` — in Neovim, `:LspRestart` first if the file was already open.

Run the same command again to update after a Rex upgrade.

```sh
./install.sh --check      # is this install healthy, and does it match my server?
./install.sh --uninstall  # remove the link; your .luarc.json is left alone
```

`--check` reports the Rex version, where `types/` points, whether the generated half matches your
server's API revision, whether `.luarc.json` sets Lua 5.1, whether lua-language-server is
installed, and what it says about your config directory.

By hand:

```sh
git clone https://github.com/destinio/rex-types && cd rex-types && ./install.sh
```

**Requirements.** bash, git, and [lua-language-server](https://luals.github.io) (tested on 3.14
and 3.19). The `rex` command is needed only to regenerate — the committed `types/rex.api.lua`
works on its own. macOS, Linux and FreeBSD; on Windows, clone the repo and use the
`workspace.library` form below, or install it as a Neovim plugin.

## What's covered

| Surface | What you get |
|---|---|
| `rex.bind`, `rex.action`, `rex.exec`, `rex.layout`, timers, JSON, hosts | Hand-written, with a note on each function saying whether it works in `init.lua`, in `rex do` scripts, or both |
| `rex.call` | One overload per server method — arguments and results typed, down to nested fields |
| `rex.session.*` | Every session method, with its argument and result classes |
| `rex.block.call` | Every block method's result; argument classes available by name |
| `rex.invoke`, `rex.client.queue` | The arguments of the actions that take any |
| action names, event names, flavors, creators, log levels | Completion with each one's title or description |
| `rex.on`, `rex.wait` | A typed payload per event — `ev.exit_code`, `ev.pwd`, `ev.foreground` |

Two places where lua-language-server can't type the argument table, because it resolves an
overload on a call's **first** argument and there that argument is the key or the creator:

| Call | Workaround |
|---|---|
| `rex.bind(key, action, args)` | Name the class on a local, or write it as `rex.invoke`, which is typed |
| `rex.block.call(creator, method, args)` | Same. The **result** is typed per method either way |

```lua
---@type rex.action.pane.resize.args
local args = { direction = "left", amount = 5 }   -- completion and checking in here
rex.bind("ctrl+a>H", "pane.resize", args)
```

## Editors

The installer's `.luarc.json` is all lua-language-server needs, so **Neovim, VS Code, Zed and
Helix all work with no further setup** — they read `.luarc.json` from the directory they open.
VS Code needs the [Lua extension](https://marketplace.visualstudio.com/items?itemName=sumneko.lua);
Neovim needs lua_ls enabled (kickstart and LazyVim both do by default).

Two cases need a little more:

**Rex scripts kept outside your Rex config** — point lua-language-server at the clone from
whatever workspace they live in:

```json
{
  "runtime": { "version": "Lua 5.1" },
  "workspace": { "library": ["/absolute/path/to/rex-types/types"] }
}
```

([examples/luarc.json](examples/luarc.json) is the full file the installer writes.) The absolute
path doesn't travel between machines, so inside your Rex config prefer the symlink.

**Neovim, as a plugin** — see below. That also covers scripts outside your Rex config, with no
`.luarc.json` at all.

## Install as a Neovim plugin

This repo is a Neovim plugin too, so your plugin manager can be the thing that installs the
definitions. `setup()` hands them to lua_ls for Lua buffers that mention `rex.`, appending to
whatever library your config already set — nothing else to configure, and it works for Rex
scripts anywhere on disk, not just in `~/.config/rex`.

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add { 'https://github.com/destinio/rex-types' }
require('rex-types').setup()
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'destinio/rex-types', ft = 'lua', config = true }
```

With [lazydev.nvim](https://github.com/folke/lazydev.nvim), skip `setup()` and let lazydev own it
— the plugin-relative path means no absolute paths in your config:

```lua
{
  'folke/lazydev.nvim',
  ft = 'lua',
  dependencies = { 'destinio/rex-types' },
  opts = {
    library = {
      { path = 'rex-types/types', words = { 'rex%.' } },
    },
  },
}
```

Options, if the defaults don't suit:

```lua
require('rex-types').setup {
  path = '/somewhere/else/types',                  -- default: this plugin's own types/
  enabled = function(buf, client) return true end, -- default: the buffer mentions `rex.`
}
```

Plugin mode leaves `runtime.version` to your own config — LuaJIT, which is 5.1-compatible, so
Rex's Lua 5.1 is described correctly either way. Inside `~/.config/rex`, the installer's
`.luarc.json` pins it exactly.

## Regenerating

```sh
rex do ~/.local/share/rex-types/types/generate.lua
```

The file's header records the Rex version, the API revision, and which clients it was built from.
`install.sh --check` compares that revision with your running server and tells you when to re-run.

Action names come from the server **plus every connected app client**, so open the apps whose
actions you want (Mac, iOS) before regenerating.

The generator also prints `action_overloads_missing_from_rex_lua`: if a Rex upgrade adds an action
that takes arguments, that's where it shows up, and the fix is one `---@overload` line in
`types/rex.lua` next to the others.

## Contributing

```sh
./check.sh              # what CI runs
./check.sh --generate   # regenerate first, then check
```

`check.sh` checks the definitions four ways: the fixtures must stay clean with `types/` linked
into the workspace, clean again with `types/` named in `workspace.library`, every mistake in
`test/negative.lua` must still be reported, and every action that takes arguments must still have
an overload in `rex.lua`.

- `test/fixture.lua` — ordinary use of the config-file API. Zero diagnostics expected; anything
  reported there is a bug in the definitions, not in the fixture.
- `test/script.lua` — the same for the `rex do` API: events, timers, waiting, exec handles.
- `test/negative.lua` — deliberate mistakes, each marked with the diagnostic it must produce.

Set `LUA_LS=/path/to/lua-language-server` if it isn't on your `PATH` (the script also looks in
Mason's directory).

## How it works

| File | Role |
|---|---|
| `types/rex.lua` | Hand-written definitions, `---@meta`, from the Lua API reference |
| `types/rex.api.lua` | Generated: every server method, session method, block method and action name |
| `types/generate.lua` | The generator, run with `rex do` — reads `help.all` and `rex actions --json` |
| `examples/luarc.json` | The `.luarc.json` the installer writes |
| `install.sh` | Install, update, `--check`, `--uninstall` |
| `check.sh` | The checks above |
| `lua/rex-types/init.lua` | The Neovim plugin half: `setup()` registers `types/` with lua_ls |
| `test/` | Fixtures: correct use, and mistakes that must be caught |

Both type files start with `---@meta`, so they only describe types — nothing in them runs, and Rex
never loads them. Rex loads `init.lua` only.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash -s -- --uninstall
```

## License

MIT
