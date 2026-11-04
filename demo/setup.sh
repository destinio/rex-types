#!/usr/bin/env bash
# Builds the throwaway Rex config the demo tape records, laid out the way
# install.sh lays one out: types/ linked in, .luarc.json beside it.
# Prints the directory it made.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
ws="${TMPDIR:-/tmp}/rex-types-demo"
rm -rf "$ws"; mkdir -p "$ws"
# a swapfile left by an interrupted run would prompt on open and eat keystrokes
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}"/nvim/swap/*rex-types-demo*.sw? 2>/dev/null || true
ln -s "$root/types" "$ws/types"
cp "$root/examples/luarc.json" "$ws/.luarc.json"
cat >"$ws/init.lua" <<'LUA'
-- ~/.config/rex/init.lua
local P = "ctrl+a>" -- tmux-style prefix

rex.bind(P .. "c", "client.tab.new")
rex.bind(P .. "x", "pane.close")
rex.bind(P .. "m", "pane.zoom")

rex.bind("ctrl+h", function()
  rex.session.focus_direction { direction = "left" }
end)
LUA
printf '%s' "$ws"
