-- Mistakes the definitions must catch. Every code line below carries a marker
-- naming the diagnostic it should produce, and check.sh asserts that each of
-- those lines is still reported. If one goes quiet, the types got weaker.

local TERM = "com.superlogical.terminal"

local r = rex.block.call(TERM, "process", {})
if r and r.foreground then
  print(r.foreground.nope) -- EXPECT undefined-field
end

local v = rex.session.view {}
if v then
  print(v.windowz) -- EXPECT undefined-field
end

rex.invoke("pane.split", { direction = "sideways" }) -- EXPECT param-type-mismatch

rex.log("shout", "hello") -- EXPECT param-type-mismatch

rex.exec("ls") -- EXPECT param-type-mismatch

rex.session.focus_direction { direction = "sideways" } -- EXPECT param-type-mismatch
