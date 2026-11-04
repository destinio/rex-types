-- Fixture for check.sh: ordinary, correct use of the Rex API.
-- lua-language-server must report zero problems here. If a change to the
-- definitions makes any of this look wrong, that's the bug.

local TERM = "com.superlogical.terminal"

-- key bindings, action names, key sequences
rex.bind("ctrl+a>shift+\\", "pane.split", { direction = "right" })
rex.bind("ctrl+a>m", "pane.zoom")
rex.unbind("cmd+d")
rex.mode("resize", { exclusive = true })
for _, b in ipairs(rex.bindings { mode = "resize" }) do
  rex.log("debug", b.key .. " -> " .. (b.action or "function") .. " at " .. b.source)
end

-- a function binding: ctx and ev are typed
rex.bind("ctrl+h", function(ctx, ev)
  local r = rex.block.call(TERM, "process", { block_id = ctx.block_id })
  local name = r and r.foreground and (r.foreground.argv0 or r.foreground.name) or ""
  if name:match("n?vim$") then return false end
  rex.session.focus_direction { direction = "left" }
  rex.log(ev.keybinding .. " handled")
  return true
end)

-- custom actions, commands, JSON
rex.action {
  name = "tests",
  title = "Run Tests",
  description = "Runs the project's tests in a split.",
  category = "Dev",
  args = { filter = "string?" },
  run = function(ctx, args)
    local argv = { "npm", "test" }
    if type(args.filter) == "string" then argv[#argv + 1] = args.filter end
    local r, err = rex.exec(argv, { cwd = os.getenv("HOME"), timeout = 600, stderr = false })
    if not r then return { ok = false, error = err } end
    local text = rex.json.encode({ code = r.code, timed_out = r.timed_out }, { indent = true })
    rex.client.queue("pane.focus", { direction = "down", wrap = true })
    return { ok = r.ok, report = text, out = r.stdout }
  end,
}

-- server methods: typed arguments and results
local view, err = rex.session.view {}
if view then
  for _, w in ipairs(view.windows or {}) do
    rex.log("info", (w.label or "window") .. " " .. #(w.layers or {}) .. " layers")
  end
else
  rex.log("error", err or "no view")
end

local clients = rex.call "client.list"
for _, c in ipairs(clients and clients.clients or {}) do
  if c.info and c.info.kind == "app" then
    rex.log("info", (c.info.name or "app") .. " on " .. (c.info.platform or "?"))
  end
end

-- layouts
local split = rex.session.new_split {
  direction = "vertical",
  side = "after",
  ratio = 0.3,
  layout = rex.layout.block {
    flavor = "com.superlogical.terminal.shell",
    options = { command = { "tail", "-f", "/tmp/log" }, cwd = "/tmp", exit = { on_completion = false } },
  },
}
if split then rex.log("new split") end

-- block methods
local pwd = rex.block.call(TERM, "pwd", {})
if pwd then rex.log(pwd.pwd or "no pwd") end

---@type rex.terminal.list_dir.args
local list_args = { path = "/tmp", limit = 10, files = true }
local dirs = rex.block.call(TERM, "list_dir", list_args)
if dirs then rex.log("listed " .. #(dirs.entries or {}) .. " entries") end

-- hosts and other servers
rex.host { label = "work", endpoints = { "tailscale://work-rex" }, icon = "desktopcomputer" }
for _, label in ipairs(rex.servers()) do
  local remote = rex.server(label)
  local v = remote.session.view {}
  if v then rex.log(label .. " revision " .. tostring(v.revision)) end
end
