-- Generates rex.api.lua next to this file: EmmyLua definitions for everything
-- this Rex server exposes — server methods, session methods, block methods and
-- action names — so lua-language-server can complete and document them.
--
--   rex do <this directory>/generate.lua
--
-- Re-run it after a Rex upgrade. The hand-written half lives in rex.lua.
-- Action names come from the server plus every connected app client, so open
-- the apps whose actions you want before running it.

local SRC = (debug.getinfo(1, "S").source:gsub("^@", ""))
local HERE = SRC:match("^(.*)[/\\]") or "."
local OUT = HERE .. "/rex.api.lua"

local help = assert(rex.call("help.all"))

-- Buffers: aliases first, then classes and functions in discovery order.
local A, B = {}, {}
local function put(buf, s) buf[#buf + 1] = s end

local function keys(t)
  local ks = {}
  for k in pairs(t or {}) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

-- One-line, comment-safe description.
local function doc(s)
  if not s or s == "" then return nil end
  return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

--------------------------------------------------------------------------------
-- JSON Schema -> EmmyLua types
--------------------------------------------------------------------------------

local anchors = {} -- $anchor -> class name
local emitted = {} -- class name -> true
local shapes = {} -- canonical schema -> class name, so one shape is one class

---A schema as a deterministic string, so two identical shapes share a class.
local function canonical(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  if v[1] ~= nil then
    for _, item in ipairs(v) do parts[#parts + 1] = canonical(item) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for _, k in ipairs(keys(v)) do
    parts[#parts + 1] = k .. "=" .. canonical(v[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function base_type(sch)
  local t = sch.type
  if type(t) == "table" then
    for _, v in ipairs(t) do
      if v ~= "null" then return v end
    end
    return nil
  end
  return t
end

local function nullable(sch)
  if type(sch.type) == "table" then
    for _, v in ipairs(sch.type) do
      if v == "null" then return true end
    end
  end
  return false
end

-- Shapes that several methods return get a name of their own, so hover doesn't
-- show one method's result class on another method. Keyed by field names.
local SHAPE_NAMES = {
  ["revision"] = "rex.session.Revision",
  ["argv0,cwd,invoked_path,name,path,pid,script,user,user_id"] = "rex.ProcessInfo",
}

local lua_type, emit_class

---Returns the EmmyLua type for `sch`, declaring a class called `name` if it is
---an object with known properties.
function lua_type(sch, name)
  local ref = sch["$ref"]
  if ref then
    local anchor = ref:match("^#(.+)$")
    return anchors[anchor] or "table"
  end

  local t = base_type(sch)

  if t == "string" then
    if sch.enum then
      local parts = {}
      for _, v in ipairs(sch.enum) do parts[#parts + 1] = string.format("%q", v) end
      return table.concat(parts, "|")
    end
    return "string"
  elseif t == "integer" or t == "number" or t == "boolean" then
    return t
  elseif t == "array" then
    if not sch.items then return "table" end
    local item = lua_type(sch.items, name .. ".item")
    if item:find("|", 1, true) then item = "(" .. item .. ")" end
    return item .. "[]"
  elseif t == "object" then
    if sch["$anchor"] then
      name = "rex.ViewLayoutNode"
      anchors[sch["$anchor"]] = name
    end
    if sch.properties and next(sch.properties) then
      local shape = canonical(sch)
      local seen = shapes[shape]
      if seen then return seen end
      name = SHAPE_NAMES[table.concat(keys(sch.properties), ",")] or name
      shapes[shape] = name
      emit_class(name, sch)
      return name
    end
    return "table"
  end

  return "any"
end

---Declares `---@class name` with one `---@field` per property.
---`skip_required` is a set of fields to treat as optional (ids Rex fills in).
function emit_class(name, sch, skip_required)
  if emitted[name] then return end
  emitted[name] = true

  local required = {}
  for _, k in ipairs(sch.required or {}) do
    if not (skip_required and skip_required[k]) then required[k] = true end
  end

  local lines = {}
  local d = doc(sch.description)
  if d then put(lines, "---" .. d) end
  put(lines, "---@class " .. name)
  for _, k in ipairs(keys(sch.properties)) do
    local prop = sch.properties[k]
    local ty = lua_type(prop, name .. "." .. k)
    local opt = (not required[k] or nullable(prop)) and "?" or ""
    local pd = doc(prop.description)
    put(lines, ("---@field %s%s %s%s"):format(k, opt, ty, pd and (" " .. pd) or ""))
  end
  put(B, table.concat(lines, "\n") .. "\n")
end

---`required` minus the ids Rex fills in, as a set, plus whether any are left.
---`force` keeps the class under this exact name instead of reusing an
---identical shape, for names that rex.lua refers to by hand.
local function arg_class(name, sch, skip, force)
  if not (sch and sch.properties and next(sch.properties)) then return nil, false end
  local shape = canonical(sch) .. "|skip:" .. canonical(skip)
  if not force then
    local seen = shapes[shape]
    if seen then
      local needed = false
      for _, k in ipairs(sch.required or {}) do
        if not skip[k] then needed = true end
      end
      return seen, needed
    end
    shapes[shape] = name
  end
  emit_class(name, sch, skip)
  local needed = false
  for _, k in ipairs(sch.required or {}) do
    if not skip[k] then needed = true end
  end
  return name, needed
end

--------------------------------------------------------------------------------
-- Aliases: server methods, client actions, block creators and flavors
--------------------------------------------------------------------------------

local methods = {}
for _, m in ipairs(help.methods or {}) do methods[m.name] = m end

put(A, [[
---A server method for `rex.call`. `rex api list` prints them, and
---`rex api describe NAME` documents one.
---@alias rex.Method string]])
for _, name in ipairs(keys(methods)) do
  local d = doc(methods[name].description)
  put(A, ("---| %q%s"):format(name, d and (" # " .. d) or ""))
end
put(A, "")

-- Actions: the server's own and every connected app client's.
local actions, order, action_args = {}, {}, {}
local function add_actions(json_text)
  local parsed = rex.json.decode(json_text or "")
  for _, a in ipairs(parsed and parsed.actions or {}) do
    if not actions[a.name] then
      actions[a.name] = doc(a.title) or doc(a.description) or ""
      order[#order + 1] = a.name
      if a.args and a.args.properties and next(a.args.properties) then
        action_args[a.name] = a.args
      end
    end
  end
end

local r = rex.exec { "rex", "actions", "--json" }
if r and r.ok then add_actions(r.stdout) end

local sources = {}
local clients = rex.call("client.list")
for _, c in ipairs(clients and clients.clients or {}) do
  if c.info and c.info.kind == "app" then
    local ra = rex.exec { "rex", "-C", c.client_id, "actions", "--json" }
    if ra and ra.ok then
      add_actions(ra.stdout)
      sources[#sources + 1] = (c.info.platform or "?") .. " " .. (c.info.name or "app")
    end
  end
end
table.sort(sources)
table.sort(order)

put(A, [[
---An action name for `rex.bind`, `rex.invoke` and `rex.client.queue`: the
---actions this server and its connected apps offer, plus any action the
---configuration file defines with `rex.action`.
---@alias rex.Action string]])
for _, name in ipairs(order) do
  local title = actions[name]
  put(A, ("---| %q%s"):format(name, title ~= "" and (" # " .. title) or ""))
end
put(A, "")

put(A, [[
---A kind of block, for `rex.block.call`.
---@alias rex.Creator string]])
for _, bt in ipairs(help.block_types or {}) do
  put(A, ("---| %q"):format(bt.creator))
end
put(A, "")

put(A, [[
---What to create in a layout, for `rex.layout.block{ flavor = ... }`.
---@alias rex.Flavor string]])
for _, bt in ipairs(help.block_types or {}) do
  for _, f in ipairs(bt.flavors or {}) do
    put(A, ("---| %q"):format(f))
  end
end
put(A, "")

--------------------------------------------------------------------------------
-- rex.session.<method>
--------------------------------------------------------------------------------

-- Methods that act on the server rather than one session. They are reachable
-- through rex.session, but rex.call reads better.
local SERVER_SCOPED = {
  ["session.create"] = true,
  ["session.destroy"] = true,
  ["session.list"] = true,
  ["session.move"] = true,
  ["session.bootstrap"] = true,
  ["session.own_block"] = true,
  ["session.disown_block"] = true,
  ["session.attach_all"] = true,
}

put(B, [[
---Session methods. `session_id` is filled in from the current session when it
---is left out; other IDs, such as `block_id`, are not. Every call returns a
---result table, or `nil` and an error message — a failure never raises.
---
---```lua
---local view, err = rex.session.view{}
---```
---@class rex.SessionAPI
local SessionAPI = {}
]])

-- session.view owns the layout shapes, so generate it first and let the other
-- methods that return a view reuse its classes.
local session_order = { "session.view" }
for _, name in ipairs(keys(methods)) do
  if name:match("^session%.") and name ~= "session.view" then
    session_order[#session_order + 1] = name
  end
end

for _, name in ipairs(session_order) do
  local short = name:match("^session%.(.+)$")
  if short then
    local m = methods[name]
    local skip = { session_id = true }
    local args_class, needed = arg_class("rex.session." .. short .. ".args", m.input_schema, skip)
    local result = m.output_schema and lua_type(m.output_schema, "rex.session." .. short .. ".result") or "table"

    local lines = {}
    local d = doc(m.description)
    if d then put(lines, "---" .. d) end
    if SERVER_SCOPED[name] then
      put(lines, "---")
      put(lines, "---*Acts on the server, not on one session. `rex.call(\"" .. name .. "\", ...)` reads better.*")
    end
    put(lines, "---")
    put(lines, "---@see rex.Method # `rex api describe " .. name .. "` documents every argument.")
    if args_class then
      put(lines, ("---@param args%s %s"):format(needed and "" or "?", args_class))
    else
      put(lines, "---@param args? table")
    end
    put(lines, ("---@return %s|nil result"):format(result))
    put(lines, "---@return string|nil err")
    put(lines, ("function SessionAPI.%s(args) end\n"):format(short))
    put(B, table.concat(lines, "\n"))
  end
end

--------------------------------------------------------------------------------
-- rex.block.call
--------------------------------------------------------------------------------

put(B, [[
---@class rex.BlockAPI
local BlockAPI = {}
]])

local overloads = {}
for _, bt in ipairs(help.block_types or {}) do
  local prefix = "rex." .. (bt.creator:match("([^.]+)$") or bt.creator)
  for _, m in ipairs(bt.methods or {}) do
    local args_class, needed =
      arg_class(prefix .. "." .. m.name .. ".args", m.args_schema, { block_id = true })
    local result = m.output_schema and lua_type(m.output_schema, prefix .. "." .. m.name .. ".result") or "table"
    local d = doc(m.description)
    overloads[#overloads + 1] = ("---@overload fun(creator: %q, method: %q, args%s %s): %s|nil, string|nil%s"):format(
      bt.creator,
      m.name,
      needed and ":" or "?:",
      args_class or "table",
      result,
      d and (" # " .. d) or ""
    )
  end
end

put(B, [[
---Call a method on a block and return its result, or `nil` and an error
---message. `block_id` is filled in from the current block when it is left out.
---
---```lua
---local title = rex.block.call("com.superlogical.terminal", "title", {}).title
---```
---
---The result is typed per method. `args` is not, because the method name is
---the second argument — name its class on a local when you want completion:
---
---```lua
-----@type rex.terminal.list_dir.args
---local args = { path = "/tmp" }
---local dirs = rex.block.call("com.superlogical.terminal", "list_dir", args)
---```
---@param creator rex.Creator The full name of the kind of block.
---@param method string The method's name. `rex actions` lists the block methods.
---@param args? table
---@return table|nil result
---@return string|nil err]])
for _, o in ipairs(overloads) do put(B, o) end
put(B, "function BlockAPI.call(creator, method, args) end\n")

--------------------------------------------------------------------------------
-- Arguments of the actions that take them, for rex.bind, rex.invoke and
-- rex.client.queue. rex.lua lists one overload per class, by name, so these
-- names are forced rather than shared with an identical shape.
--------------------------------------------------------------------------------

local action_classes = {}
for _, name in ipairs(order) do
  local sch = action_args[name]
  if sch then
    local class = "rex.action." .. name .. ".args"
    local _, needed = arg_class(class, sch, {}, true)
    action_classes[#action_classes + 1] = { action = name, class = class, needed = needed }
  end
end

--------------------------------------------------------------------------------
-- rex.call: one overload per server method, so arguments and results are typed
--------------------------------------------------------------------------------

local call_overloads = {}
for _, name in ipairs(keys(methods)) do
  local m = methods[name]
  local args_class, needed = arg_class("rex.api." .. name .. ".args", m.input_schema, {}, true)
  local result = m.output_schema and lua_type(m.output_schema, "rex.api." .. name .. ".result") or "table"
  local d = doc(m.description)
  call_overloads[#call_overloads + 1] = ("---@overload fun(method: %q, args%s %s): %s|nil, string|nil%s"):format(
    name,
    needed and ":" or "?:",
    args_class or "table",
    result,
    d and (" # " .. d) or ""
  )
end

put(B, [[
---Call any server method by its full name, including the ones `rex.session`
---doesn't cover. Returns the result table, or `nil` and an error message — a
---failure never raises.
---
---```lua
---local clients, err = rex.call("client.list")
---```
---@param method rex.Method
---@param args? table
---@return table|nil result
---@return string|nil err]])
for _, o in ipairs(call_overloads) do put(B, o) end
put(B, "function rex.call(method, args) end\n")

--------------------------------------------------------------------------------
-- Write it out
--------------------------------------------------------------------------------

local status = rex.call("server.status") or {}
local v = rex.exec { "rex", "version" }
local version = v and v.ok and (v.stdout:match("^rex ([^\n]+)")) or "unknown"
local header = ([[
---@meta
--- GENERATED by generate.lua from this server's own API description
--- (`rex api call help.all`, `rex actions --json`). Do not edit by hand; run
---     rex do <this directory>/generate.lua
--- again after a Rex upgrade. The hand-written half of the API is in rex.lua.
---
--- Generated from rex %s, API revision %s.
--- Action names from this server%s.
]]):format(version, tostring(status.api_revision or "?"),
  #sources > 0 and (" and " .. #sources .. " app client(s): " .. table.concat(sources, ", ")) or "")

local f = assert(io.open(OUT, "w"))
f:write(header, "\n", table.concat(A, "\n"), "\n", table.concat(B, "\n"))
f:close()
rex.exec { "chmod", "644", OUT }

-- rex.lua spells out one overload per action class. Report the ones it is
-- missing, so a new or renamed action doesn't go unnoticed.
local hand = io.open(HERE .. "/rex.lua")
local hand_src = hand and hand:read("*a") or ""
if hand then hand:close() end
local unreferenced = {}
for _, a in ipairs(action_classes) do
  if not hand_src:find(a.class, 1, true) then
    unreferenced[#unreferenced + 1] = a.action .. " -> " .. a.class .. (a.needed and " (args required)" or "")
  end
end

return {
  file = OUT,
  action_overloads_missing_from_rex_lua = unreferenced,
  methods = #keys(methods),
  actions = #order,
  classes = #keys(emitted),
}
