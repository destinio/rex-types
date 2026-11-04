--- Neovim side of rex-types.
---
--- Installed with any plugin manager, this module hands the definitions in
--- `types/` to lua-language-server for the buffers that want them, so no
--- `.luarc.json` and no symlink are needed:
---
---     require("rex-types").setup()
---
--- With lazydev.nvim, prefer its own library list instead — see the README.

local M = {}

---Absolute path of the directory holding the definitions.
---@return string
function M.path()
  local src = debug.getinfo(1, 'S').source:sub(2) -- …/lua/rex-types/init.lua
  local root = vim.fn.fnamemodify(src, ':h:h:h')
  return vim.fs.normalize(root .. '/types')
end

---Does this buffer look like Rex Lua? True when it mentions `rex.`, the same
---cheap test lazydev.nvim's `words` makes.
---@param buf integer
---@return boolean
local function mentions_rex(buf)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 400, false)) do
    if line:find('rex%.') then return true end
  end
  return false
end

---Does this workspace already ship the definitions? A Rex config with `types/`
---linked into it does, and loading a second copy from the plugin would define
---every class twice.
---@param client vim.lsp.Client
---@return boolean
local function already_provided(client)
  local root = client.root_dir
  if root then
    for _, candidate in ipairs { root .. '/types/rex.api.lua', root .. '/rex.api.lua' } do
      if vim.uv.fs_stat(candidate) then return true end
    end
  end
  local settings = client.config.settings or {}
  local library = (settings.Lua and settings.Lua.workspace and settings.Lua.workspace.library) or {}
  for _, dir in ipairs(library) do
    if vim.uv.fs_stat(vim.fs.normalize(dir) .. '/rex.api.lua') then return true end
  end
  return false
end

---Add `path` to a running lua_ls client's library, keeping what's already there.
---@param client vim.lsp.Client
---@param path string
---@return boolean added
local function add_library(client, path)
  local settings = vim.deepcopy(client.config.settings or {})
  settings.Lua = settings.Lua or {}
  settings.Lua.workspace = settings.Lua.workspace or {}
  local library = settings.Lua.workspace.library or {}
  if vim.tbl_contains(library, path) then return false end
  table.insert(library, path)
  settings.Lua.workspace.library = library
  client.config.settings = settings
  client:notify('workspace/didChangeConfiguration', { settings = settings })
  return true
end

---@class rex-types.Opts
---@field path? string Where the definitions live. Defaults to this plugin's own `types/`.
---@field enabled? fun(buf: integer, client: vim.lsp.Client): boolean Which buffers get them. Defaults to "the buffer mentions `rex.`, and the workspace doesn't already ship the definitions".

---Register the definitions with every lua_ls that attaches to a Rex Lua buffer.
---@param opts? rex-types.Opts
function M.setup(opts)
  opts = opts or {}
  local path = opts.path or M.path()
  local enabled = opts.enabled or function(buf, client)
    return mentions_rex(buf) and not already_provided(client)
  end

  local function try(client, buf)
    if client and client.name == 'lua_ls' and vim.bo[buf].filetype == 'lua' and enabled(buf, client) then
      add_library(client, path)
    end
  end

  -- clients that attach from now on, and the ones already attached
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('rex-types', { clear = true }),
    callback = function(ev) try(vim.lsp.get_client_by_id(ev.data.client_id), ev.buf) end,
  })
  for _, client in ipairs(vim.lsp.get_clients { name = 'lua_ls' }) do
    for buf in pairs(client.attached_buffers or {}) do try(client, buf) end
  end
end

return M
