---@meta
--- Type definitions for the `rex` global that Rex exposes to `init.lua` and to
--- scripts run with `rex do`. Hand-written from the Lua API reference:
--- https://www.superlogical.com/rex/docs/reference/lua-api.md
---
--- Rex runs Lua 5.1 with the full standard library. `io.popen` and `os.execute`
--- raise an error; use `rex.exec` instead.
---
--- Server methods, client actions and block methods live in `rex.api.lua`,
--- which is generated from this server. Regenerate it with:
---     rex do ~/.config/rex/types/generate.lua

---Where a function works:
--- * **Config** — the configuration file (`~/.config/rex/init.lua`).
--- * **Script** — a script run with `rex do`. Names marked *script only* are
---   `nil` in the configuration file, so a shared file must check for them.
---@class rex
---@field session rex.SessionAPI Session methods. `session_id` is filled in when left out.
---@field block rex.BlockAPI Block methods.
---@field client rex.ClientAPI Asking the client to perform its own actions.
---@field layout rex.LayoutAPI Builders for the `layout` tables `new_window`, `new_split` and `new_layer` take.
---@field json rex.JsonAPI JSON encoding and decoding.
---@field exec rex.ExecAPI Run a command. Callable: `rex.exec(argv, opts)`.
---@field args table Script only. The script's arguments. Empty when none were passed.
---@field session_id string Script only. The session the script runs against.
---@field block_id string|nil Script only. The block the script runs against, if any.
rex = {}

--------------------------------------------------------------------------------
-- Context and events
--------------------------------------------------------------------------------

---The context an action, key binding, event handler or timer is called with.
---A field Rex doesn't know is absent.
---@class rex.Ctx
---@field session_id string|nil The session the work belongs to.
---@field block_id string|nil The block the work belongs to.
---@field client_id string|nil The client that asked for the work.
---@field origin string|nil What started the work, such as `key`, `palette`, `cli` or `timer`.
---@field server string|nil The server the work came from.

---A key event passed to a function binding.
---@class rex.KeyEvent
---@field keybinding string The key that was pressed.
---@field prefix string[]|nil For a sequence, the keys pressed before it.

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

---Bind a key to an action by name.
---
---`key` is a single key (`cmd+d`), a sequence written with `>`
---(`ctrl+a>shift+\`), or either one prefixed with a mode and a slash
---(`resize/h`).
---
---```lua
---rex.bind("cmd+d", "pane.split", { direction = "right" })
---```
---
---*Config. In a script this is accepted and does nothing.*
---
---`args` stays an untyped table here: lua-language-server resolves an overload
---on the first argument, which is the key, so it can't type `args` per action.
---For completion inside the table, name the action's argument class on a local:
---
---```lua
----- completion and checking for `direction` inside the braces
-----@type rex.action.pane.split.args
---local args = { direction = "right" }
---rex.bind("cmd+d", "pane.split", args)
---```
---
---`rex.invoke("pane.split", { ... })` is typed directly, because there the
---action name is the first argument.
---@param key string
---@param action rex.Action The action's name. `rex actions` lists them.
---@param args? table Arguments passed to the action. See the note above.
---@overload fun(key: string, fn: fun(ctx: rex.Ctx, ev: rex.KeyEvent): boolean?)
function rex.bind(key, action, args) end

---Remove the bindings of a key, in this file and in the client's defaults.
---Returns how many of this file's bindings it removed.
---
---`target` limits the removal to bindings with that action name or function.
---`rex.unbind("mode/key")` also blocks the key in that mode.
---@param key string
---@param target? rex.Action|function
---@return integer removed
---@overload fun(mode: { mode: string }): integer Remove a whole mode: its bindings, blocked keys and options.
---@overload fun(binding: rex.Binding): integer Remove one binding returned by `rex.bindings`.
function rex.unbind(key, target) end

---Declare a key mode and set its options.
---
---*Config, at load only.*
---@param name string
---@param options? { exclusive?: boolean } `exclusive` keeps unbound keys from reaching the terminal. Defaults to `false`.
function rex.mode(name, options) end

---One key binding, as returned by `rex.bindings`.
---@class rex.Binding
---@field key string The key or sequence, without its mode.
---@field mode string|nil The mode, or `nil`.
---@field action string|nil The action name, or `nil` for a function binding.
---@field fn function|nil The function, or `nil` for an action binding.
---@field args table|nil The arguments table, or `nil`.
---@field source string Where it was bound, such as `keys.lua:3`.

---The bindings this file and the files it requires have made so far, in order.
---
---*Config, at load only.*
---@param filter? { key?: string, mode?: string, action?: string }
---@return rex.Binding[]
function rex.bindings(filter) end

---One declared mode.
---@class rex.Mode
---@field name string
---@field exclusive boolean
---@field source string

---The modes declared or bound so far.
---
---*Config, at load only.*
---@return rex.Mode[]
function rex.modes() end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

---An action definition.
---@class rex.ActionSpec
---@field name string Required. Lowercase letters, digits and underscores.
---@field title string Required. Shown in the command palette.
---@field run fun(ctx: rex.Ctx, args: table): any Required. The action's body. Its return value is the action's result.
---@field description? string A longer explanation.
---@field category? string A group for the palette. Defaults to `Actions`.
---@field keywords? string Extra words for palette search.
---@field args? table<string, rex.ArgType>|table Argument types, or a JSON Schema.
---@field repeats? boolean Run again while the key is held.

---An argument type in `rex.action{ args = ... }`. A trailing `?` marks the
---argument as optional, such as `"string?"`.
---@alias rex.ArgType string
---| "string"
---| "number"
---| "integer"
---| "boolean"
---| "object"
---| "array"
---| "any"
---| "string?"
---| "number?"
---| "integer?"
---| "boolean?"
---| "object?"
---| "array?"
---| "any?"

---Define an action. It can then be bound to a key, run from the command
---palette, or run with `rex do <name>`.
---
---```lua
---rex.action {
---  name = "tests",
---  title = "Run Tests",
---  args = { filter = "string?" },
---  run = function(ctx, args)
---    return rex.exec({ "npm", "test" }).ok
---  end,
---}
---```
---
---*Config and Script, at load only.*
---@param spec rex.ActionSpec
function rex.action(spec) end

---Run an action and return its result, or `nil` and an error message.
---
---In the configuration file only that file's own actions can be invoked. In a
---script, a name the script doesn't define is run by the server, so a script
---can invoke the configuration file's actions. Calls nest up to 16 deep.
---@param name rex.Action
---@param args? table
---@return any result
---@return string|nil err
---@overload fun(name: "client.appearance.switch_mode", args: rex.action.client.appearance.switch_mode.args): any, string|nil
---@overload fun(name: "client.mode.enter", args: rex.action.client.mode.enter.args): any, string|nil
---@overload fun(name: "client.tab.goto", args: rex.action.client.tab.goto.args): any, string|nil
---@overload fun(name: "client.tab.move", args: rex.action.client.tab.move.args): any, string|nil
---@overload fun(name: "client.theme.change", args?: rex.action.client.theme.change.args): any, string|nil
---@overload fun(name: "client.theme.import", args: rex.action.client.theme.import.args): any, string|nil
---@overload fun(name: "com.superlogical.onboarding.set_step", args: rex.action.com.superlogical.onboarding.set_step.args): any, string|nil
---@overload fun(name: "com.superlogical.terminal.blob_read", args?: rex.action.com.superlogical.terminal.blob_read.args): any, string|nil
---@overload fun(name: "com.superlogical.terminal.clipboard_read", args?: rex.action.com.superlogical.terminal.clipboard_read.args): any, string|nil
---@overload fun(name: "com.superlogical.terminal.format", args?: rex.action.com.superlogical.terminal.format.args): any, string|nil
---@overload fun(name: "com.superlogical.terminal.list_dir", args?: rex.action.com.superlogical.terminal.list_dir.args): any, string|nil
---@overload fun(name: "com.superlogical.terminal.resize", args: rex.action.com.superlogical.terminal.resize.args): any, string|nil
---@overload fun(name: "com.superlogical.terminal.set_theme", args?: rex.action.com.superlogical.terminal.set_theme.args): any, string|nil
---@overload fun(name: "com.superlogical.terminal.write", args: rex.action.com.superlogical.terminal.write.args): any, string|nil
---@overload fun(name: "pane.focus", args: rex.action.pane.focus.args): any, string|nil
---@overload fun(name: "pane.move", args: rex.action.pane.move.args): any, string|nil
---@overload fun(name: "pane.resize", args: rex.action.pane.resize.args): any, string|nil
---@overload fun(name: "pane.send_key", args: rex.action.pane.send_key.args): any, string|nil
---@overload fun(name: "pane.split", args: rex.action.pane.split.args): any, string|nil
---@overload fun(name: "session.collapse", args?: rex.action.session.collapse.args): any, string|nil
---@overload fun(name: "session.collapse_others", args?: rex.action.session.collapse_others.args): any, string|nil
---@overload fun(name: "session.expand", args?: rex.action.session.expand.args): any, string|nil
---@overload fun(name: "session.select", args: rex.action.session.select.args): any, string|nil
function rex.invoke(name, args) end

--------------------------------------------------------------------------------
-- Calling Rex
--------------------------------------------------------------------------------

-- rex.call is declared in rex.api.lua, which gives it one overload per server
-- method so that its arguments and its result are typed. Its signature is
-- `rex.call(method, args?) -> result|nil, err`.

---@class rex.ClientAPI
local client = {}

---Ask the client to perform one of its own actions, such as `pane.zoom`.
---
---In an action, queued actions run in order after `run` returns and are
---discarded if it fails. In a script each one is performed immediately.
---Raises an error when there is no client to ask.
---@param name rex.Action
---@param args? table
---@overload fun(name: "client.appearance.switch_mode", args: rex.action.client.appearance.switch_mode.args)
---@overload fun(name: "client.mode.enter", args: rex.action.client.mode.enter.args)
---@overload fun(name: "client.tab.goto", args: rex.action.client.tab.goto.args)
---@overload fun(name: "client.tab.move", args: rex.action.client.tab.move.args)
---@overload fun(name: "client.theme.change", args?: rex.action.client.theme.change.args)
---@overload fun(name: "client.theme.import", args: rex.action.client.theme.import.args)
---@overload fun(name: "pane.focus", args: rex.action.pane.focus.args)
---@overload fun(name: "pane.move", args: rex.action.pane.move.args)
---@overload fun(name: "pane.resize", args: rex.action.pane.resize.args)
---@overload fun(name: "pane.send_key", args: rex.action.pane.send_key.args)
---@overload fun(name: "pane.split", args: rex.action.pane.split.args)
---@overload fun(name: "session.collapse", args?: rex.action.session.collapse.args)
---@overload fun(name: "session.collapse_others", args?: rex.action.session.collapse_others.args)
---@overload fun(name: "session.expand", args?: rex.action.session.expand.args)
---@overload fun(name: "session.select", args: rex.action.session.select.args)
function client.queue(name, args) end

rex.client = client

--------------------------------------------------------------------------------
-- Hosts and other servers
--------------------------------------------------------------------------------

---Declare another Rex server you connect to.
---
---*Config, at load only.*
---@param host { label: string, endpoints?: string[], endpoint?: string, id?: string, icon?: string }
function rex.host(host) end

---The labels of the other servers available to the running action or script.
---@return string[]
function rex.servers() end

---The same `session`, `block` and `call` functions as `rex`, with calls going
---to another host. Raises an error for an unknown label. Calls made through it
---don't fill in a `session_id` or `block_id`.
---@param label string A label from `rex.servers()`.
---@return rex.Server
function rex.server(label) end

---@class rex.Server
---@field session rex.SessionAPI
---@field block rex.BlockAPI
---@field call fun(method: rex.Method, args?: table): table|nil, string|nil

--------------------------------------------------------------------------------
-- Events (scripts run with `rex do` only)
--------------------------------------------------------------------------------

---Call `fn` each time `event` happens. `ev` holds the event's fields; `ctx`
---has `session_id`, and `block_id` for a block event.
---
---A script that registers handlers keeps running after its last line and runs
---handlers as events arrive, one at a time, until `rex.stop` is called.
---
---*Script only. In the configuration file this warns and does nothing.*
---@param event rex.Event
---@param fn fun(ctx: rex.Ctx, ev: table)
---@overload fun(event: "window_created", fn: fun(ctx: rex.Ctx, ev: rex.event.window_created))
---@overload fun(event: "window_closed", fn: fun(ctx: rex.Ctx, ev: rex.event.window_closed))
---@overload fun(event: "window_label_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.window_label_changed))
---@overload fun(event: "active_window_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.active_window_changed))
---@overload fun(event: "block_created", fn: fun(ctx: rex.Ctx, ev: rex.event.block_created))
---@overload fun(event: "block_closed", fn: fun(ctx: rex.Ctx, ev: rex.event.block_closed))
---@overload fun(event: "session_label_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.session_label_changed))
---@overload fun(event: "session_view_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.session_view_changed))
---@overload fun(event: "client_connected", fn: fun(ctx: rex.Ctx, ev: rex.event.client_connected))
---@overload fun(event: "client_disconnected", fn: fun(ctx: rex.Ctx, ev: rex.event.client_disconnected))
---@overload fun(event: "client_connection_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.client_connection_changed))
---@overload fun(event: "creator_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.creator_changed))
---@overload fun(event: "terminal.child_exited", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_child_exited))
---@overload fun(event: "terminal.pwd_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_pwd_changed))
---@overload fun(event: "terminal.title_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_title_changed))
---@overload fun(event: "terminal.bell", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_bell))
---@overload fun(event: "terminal.process_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_process_changed))
---@overload fun(event: "terminal.desktop_notification", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_desktop_notification))
---@overload fun(event: "terminal.progress_report", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_progress_report))
---@overload fun(event: "terminal.clipboard_written", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_clipboard_written))
---@overload fun(event: "terminal.program_status_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_program_status_changed))
---@overload fun(event: "terminal.program_status_removed", fn: fun(ctx: rex.Ctx, ev: rex.event.terminal_program_status_removed))
---@overload fun(event: "session_created", fn: fun(ctx: rex.Ctx, ev: rex.event.session_created))
---@overload fun(event: "session_destroyed", fn: fun(ctx: rex.Ctx, ev: rex.event.session_destroyed))
---@overload fun(event: "client_joined", fn: fun(ctx: rex.Ctx, ev: rex.event.client_joined))
---@overload fun(event: "client_left", fn: fun(ctx: rex.Ctx, ev: rex.event.client_left))
---@overload fun(event: "client_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.client_changed))
---@overload fun(event: "keymap_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.keymap_changed))
---@overload fun(event: "hosts_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.hosts_changed))
---@overload fun(event: "tailscale_status_changed", fn: fun(ctx: rex.Ctx, ev: rex.event.tailscale_status_changed))
function rex.on(event, fn) end

---Block until `event` happens, and return its fields and context. Returns
---`nil` and `"timeout"` if `timeout` seconds pass first.
---
---*Script only.*
---@param event rex.Event
---@param filter? table|fun(ev: table, ctx: rex.Ctx): boolean Fields the event must match, or a predicate.
---@param timeout? number Seconds to wait.
---@return table|nil ev
---@return rex.Ctx|string|nil ctx_or_err `"timeout"` when the wait timed out.
---@overload fun(event: "window_created", filter?: table|(fun(ev: rex.event.window_created, ctx: rex.Ctx): boolean), timeout?: number): rex.event.window_created|nil, rex.Ctx|string|nil
---@overload fun(event: "window_closed", filter?: table|(fun(ev: rex.event.window_closed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.window_closed|nil, rex.Ctx|string|nil
---@overload fun(event: "window_label_changed", filter?: table|(fun(ev: rex.event.window_label_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.window_label_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "active_window_changed", filter?: table|(fun(ev: rex.event.active_window_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.active_window_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "block_created", filter?: table|(fun(ev: rex.event.block_created, ctx: rex.Ctx): boolean), timeout?: number): rex.event.block_created|nil, rex.Ctx|string|nil
---@overload fun(event: "block_closed", filter?: table|(fun(ev: rex.event.block_closed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.block_closed|nil, rex.Ctx|string|nil
---@overload fun(event: "session_label_changed", filter?: table|(fun(ev: rex.event.session_label_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.session_label_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "session_view_changed", filter?: table|(fun(ev: rex.event.session_view_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.session_view_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "client_connected", filter?: table|(fun(ev: rex.event.client_connected, ctx: rex.Ctx): boolean), timeout?: number): rex.event.client_connected|nil, rex.Ctx|string|nil
---@overload fun(event: "client_disconnected", filter?: table|(fun(ev: rex.event.client_disconnected, ctx: rex.Ctx): boolean), timeout?: number): rex.event.client_disconnected|nil, rex.Ctx|string|nil
---@overload fun(event: "client_connection_changed", filter?: table|(fun(ev: rex.event.client_connection_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.client_connection_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "creator_changed", filter?: table|(fun(ev: rex.event.creator_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.creator_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.child_exited", filter?: table|(fun(ev: rex.event.terminal_child_exited, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_child_exited|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.pwd_changed", filter?: table|(fun(ev: rex.event.terminal_pwd_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_pwd_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.title_changed", filter?: table|(fun(ev: rex.event.terminal_title_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_title_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.bell", filter?: table|(fun(ev: rex.event.terminal_bell, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_bell|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.process_changed", filter?: table|(fun(ev: rex.event.terminal_process_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_process_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.desktop_notification", filter?: table|(fun(ev: rex.event.terminal_desktop_notification, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_desktop_notification|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.progress_report", filter?: table|(fun(ev: rex.event.terminal_progress_report, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_progress_report|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.clipboard_written", filter?: table|(fun(ev: rex.event.terminal_clipboard_written, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_clipboard_written|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.program_status_changed", filter?: table|(fun(ev: rex.event.terminal_program_status_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_program_status_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "terminal.program_status_removed", filter?: table|(fun(ev: rex.event.terminal_program_status_removed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.terminal_program_status_removed|nil, rex.Ctx|string|nil
---@overload fun(event: "session_created", filter?: table|(fun(ev: rex.event.session_created, ctx: rex.Ctx): boolean), timeout?: number): rex.event.session_created|nil, rex.Ctx|string|nil
---@overload fun(event: "session_destroyed", filter?: table|(fun(ev: rex.event.session_destroyed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.session_destroyed|nil, rex.Ctx|string|nil
---@overload fun(event: "client_joined", filter?: table|(fun(ev: rex.event.client_joined, ctx: rex.Ctx): boolean), timeout?: number): rex.event.client_joined|nil, rex.Ctx|string|nil
---@overload fun(event: "client_left", filter?: table|(fun(ev: rex.event.client_left, ctx: rex.Ctx): boolean), timeout?: number): rex.event.client_left|nil, rex.Ctx|string|nil
---@overload fun(event: "client_changed", filter?: table|(fun(ev: rex.event.client_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.client_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "keymap_changed", filter?: table|(fun(ev: rex.event.keymap_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.keymap_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "hosts_changed", filter?: table|(fun(ev: rex.event.hosts_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.hosts_changed|nil, rex.Ctx|string|nil
---@overload fun(event: "tailscale_status_changed", filter?: table|(fun(ev: rex.event.tailscale_status_changed, ctx: rex.Ctx): boolean), timeout?: number): rex.event.tailscale_status_changed|nil, rex.Ctx|string|nil
function rex.wait(event, filter, timeout) end

---Block for a number of seconds, which may be fractional.
---
---*Script only.*
---@param seconds number
function rex.sleep(seconds) end

---End the script immediately. `rex do` exits with `code`, or 0.
---
---*Script only.*
---@param code? integer
function rex.stop(code) end

--------------------------------------------------------------------------------
-- Timers (scripts run with `rex do` only)
--------------------------------------------------------------------------------

---@class rex.Timer
local Timer = {}

---Stop the timer.
function Timer:cancel() end

---Whether the timer is still live: `true` until it is cancelled or has fired
---for the last time.
---@return boolean
function Timer:active() end

---Call `fn` once, after `seconds`. `seconds` may be zero or fractional.
---`ctx.origin` is `timer`.
---
---*Script only.*
---@param seconds number
---@param fn fun(ctx: rex.Ctx)
---@return rex.Timer
function rex.after(seconds, fn) end

---Call `fn` every `seconds` until the timer is cancelled. If the script is
---still busy when a tick comes, `fn` runs once when it is free and the missed
---ticks are dropped. An error in `fn` is reported and the timer keeps running.
---
---*Script only.*
---@param seconds number More than zero.
---@param fn fun(ctx: rex.Ctx)
---@return rex.Timer
function rex.every(seconds, fn) end

--------------------------------------------------------------------------------
-- Running commands
--------------------------------------------------------------------------------

---@class rex.ExecOpts
---@field cwd? string The working directory. Defaults to Rex's own.
---@field env? table<string, string|false> Variables to set. `false` removes one.
---@field clear_env? boolean `true` starts from an empty environment. `env` still applies.
---@field stdin? string Text written to the command's standard input.
---@field timeout? number Seconds until `SIGTERM`, then `SIGKILL` two seconds later.
---@field stdout? boolean `false` discards the stream. Captured by default.
---@field stderr? boolean `false` discards the stream. Captured by default.
---@field text? boolean `false` keeps `\r\n` in the output on Windows.

---@class rex.ExecStartOpts : rex.ExecOpts
---@field stdin? string|boolean `true` keeps standard input open for `h:write`.
---@field stdout? boolean|fun(chunk: string) A function is called with each piece of output as it arrives. A piece may end mid-line.
---@field stderr? boolean|fun(chunk: string)
---@field detach? boolean `true` lets the command outlive the work that started it.

---@class rex.ExecResult
---@field code integer The exit status, or `-1` if a signal ended the command.
---@field signal string|nil The name of that signal, such as `SIGTERM`.
---@field stdout string What the command printed. `""` when it printed nothing.
---@field stderr string
---@field timed_out boolean `true` if `timeout` stopped the command.
---@field ok boolean `true` if `code` is 0 and the command didn't time out.

---A running command started with `rex.exec.start`.
---@class rex.ExecHandle
---@field pid integer The command's process ID.
local ExecHandle = {}

---Wait for the command to exit. Returns `nil` and `"timeout"` if `seconds`
---pass first.
---@param seconds? number
---@return rex.ExecResult|nil
---@return string|nil err
function ExecHandle:wait(seconds) end

---Write to standard input. Needs `stdin = true`.
---@param data string
---@return true|nil ok
---@return string|nil err
function ExecHandle:write(data) end

---Close standard input.
function ExecHandle:close_stdin() end

---Send a signal, `SIGTERM` by default.
---@param signal? string|integer A name such as `SIGINT`, or a number.
function ExecHandle:kill(signal) end

---Whether the command is still running.
---@return boolean
function ExecHandle:running() end

---Run a command, wait for it to exit and return its result. Callable table:
---`rex.exec(argv, opts)`.
---
---`argv` is a list of strings — the program, then each argument. No shell
---reads it, so arguments need no quoting. A non-zero exit is still a result,
---not an error: check `ok`.
---
---```lua
---local r, err = rex.exec({ "git", "status", "--short" }, { cwd = dir })
---if r and r.ok then rex.log(r.stdout) end
---```
---@class rex.ExecAPI
---@overload fun(argv: string[], opts?: rex.ExecOpts): rex.ExecResult|nil, string|nil
local exec = {}

---Start a command and return a handle without waiting. A command lasts as long
---as the work that started it, unless it was started with `detach = true`.
---@param argv string[]
---@param opts? rex.ExecStartOpts
---@return rex.ExecHandle|nil
---@return string|nil err
function exec.start(argv, opts) end

rex.exec = exec

--------------------------------------------------------------------------------
-- JSON and logging
--------------------------------------------------------------------------------

---@class rex.JsonAPI
local json = {}

---Turn a Lua value into JSON text. A table whose keys are 1..n becomes an
---array; any other table, including an empty one, becomes an object.
---@param value any
---@param opts? { indent?: boolean } `indent = true` indents by two spaces.
---@return string|nil text
---@return string|nil err
function json.encode(value, opts) end

---Turn JSON text into a Lua value. `null` becomes `nil`, and a `null` in an
---array is dropped.
---@param text string
---@return any value
---@return string|nil err
function json.decode(text) end

rex.json = json

---Write a log message. In a script it is printed to the terminal.
---@param level rex.LogLevel
---@param message string
---@overload fun(message: string) Logs at `info`.
function rex.log(level, message) end

---@alias rex.LogLevel
---| "debug"
---| "info"
---| "warn"
---| "error"

--------------------------------------------------------------------------------
-- Layout builders
--------------------------------------------------------------------------------

---Options for a terminal block in a layout.
---@class rex.TerminalOptions
---@field command? string[] The program to run and its arguments. Without it, an interactive shell starts.
---@field shell? string The shell to use. `none` starts `command` directly.
---@field cwd? string The working directory.
---@field initial_input? string Text typed into the terminal once it starts.
---@field exit? { on_completion?: boolean } `{ on_completion = false }` keeps the terminal open after its program exits.

---A node in a layout passed to `new_window`, `new_split` or `new_layer`: one
---block, or a split holding two more nodes. Build one with `rex.layout.block`,
---`rex.layout.horizontal` or `rex.layout.vertical`.
---@class rex.LayoutNode
---@field block? { flavor: rex.Flavor, options?: rex.TerminalOptions|table, label?: string }
---@field split? { direction: "horizontal"|"vertical", before: rex.LayoutNode, after: rex.LayoutNode, ratio?: number }

---Builders for the `layout` table taken by `new_window`, `new_split` and
---`new_layer`. They only build tables and call nothing.
---@class rex.LayoutAPI
local layout = {}

---One block.
---@param spec { flavor: rex.Flavor, options?: rex.TerminalOptions|table, label?: string }
---@return rex.LayoutNode
function layout.block(spec) end

---Two layouts side by side. `ratio` is the share given to `a`, from 0 to 1.
---@param ratio number
---@param a rex.LayoutNode
---@param b rex.LayoutNode
---@return rex.LayoutNode
function layout.horizontal(ratio, a, b) end

---Two layouts, one above the other.
---@param ratio number
---@param a rex.LayoutNode
---@param b rex.LayoutNode
---@return rex.LayoutNode
function layout.vertical(ratio, a, b) end

rex.layout = layout

--------------------------------------------------------------------------------
-- Events reference
--------------------------------------------------------------------------------

---An event name for `rex.on` and `rex.wait`. Rex never checks a name against a
---list, so a handler can be registered for an event only a newer server sends.
---See https://www.superlogical.com/rex/docs/reference/events.md
---@alias rex.Event string
---| "window_created" # A window is created. `window_id`, `label`
---| "window_closed" # A window is closed. `window_id`
---| "window_label_changed" # A window is renamed. `window_id`, `label`
---| "active_window_changed" # A different window becomes the active one. `window_id`
---| "block_created" # A block is created. `block_id`
---| "block_closed" # A block is closed. `block_id`
---| "session_label_changed" # The session is renamed. `label`
---| "session_view_changed" # The session's layout changed in any way. `revision`
---| "client_connected" # A client attaches to the session. `client_id`, `principal`, `connected_at`
---| "client_disconnected" # A client detaches from the session. `client_id`, `principal`
---| "client_connection_changed" # An attached client's connection is lost or restored. `client_id`, `principal`, `connection_state`
---| "creator_changed" # The kinds of block the session can create have changed.
---| "terminal.child_exited" # The terminal's program exits. `exit_code`, and `error` when it is not zero
---| "terminal.pwd_changed" # The program reports a new working directory. `pwd` (a URL), `owner`
---| "terminal.title_changed" # The terminal's title changes. `title`, `owner`
---| "terminal.bell" # The terminal receives a bell character.
---| "terminal.process_changed" # The foreground process changes. `generation`, `foreground`, `ancestors`
---| "terminal.desktop_notification" # The program asks for a desktop notification. `title`, `body`
---| "terminal.progress_report" # The program reports progress. `state`, `progress`
---| "terminal.clipboard_written" # The program writes to the clipboard. `text`
---| "terminal.program_status_changed" # A program reports or updates its status. `id`, `record`, `reason`
---| "terminal.program_status_removed" # Program status records are removed. `ids`, `reason`
---| "session_created" # Server event (`--all`). A session is created. `session`
---| "session_destroyed" # Server event (`--all`). A session is destroyed. `session_id`
---| "client_joined" # Server event (`--all`). A client connects to the server. `client`
---| "client_left" # Server event (`--all`). A client disconnects. `client_id`
---| "client_changed" # Server event (`--all`). A connected client's details change. `client`
---| "keymap_changed" # Server event (`--all`). The configuration file is reloaded. `generation`, `hash`
---| "hosts_changed" # Server event (`--all`). The list of hosts changes. `hash`
---| "tailscale_status_changed" # Server event (`--all`). The server's Tailscale status changes.

--------------------------------------------------------------------------------
-- Event payloads
--------------------------------------------------------------------------------

---The process that made a change, in a terminal event.
---@class rex.event.Owner
---@field pid integer The process ID.
---@field name string The process's name.

---A session, as `session_created` reports it.
---@class rex.event.SessionRef
---@field session_id string
---@field label? string

---A client, as `client_joined` and `client_changed` report it.
---@class rex.event.Client
---@field client_id string Stays the same when the client reconnects.
---@field info? rex.event.ClientInfo What the client says about itself.
---@field principal? table How the server identified the client.
---@field connected_at? string When it connected, as an RFC 3339 timestamp.

---@class rex.event.ClientInfo
---@field kind? string `app`, `cli`, `agent` or `other`.
---@field name? string The program's name, such as `Rex.app`.
---@field platform? string `macos`, `ios`, `linux`, `windows`, `freebsd`, `web` or `other`.
---@field version? string
---@field label? string

---Fields of the `window_created` event.
---@class rex.event.window_created
---@field window_id string
---@field label? string The window's label, if it has one.

---Fields of the `window_closed` event.
---@class rex.event.window_closed
---@field window_id string

---Fields of the `window_label_changed` event.
---@class rex.event.window_label_changed
---@field window_id string
---@field label? string The new label. Absent when the label was removed.

---Fields of the `active_window_changed` event.
---@class rex.event.active_window_changed
---@field window_id string

---Fields of the `block_created` event.
---@class rex.event.block_created
---@field block_id string

---Fields of the `block_closed` event.
---@class rex.event.block_closed
---@field block_id string

---Fields of the `session_label_changed` event.
---@class rex.event.session_label_changed
---@field label? string The new label.

---Fields of the `session_view_changed` event.
---@class rex.event.session_view_changed
---@field revision integer The session's revision after the change. Call `rex.session.view` for the new layout.

---Fields of the `client_connected` event.
---@class rex.event.client_connected
---@field client_id string
---@field principal table How the server identified the client.
---@field connected_at string When it connected, as an RFC 3339 timestamp.

---Fields of the `client_disconnected` event.
---@class rex.event.client_disconnected
---@field client_id string
---@field principal table

---Fields of the `client_connection_changed` event.
---@class rex.event.client_connection_changed
---@field client_id string
---@field principal table
---@field connection_state string `lost` or `restored`.

---Fields of the `creator_changed` event.
---@class rex.event.creator_changed
---(no fields)

---Fields of the `terminal.child_exited` event.
---@class rex.event.terminal_child_exited
---@field exit_code integer The program's exit code, or -1 if a signal ended it.
---@field error? string Why it failed, such as `exit status 2`. Absent on success.

---Fields of the `terminal.pwd_changed` event.
---@class rex.event.terminal_pwd_changed
---@field pwd string A URL such as `file://hostname/Users/you/src`, not a plain path.
---@field owner rex.event.Owner The process that reported it.

---Fields of the `terminal.title_changed` event.
---@class rex.event.terminal_title_changed
---@field title string
---@field owner rex.event.Owner

---Fields of the `terminal.bell` event.
---@class rex.event.terminal_bell
---(no fields)

---Fields of the `terminal.process_changed` event.
---@class rex.event.terminal_process_changed
---@field generation integer Increases with every change.
---@field foreground? rex.ProcessInfo The process in the foreground. Absent if it can't be found or read.
---@field ancestors? rex.ProcessInfo[] The processes between the foreground process and the terminal's own child, nearest first.

---Fields of the `terminal.desktop_notification` event.
---@class rex.event.terminal_desktop_notification
---@field title string
---@field body string

---Fields of the `terminal.progress_report` event.
---@class rex.event.terminal_progress_report
---@field state string Such as `set`, `remove`, `error` or `indeterminate`.
---@field progress? integer Percent complete, when the program reported one.

---Fields of the `terminal.clipboard_written` event.
---@class rex.event.terminal_clipboard_written
---@field text string

---Fields of the `terminal.program_status_changed` event.
---@class rex.event.terminal_program_status_changed
---@field id string The record's ID.
---@field record table The status record. See the OSC 7501 reference.
---@field reason string Why it changed.

---Fields of the `terminal.program_status_removed` event.
---@class rex.event.terminal_program_status_removed
---@field ids string[] The records that were removed.
---@field reason string

---Fields of the `session_created` event.
---@class rex.event.session_created
---@field session rex.event.SessionRef The new session.

---Fields of the `session_destroyed` event.
---@class rex.event.session_destroyed
---@field session_id string

---Fields of the `client_joined` event.
---@class rex.event.client_joined
---@field client rex.event.Client

---Fields of the `client_left` event.
---@class rex.event.client_left
---@field client_id string

---Fields of the `client_changed` event.
---@class rex.event.client_changed
---@field client rex.event.Client

---Fields of the `keymap_changed` event.
---@class rex.event.keymap_changed
---@field generation integer Increases with every reload.
---@field hash string The configuration's hash, for spotting a real change.

---Fields of the `hosts_changed` event.
---@class rex.event.hosts_changed
---@field hash string

---Fields of the `tailscale_status_changed` event.
---@class rex.event.tailscale_status_changed
---(no fields)
