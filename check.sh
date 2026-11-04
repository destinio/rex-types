#!/usr/bin/env bash
#
# Checks the definitions against lua-language-server, both ways people install
# them: types/ linked into the workspace, and types/ named in workspace.library.
#
#   ./check.sh            both modes
#   ./check.sh --generate regenerate rex.api.lua first (needs a running Rex)
#
# Zero problems expected. test/fixture.lua and test/script.lua are ordinary,
# correct uses of the API; anything reported there is a bug in the definitions.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
green=$'\033[32m'; red=$'\033[31m'; dim=$'\033[2m'; bold=$'\033[1m'; reset=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
fail() { printf '  %s✗%s %s\n' "$red" "$reset" "$*"; }

lls=""
for candidate in \
  "${LUA_LS:-}" \
  "$(command -v lua-language-server 2>/dev/null || true)" \
  "$HOME/.local/share/nvim/mason/bin/lua-language-server"; do
  [[ -n "$candidate" && -x "$candidate" ]] && { lls="$candidate"; break; }
done
if [[ -z "$lls" ]]; then
  fail "lua-language-server not found. Set LUA_LS=/path/to/lua-language-server, or install it:"
  printf '      nvim: :MasonInstall lua-language-server · macOS: brew install lua-language-server\n'
  printf '      Linux: your package manager, or https://github.com/LuaLS/lua-language-server/releases\n'
  exit 1
fi
ok "lua-language-server: $lls"

if [[ "${1:-}" == "--generate" ]]; then
  command -v rex >/dev/null 2>&1 || { fail "rex isn't on your PATH"; exit 1; }
  rex do "$root/types/generate.lua" >/dev/null || { fail "generator failed"; exit 1; }
  ok "regenerated types/rex.api.lua"
fi

status=0
run_check() { # name, workspace dir
  local name="$1" ws="$2" out
  # no --logpath: some packages wrap the binary and pass their own
  if out="$("$lls" --check "$ws" --checklevel=Information 2>&1 | tr '\r' '\n')"; then :; fi
  if printf '%s' "$out" | grep -q "no problems found"; then
    ok "$name: no problems"
  else
    fail "$name:"
    printf '%s\n' "$out" | grep -E "\.lua:[0-9]+" | sed 's/^/      /' | head -40
    status=1
  fi
}

# Mode 1: types/ inside the workspace, the way the installer links it.
ws1="$(mktemp -d)"
cp "$root"/test/fixture.lua "$root"/test/script.lua "$ws1/"
ln -s "$root/types" "$ws1/types"
cp "$root/examples/luarc.json" "$ws1/.luarc.json"
run_check "linked into the workspace" "$ws1"

# Mode 2: types/ named in workspace.library, for configs kept elsewhere.
ws2="$(mktemp -d)"
cp "$root"/test/fixture.lua "$root"/test/script.lua "$ws2/"
cat >"$ws2/.luarc.json" <<JSON
{
  "runtime": { "version": "Lua 5.1" },
  "workspace": { "library": ["$root/types"], "checkThirdParty": false },
  "diagnostics": { "disable": ["duplicate-set-field"] }
}
JSON
run_check "named in workspace.library" "$ws2"

# Mode 3: every mistake marked EXPECT in test/negative.lua must be reported.
ws3="$(mktemp -d)"
cp "$root/test/negative.lua" "$ws3/"
ln -s "$root/types" "$ws3/types"
cp "$root/examples/luarc.json" "$ws3/.luarc.json"
neg_out="$("$lls" --check "$ws3" --checklevel=Information 2>&1 | tr '\r' '\n' | sed 's/\x1b\[[0-9;]*m//g' || true)"
expected="$(grep -nE '^[^-].*-- EXPECT' "$root/test/negative.lua" | cut -d: -f1)"
caught="$(printf '%s' "$neg_out" | grep -oE "negative\.lua:[0-9]+" | cut -d: -f2 | sort -u || true)"
missed=""
for line in $expected; do
  printf '%s\n' "$caught" | grep -qx "$line" || missed="$missed $line"
done
if [[ -z "$missed" ]]; then
  ok "all $(printf '%s\n' "$expected" | wc -l | tr -d ' ') mistakes in test/negative.lua are still caught"
else
  fail "mistakes no longer caught, at test/negative.lua lines:$missed"
  status=1
fi
rm -rf "$ws3"

# The generated half must still line up with the hand-written half.
if command -v rex >/dev/null 2>&1; then
  missing="$(rex do "$root/types/generate.lua" 2>/dev/null || true)"
  if printf '%s' "$missing" | grep -q '"action_overloads_missing_from_rex_lua":{}'; then
    ok "every action that takes arguments has an overload in rex.lua"
  elif [[ -n "$missing" ]]; then
    fail "actions missing an overload in rex.lua:"
    printf '      %s\n' "$missing"
    status=1
  fi
else
  printf '  %s—%s rex not on PATH, skipped the generator cross-check\n' "$dim" "$reset"
fi

# The Neovim half must load and find its own types/.
if command -v nvim >/dev/null 2>&1; then
  if nvim --headless --clean --cmd "set rtp+=$root" \
      -c "lua local p = require('rex-types').path(); assert(vim.uv.fs_stat(p .. '/rex.lua'), p)" \
      -c "qa!" >/dev/null 2>&1; then
    ok "lua/rex-types loads and resolves types/"
  else
    fail "lua/rex-types didn't load, or couldn't find types/rex.lua"
    status=1
  fi
else
  printf '  %s—%s nvim not on PATH, skipped the plugin check\n' "$dim" "$reset"
fi

rm -rf "$ws1" "$ws2"
printf '\n'
if ((status == 0)); then printf '  %sAll checks passed.%s\n\n' "$bold" "$reset"; else printf '  %sFailed.%s\n\n' "$red" "$reset"; fi
exit $status
