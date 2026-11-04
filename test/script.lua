-- Fixture for the script half of the API: events, timers, waiting, exec handles.
-- Zero problems expected, same as fixture.lua.

rex.on("terminal.child_exited", function(ctx, ev)
  if ev.exit_code ~= 0 then
    rex.log("warn", (ev.error or "failed") .. " in " .. (ctx.block_id or "?"))
  end
end)

rex.on("terminal.process_changed", function(_, ev)
  local fg = ev.foreground
  if fg then rex.log(fg.name .. " #" .. tostring(fg.pid) .. " gen " .. tostring(ev.generation)) end
  for _, p in ipairs(ev.ancestors or {}) do rex.log("  " .. p.name) end
end)

rex.on("terminal.program_status_changed", function(_, ev)
  rex.log(("status %s (%s)"):format(ev.id, ev.reason))
end)

rex.on("session_view_changed", function(_, ev)
  rex.log("revision " .. tostring(ev.revision))
end)

local ev, ctx = rex.wait("terminal.bell", nil, 5)
if ev then rex.log("bell in " .. tostring(type(ctx) == "table" and ctx.block_id or ctx)) end

local pwd_ev = rex.wait("terminal.pwd_changed", function(e) return e.pwd:match("^file://") ~= nil end)
if pwd_ev then rex.log(pwd_ev.pwd .. " by " .. pwd_ev.owner.name) end

local h = rex.exec.start({ "tail", "-f", "/tmp/log" }, {
  stdout = function(chunk) rex.log(chunk) end,
  stdin = true,
  detach = false,
})
if h then
  rex.log("pid " .. tostring(h.pid))
  h:write("hello\n")
  h:close_stdin()
  if h:running() then h:kill("SIGINT") end
  local r = h:wait(2)
  if r then rex.log("exit " .. tostring(r.code) .. " ok=" .. tostring(r.ok)) end
end

local timer = rex.every(2, function(c)
  rex.log(c.origin or "timer")
end)
rex.after(10, function()
  if timer:active() then timer:cancel() end
  rex.stop(0)
end)

rex.sleep(0.5)
rex.log("args: " .. tostring(#rex.args) .. " session: " .. rex.session_id .. " block: " .. tostring(rex.block_id))
