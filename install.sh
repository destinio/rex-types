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
# Options (environment variables):
#   REX_TYPES_DIR=path     clone somewhere else (default ~/.local/share/rex-types)
#   REX_TYPES_GENERATE=0   keep the committed rex.api.lua instead of regenerating
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/destinio/rex-types/main/install.sh | bash -s -- --uninstall

set -euo pipefail

REPO="https://github.com/destinio/rex-types.git"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

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

# ------------------------------------------------------------------ prerequisites

command -v rex >/dev/null 2>&1 || die "rex isn't on your PATH. Install the Rex app (https://www.superlogical.com/rex), open it once, then run this again."
ok "rex"
command -v git >/dev/null 2>&1 || die "git isn't on your PATH."
ok "git"

if command -v lua-language-server >/dev/null 2>&1; then
  ok "lua-language-server"
elif [[ -x "$HOME/.local/share/nvim/mason/bin/lua-language-server" ]]; then
  ok "lua-language-server (nvim/mason)"
else
  warn "lua-language-server not found. nvim: :MasonInstall lua-language-server. Else: brew install lua-language-server"
fi

# ------------------------------------------------------------------ get the code

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n "$here" && -f "$here/types/rex.lua" ]]; then
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
    warn "couldn't regenerate (using the committed copy): ${out}"
  fi
else
  ok "kept the committed types/rex.api.lua"
fi

say ""
say "  ${bold}Next${reset}"
say "    Open ${bold}$config${reset} and type ${bold}rex.${reset} — the menu is the whole API."
say "    ${dim}K for docs, grd to jump into types/. Already in nvim? :LspRestart${reset}"
say "    ${dim}Re-run this after a Rex upgrade to refresh the generated half.${reset}"
say ""
