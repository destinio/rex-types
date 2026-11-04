# rex-types

Lua type definitions for [Rex](https://www.superlogical.com/rex)'s `rex` API, so your editor
treats `~/.config/rex/init.lua` like typed code: completion for every method and action name,
Rex's own documentation on hover, jump to definition, and a diagnostic when a field is wrong.

```
rex.bind("ctrl+a>|", "pane.
                     ┌──────────────────────────────────────────────┐
                     │ "pane.split"            Split Pane           │
                     │ "pane.split.auto"       Split Pane Best Fit  │
                     │ "pane.focus"            Focus Pane           │
                     │ "pane.zoom"             Zoom Pane            │
                     │ "pane.send_key"         Send Key             │
                     └──────────────────────────────────────────────┘

local r = rex.block.call("com.superlogical.terminal", "process", {})
r.foreground.|
             ┌───────────────────────────────────────────────────────┐
             │ argv0?   string  The first argument as the process …  │
             │ cwd?     string  The process's working directory …    │
             │ name     string  The file name of the executable …    │
             └───────────────────────────────────────────────────────┘
```

Works with any editor that uses [lua-language-server](https://luals.github.io): Neovim, VS Code,
Zed, Helix, IntelliJ.

## What's covered

| Surface | What you get |
|---|---|
| `rex.bind`, `rex.action`, `rex.exec`, `rex.layout`, timers, JSON, hosts | Hand-written from the [Lua API reference](https://www.superlogical.com/rex/docs/reference/lua-api.md), with a note on each function saying whether it works in `init.lua`, in `rex do` scripts, or both |
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

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash
```

That clones this repo to `~/.local/share/rex-types`, links it into your Rex config as `types/`,
writes a `.luarc.json` if you don't have one, and regenerates the API half against your own
server. ([Read the script](install.sh) first if you like.) Then open `~/.config/rex/init.lua`
and type `rex.` — in nvim, `:LspRestart` first if it was already open.

Run the same command again to update after a Rex upgrade.

Or by hand:

```sh
git clone https://github.com/destinio/rex-types && cd rex-types && ./install.sh
```

### Keeping the types outside your Rex config

If you'd rather not link anything into `~/.config/rex`, point lua-language-server at the clone
instead. In `~/.config/rex/.luarc.json`:

```json
{
  "runtime": { "version": "Lua 5.1" },
  "workspace": { "library": ["/absolute/path/to/rex-types/types"] }
}
```

([examples/luarc.json](examples/luarc.json) is the full file.) The absolute path is per-machine,
so if you share `.luarc.json` across machines, prefer the symlink the installer makes.

### Neovim with lazydev.nvim

```lua
{
  "folke/lazydev.nvim",
  ft = "lua",
  opts = {
    library = {
      { path = "~/.local/share/rex-types/types", words = { "rex%." } },
    },
  },
}
```

That loads the types in any Lua file that mentions `rex.`, including scripts you keep outside
your Rex config.

## Regenerating

```sh
rex do ~/.local/share/rex-types/types/generate.lua
```

`types/rex.api.lua` is generated from the server's own API description — `rex api call help.all`
plus `rex actions --json` — so it matches the Rex you're running rather than the Rex that was
current when this repo was written. Its header records the version and API revision it came from.

Action names come from the server plus **every connected app client**, so open the apps whose
actions you want (Mac, iOS) before regenerating. The committed copy was generated from the
version named in the file's header.

The generator also prints `action_overloads_missing_from_rex_lua`: if a Rex upgrade adds an
action that takes arguments, that's where it shows up, and the fix is one `---@overload` line
in `types/rex.lua` next to the others. Pull requests welcome.

## How it works

| File | Role |
|---|---|
| `types/rex.lua` | Hand-written definitions, `---@meta`, from the Lua API reference |
| `types/rex.api.lua` | Generated: 73 server methods, 41 session methods, every block method, every action name, 258 classes |
| `types/generate.lua` | The generator, run with `rex do` — reads `help.all` and `rex actions --json` |
| `examples/luarc.json` | The `.luarc.json` the installer writes |
| `install.sh` | Installs, updates (`git pull` + regenerate), or uninstalls (`--uninstall`) |

Both type files start with `---@meta`, so they only describe types — nothing in them runs, and
Rex never loads them.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash -s -- --uninstall
```

That removes the link and leaves your `.luarc.json` alone.

## License

MIT
