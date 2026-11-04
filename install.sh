#!/usr/bin/env bash
#
# rex-types: one-line install (run it again to update).
#
#   curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash
#
# Clones the repo to ~/.local/share/rex-types, links it into your Rex config as
# types/, writes a .luarc.json if you don't have one, and regenerates the API
# half against your own server.
# Read it first if you like: https://github.com/destinio/rex-types/blob/main/install.sh
#
# Check an existing install:
#   curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash -s -- --check
#
# Options (environment variables):
#   REX_TYPES_DIR=path     clone somewhere else (default ~/.local/share/rex-types)
#   REX_TYPES_GENERATE=0   keep the committed rex.api.lua instead of regenerating
#   REX_CONFIG=path        your init.lua, if it isn't ~/.config/rex/init.lua
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash -s -- --uninstall

set -euo pipefail

REPO="https://github.com/destinio/rex-types.git"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; dim=$'\033[2m'; reset=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '  %s!%s %s\n' "$yellow" "$reset" "$*"; }
die()  { printf '\n  %s✗%s %s\n\n' "$red" "$reset" "$*"; exit 1; }

if [[ -n "${REX_CONFIG:-}" ]]; then config="$REX_CONFIG"
else config="${XDG_CONFIG_HOME:-$HOME/.config}/rex/init.lua"; fi
confdir="$(dirname "$config")"
link="$confdir/types"
luarc="$confdir/.luarc.json"

LLS_HINT="lua-language-server not found. nvim: :MasonInstall lua-language-server · macOS: brew install lua-language-server · Linux/FreeBSD: your package manager, or https://github.com/LuaLS/lua-language-server/releases"

find_lls() {
  local c
  for c in "${LUA_LS:-}" "$(command -v lua-language-server 2>/dev/null || true)" \
    "$HOME/.local/share/nvim/mason/bin/lua-language-server" \
    "$HOME/.local/share/nvim/mason/packages/lua-language-server/libexec/bin/lua-language-server"; do
    [[ -n "$c" && -x "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

say ""
say "  📘 ${bold}rex-types${reset}"
say "  ${dim}Lua types for the Rex API: completion, docs on hover, jump to definition${reset}"
say ""

# ------------------------------------------------------------------ uninstall

if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -L "$link" ]]; then rm "$link"; ok "removed $link"
  elif [[ -e "$link" ]]; then warn "left $link alone (not a link this installer made)"; fi
  if [[ -f "$luarc" ]]; then warn "left $luarc alone — delete it by hand if you want lua_ls back to its defaults"; fi
  say ""
  say "  The clone is still at ${REX_TYPES_DIR:-$HOME/.local/share/rex-types}; delete it if you like."
  say ""
  exit 0
fi

# ------------------------------------------------------------------ check

if [[ "${1:-}" == "--check" || "${1:-}" == "--doctor" ]]; then
  problems=0
  if command -v rex >/dev/null 2>&1; then ok "rex ($(rex version 2>/dev/null | head -1))"
  else warn "rex isn't on your PATH"; problems=$((problems + 1)); fi

  if [[ -L "$link" || -d "$link" ]] && [[ -f "$link/rex.lua" ]]; then
    target="$(cd "$link" && pwd -P)"
    ok "types at $link → $target"
    header="$(grep -m1 'Generated from rex' "$link/rex.api.lua" 2>/dev/null || true)"
    [[ -n "$header" ]] && say "    ${dim}${header#--- }${reset}"
    have="$(grep -m1 -o 'API revision [0-9]*' "$link/rex.api.lua" 2>/dev/null | grep -o '[0-9]*' || true)"
    want="$(rex api call server.status 2>/dev/null | sed -n 's/.*"api_revision":\([0-9]*\).*/\1/p' || true)"
    if [[ -n "$have" && -n "$want" && "$have" != "$want" ]]; then
      warn "generated for API revision $have, your server speaks $want — regenerate: rex do $link/generate.lua"
      problems=$((problems + 1))
    elif [[ -n "$have" && "$have" == "$want" ]]; then
      ok "generated for this server's API revision ($have)"
    fi
  else
    warn "no types at $link — run this script without --check to install them"
    problems=$((problems + 1))
  fi

  if [[ -f "$luarc" ]]; then
    if grep -q '"Lua 5.1"' "$luarc"; then ok "$luarc sets Lua 5.1"
    else warn "$luarc doesn't set runtime.version to \"Lua 5.1\" — Rex runs Lua 5.1"; problems=$((problems + 1)); fi
    grep -q '"rex"' "$luarc" && warn "$luarc still lists \"rex\" in diagnostics.globals; the types define it now, so you can drop it"
  else
    warn "no $luarc — lua-language-server won't root itself at $confdir"
    problems=$((problems + 1))
  fi

  lls="$(find_lls || true)"
  if [[ -n "$lls" ]]; then
    ok "lua-language-server ($lls)"
    if out="$("$lls" --check "$confdir" --checklevel=Information 2>&1 | tr '\r' '\n')"; then :; fi
    if printf '%s' "$out" | grep -q "no problems found"; then
      ok "lua-language-server reports no problems in $confdir"
    else
      n="$(printf '%s' "$out" | grep -cE '\.lua:[0-9]+' || true)"
      warn "lua-language-server reports $n problem line(s) in $confdir:"
      printf '%s\n' "$out" | grep -E '\.lua:[0-9]+' | sed 's/^/      /' | head -10
    fi
  else
    warn "$LLS_HINT"
    problems=$((problems + 1))
  fi

  say ""
  if ((problems == 0)); then say "  ${bold}Looks good.${reset}"; else say "  ${yellow}$problems thing(s) to fix above.${reset}"; fi
  say ""
  exit $((problems > 0))
fi

# ------------------------------------------------------------------ prerequisites

command -v rex >/dev/null 2>&1 || die "rex isn't on your PATH. Install the Rex app (https://www.superlogical.com/rex), open it once, then run this again."
ok "rex"
command -v git >/dev/null 2>&1 || die "git isn't on your PATH."
ok "git"

lls="$(find_lls || true)"
if [[ -n "$lls" ]]; then ok "lua-language-server ($lls)"; else warn "$LLS_HINT"; fi

# ------------------------------------------------------------------ get the code

# Running from a clone (./install.sh) → use it. Piped from curl → clone or
# update our own copy. When piped, BASH_SOURCE is unset and $0 is "bash", so
# only a real file on disk counts as "running from a clone".
self="${BASH_SOURCE[0]:-}"
here=""
if [[ -n "$self" && -f "$self" ]]; then
  here="$(cd "$(dirname "$self")" 2>/dev/null && pwd || true)"
fi
if [[ -n "$here" && -f "$here/install.sh" && -f "$here/types/rex.lua" ]]; then
  src="$here"
  ok "using $src"
else
  src="${REX_TYPES_DIR:-$HOME/.local/share/rex-types}"
  if [[ -d "$src/.git" ]]; then
    # rex.api.lua is generated, so a local copy is expendable
    git -C "$src" checkout -- types/rex.api.lua 2>/dev/null || true
    git -C "$src" pull --quiet --ff-only || die "couldn't update $src (local changes?)"
    ok "updated $src"
  elif [[ -e "$src" ]]; then
    die "$src exists and isn't a clone. Remove it, or pick another folder: REX_TYPES_DIR=..."
  else
    mkdir -p "$(dirname "$src")"
    git clone --quiet "$REPO" "$src"
    ok "cloned into $src"
  fi
fi

# ------------------------------------------------------------------ link into Rex

mkdir -p "$confdir"
if [[ -L "$link" ]]; then
  rm "$link"
elif [[ -e "$link" ]]; then
  backup="$link.bak.$(date +%Y%m%d%H%M%S)"
  mv "$link" "$backup"
  warn "moved your existing $link to $backup"
fi
ln -s "$src/types" "$link"
ok "linked $link"

# ------------------------------------------------------------------ .luarc.json

if [[ -f "$luarc" ]]; then
  ok "kept your $luarc"
  grep -q '"Lua 5.1"' "$luarc" || warn "add  \"runtime\": { \"version\": \"Lua 5.1\" }  to it — Rex runs Lua 5.1"
else
  cat >"$luarc" <<'JSON'
{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime": {
    "version": "Lua 5.1",
    "pathStrict": true,
    "path": ["?.lua", "?/init.lua"]
  },
  "workspace": {
    "library": [],
    "checkThirdParty": false,
    "ignoreDir": [".git"]
  },
  "diagnostics": {
    "globals": [],
    "disable": ["duplicate-set-field"]
  },
  "completion": {
    "callSnippet": "Replace",
    "keywordSnippet": "Replace",
    "showWord": "Disable"
  },
  "hint": { "enable": true, "paramType": true, "setType": true },
  "format": { "enable": false }
}
JSON
  ok "wrote $luarc"
fi

# ------------------------------------------------------------------ regenerate

if [[ "${REX_TYPES_GENERATE:-1}" == "1" ]]; then
  if out="$(rex do "$src/types/generate.lua" 2>&1)"; then
    ok "generated types/rex.api.lua from your server"
    say "    ${dim}${out}${reset}"
  else
    warn "couldn't regenerate, keeping the committed copy: ${out}"
    say "    ${dim}$(grep -m1 'Generated from rex' "$src/types/rex.api.lua" | sed 's/^--- //')${reset}"
    say "    ${dim}Run it yourself once Rex is up:  rex do $link/generate.lua${reset}"
  fi
else
  ok "kept the committed types/rex.api.lua"
  say "    ${dim}$(grep -m1 'Generated from rex' "$src/types/rex.api.lua" | sed 's/^--- //')${reset}"
fi

say ""
say "  ${bold}Next${reset}"
say "    Open ${bold}$config${reset} and type ${bold}rex.${reset} — the menu is the whole API."
say "    ${dim}K for docs, grd to jump into types/. Already in nvim? :LspRestart${reset}"
say "    ${dim}Re-run this after a Rex upgrade, or check an install with:  install.sh --check${reset}"
say ""
