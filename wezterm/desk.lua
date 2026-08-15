-- =============================================================================
--  AI STAR CUBE · macOS · task identity (POSIX edition)
--  Contract distilled from upstream desk.lua (bf1f6ef):
--    R2  weak/system paths never project roots
--    R3  project name = desk-roots left column only
--    R4  project path frozen at create/bind
--    R5  set_root / bind refuse weak + reserved
--    R6  UI project column uses name-for-path reverse lookup
--    D-005 desk-roots rows carry an explicit third column (agent)
-- =============================================================================

local wezterm = require("wezterm")

local M = {}

local home = wezterm.home_dir
local roots_file = home .. "/.config/wezterm/workbench/desk-roots.tsv"

function M.normalize(path)
  if not path or path == "" then
    return nil
  end
  path = tostring(path)
  path = path:gsub("^file://", "")   -- keeps the leading "/" of the path part
  path = path:gsub("%%20", " ")
  path = path:gsub("\\", "/")
  path = path:gsub("/+$", "")
  if path == "" then
    return nil
  end
  return path
end

function M.basename(path)
  path = M.normalize(path)
  if not path then
    return "?"
  end
  return path:match("([^/]+)$") or path
end

function M.short_path(path, max_len)
  path = M.normalize(path)
  if not path then
    return "--"
  end
  max_len = max_len or 42
  if home and #path > #home and path:sub(1, #home) == home then
    path = "~" .. path:sub(#home + 1)
  end
  if #path <= max_len then
    return path
  end
  return "..." .. path:sub(-(max_len - 3))
end

local RESERVED_NAMES = {
  home = true, desktop = true, documents = true, downloads = true,
  library = true, applications = true, config = true, tmp = true,
  usr = true, etc = true, bin = true, var = true, sbin = true,
}

function M.is_reserved_name(name)
  if not name or name == "" then
    return true
  end
  return RESERVED_NAMES[tostring(name):lower()] == true
end

-- macOS weak paths (R2)
function M.is_weak_path(path)
  path = M.normalize(path)
  if not path or path == "" then
    return true
  end
  local pl = path:lower()
  local hl = (home or ""):lower()
  if pl == "/" or pl == "/tmp" or pl == "/var" or pl == "/etc" or pl == "/usr" or pl == "/bin" or pl == "/system" or pl == "/library" or pl == "/applications" then
    return true
  end
  if pl:sub(1, #"/system/") == "/system/" or pl:sub(1, #"/private/") == "/private/" then
    return true
  end
  if hl ~= "" then
    if pl == hl then
      return true
    end
    local weak_exact = {
      hl .. "/desktop",
      hl .. "/documents",
      hl .. "/downloads",
      hl .. "/pictures",
      hl .. "/movies",
      hl .. "/music",
      hl .. "/library",
      hl .. "/applications",
      hl .. "/.config",
      hl .. "/.local",
    }
    for _, w in ipairs(weak_exact) do
      if pl == w then
        return true
      end
    end
    if pl:sub(1, #hl + 9) == hl .. "/library/" then
      return true
    end
  end
  return false
end

function M.is_strong_path(path)
  path = M.normalize(path)
  if not path then
    return false
  end
  return not M.is_weak_path(path)
end

-- P1: read cache with a short time window — the status tick (1s) no longer
-- re-reads the TSV on every repaint. Any write invalidates immediately.
local map_cache = nil
local map_cache_at = 0
local MAP_TTL = 2.0

local function invalidate_map()
  map_cache = nil
  map_cache_at = 0
end

local function read_map()
  local now = os.clock()
  if map_cache and (now - map_cache_at) < MAP_TTL and (now - map_cache_at) >= 0 then
    return map_cache
  end
  local map = {}
  local f = io.open(roots_file, "r")
  if not f then
    map_cache = map
    map_cache_at = now
    return map
  end
  for raw in f:lines() do
    local line = raw:gsub("^\239\187\191", "")
    line = line:match("^%s*(.-)%s*$") or ""
    if line ~= "" and not line:match("^#") then
      local name, path, agent = line:match("^([^\t]+)\t([^\t]+)\t*([^\t]*)$")
      if name and path then
        path = M.normalize(path)
        if path and M.is_strong_path(path) and not M.is_reserved_name(name) and name:sub(1, 1) ~= "." then
          map[name] = { path = path, agent = agent ~= "" and agent or nil }
        end
      end
    end
  end
  f:close()
  map_cache = map
  map_cache_at = now
  return map
end

-- H1: atomic write — temp file + rename, never truncate in place (upstream
-- L-3 discipline; zsh side already does mktemp+mv, Lua side now matches).
local function write_map(map)
  local tmp = roots_file .. ".tmp." .. tostring(os.time()) .. tostring(math.random(10000, 99999))
  local f = io.open(tmp, "w")
  if not f then
    return false
  end
  f:write("# AI STAR CUBE desk roots — name<TAB>path<TAB>agent\n")
  local keys = {}
  for k in pairs(map) do
    table.insert(keys, k)
  end
  table.sort(keys)
  for _, name in ipairs(keys) do
    local entry = map[name]
    local p = M.normalize(entry.path)
    local agent = entry.agent or ""
    if p and M.is_strong_path(p) and not M.is_reserved_name(name) then
      f:write(name .. "\t" .. p .. "\t" .. agent .. "\n")
    end
  end
  f:close()
  local ok = os.rename(tmp, roots_file)
  if not ok then
    pcall(os.remove, tmp)
    return false
  end
  invalidate_map()
  return true
end

--- External invalidation hook (config reload, panel writes observed late)
function M.invalidate_cache()
  invalidate_map()
end

function M.ensure_roots_dir()
  pcall(function()
    local dir = home .. "/.config/wezterm/workbench"
    os.execute('mkdir -p "' .. dir:gsub('"', '\\"') .. '"')
  end)
end

function M.name_for_path(path)
  path = M.normalize(path)
  if not path then
    return nil
  end
  local map = read_map()
  for name, entry in pairs(map) do
    if M.normalize(entry.path) == path then
      return name
    end
  end
  local best_name, best_len = nil, -1
  for name, entry in pairs(map) do
    local np = M.normalize(entry.path)
    if np and (path == np or path:sub(1, #np + 1) == np .. "/") then
      if #np > best_len then
        best_len = #np
        best_name = name
      end
    end
  end
  if best_name then
    return best_name
  end
  if M.is_strong_path(path) then
    local leaf = M.basename(path)
    if leaf and not M.is_reserved_name(leaf) then
      return leaf
    end
  end
  return nil
end

function M.project_label(path)
  local n = M.name_for_path(path)
  if n then
    return n
  end
  if M.is_weak_path(path) then
    return "(system)"
  end
  return M.basename(path) or "?"
end

function M.get_root(name)
  if not name or name == "" or M.is_reserved_name(name) then
    return nil
  end
  local g = wezterm.GLOBAL.macos_desk
  if g and g[name] and M.is_strong_path(g[name]) then
    return M.normalize(g[name])
  end
  local map = read_map()
  if map[name] then
    return map[name].path
  end
  return nil
end

function M.agent_for_path(path)
  path = M.normalize(path)
  if not path then
    return nil
  end
  local map = read_map()
  for _, entry in pairs(map) do
    if M.normalize(entry.path) == path and entry.agent and entry.agent ~= "" then
      return entry.agent
    end
  end
  return nil
end

--- All bound tasks as {name, path, agent} list (sorted by name)
function M.roots_list()
  local map = read_map()
  local out = {}
  for name, entry in pairs(map) do
    table.insert(out, { name = name, path = entry.path, agent = entry.agent })
  end
  table.sort(out, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return out
end

function M.set_root(name, path, agent)
  name = name and tostring(name):match("^%s*(.-)%s*$")
  path = M.normalize(path)
  if not name or name == "" or not path then
    return false
  end
  if M.is_reserved_name(name) or name:sub(1, 1) == "." or M.is_weak_path(path) then
    return false
  end
  local map = read_map()
  local pl = path:lower()
  for k, entry in pairs(map) do
    if k ~= name and entry.path and entry.path:lower() == pl then
      map[k] = nil
      if wezterm.GLOBAL.macos_desk then   -- evict stale GLOBAL alias too
        wezterm.GLOBAL.macos_desk[k] = nil
      end
    end
  end
  map[name] = { path = path, agent = agent or map[name] and map[name].agent }
  wezterm.GLOBAL.macos_desk = wezterm.GLOBAL.macos_desk or {}
  wezterm.GLOBAL.macos_desk[name] = path
  return write_map(map)
end

-- Per-tab task root (tab-first policy)
local function extract_tab_id(tab)
  if not tab then
    return nil
  end
  local ok_field, field = pcall(function()
    return tab.tab_id
  end)
  if ok_field and field ~= nil and type(field) ~= "function" then
    if type(field) == "number" or type(field) == "string" then
      return field
    end
  end
  local ok_m, v = pcall(function()
    return tab:tab_id()
  end)
  if ok_m and v ~= nil and tostring(v) ~= "" then
    return v
  end
  return nil
end

function M.get_tab_desk_by_id(tab_id)
  if not tab_id then
    return nil
  end
  local g = wezterm.GLOBAL.macos_tab_desk
  if not g then
    return nil
  end
  return M.normalize(g[tostring(tab_id)])
end

function M.set_tab_desk_by_id(tab_id, path)
  path = M.normalize(path)
  if not tab_id or not path or M.is_weak_path(path) then
    return false
  end
  wezterm.GLOBAL.macos_tab_desk = wezterm.GLOBAL.macos_tab_desk or {}
  wezterm.GLOBAL.macos_tab_desk[tostring(tab_id)] = path
  local name = M.name_for_path(path) or M.basename(path)
  if name and not M.is_reserved_name(name) then
    M.set_root(name, path)
  end
  return true
end

function M.bind_tab(tab, path, pane)
  path = M.normalize(path)
  if not path or M.is_weak_path(path) then
    return false
  end
  local id = extract_tab_id(tab)
  return M.set_tab_desk_by_id(id, path)
end

-- Best-effort cwd of a pane (no get_current_working_dir on older WezTerm builds)
function M.cwd_from_pane(pane)
  if not pane then
    return home
  end
  local ok, info = pcall(function()
    return pane:get_foreground_process_info()
  end)
  if ok and info then
    if info.argv then
      for i = 1, #info.argv do
        local a = tostring(info.argv[i] or "")
        if a == "--cwd" or a == "-C" or a == "--cd" then
          local v = info.argv[i + 1]
          if v and M.is_strong_path(M.normalize(tostring(v))) then
            return M.normalize(tostring(v))
          end
        end
        local m = a:match("^%-%-cwd=(.+)$") or a:match("^%-C=(.+)$") or a:match("^%-%-cd=(.+)$")
        if m and M.is_strong_path(M.normalize(m)) then
          return M.normalize(m)
        end
      end
    end
    if info.cwd and M.is_strong_path(M.normalize(info.cwd)) then
      return M.normalize(info.cwd)
    end
  end
  return home
end

function M.process_name(pane)
  if not pane then
    return ""
  end
  local ok, info = pcall(function()
    return pane:get_foreground_process_info()
  end)
  if ok and info then
    if info.executable and info.executable ~= "" then
      return tostring(info.executable)
    end
    if info.name and info.name ~= "" then
      return tostring(info.name)
    end
  end
  local ok2, name = pcall(function()
    return pane:get_foreground_process_name() or ""
  end)
  if ok2 and name then
    return tostring(name)
  end
  return ""
end

-- HUD-only resolve: always the GUI-active tab
function M.resolve_active_for_hud(window, pane)
  local id = nil
  pcall(function()
    local mux = window:mux_window()
    if mux then
      for _, ti in ipairs(mux:tabs_with_info() or {}) do
        if ti and ti.is_active then
          id = extract_tab_id(ti.tab)
          if not id and ti.tab_id then
            id = ti.tab_id
          end
          break
        end
      end
    end
  end)
  local root = M.get_tab_desk_by_id(id)
  if M.is_strong_path(root) then
    return M.project_label(root), root, true, id
  end
  local cwd = M.cwd_from_pane(pane)
  if M.is_strong_path(cwd) then
    if id then
      M.set_tab_desk_by_id(id, cwd)
    end
    return M.project_label(cwd), cwd, true, id
  end
  return "unbound", nil, false, id
end

function M.ensure(window, pane)
  local _, root = M.resolve_active_for_hud(window, pane)
  return M.project_label(root), root
end

-- H3: prune GLOBAL per-tab records whose tab no longer exists (tab close
-- leaves macos_tab_desk / macos_help_tabs / macos_sidebar_tabs entries
-- behind: slow leak + stale hit risk if the mux ever reuses an id).
function M.prune_dead_tabs(window)
  local live = {}
  local ok = pcall(function()
    local mux = window:mux_window()
    if not mux then
      return
    end
    for _, ti in ipairs(mux:tabs_with_info() or {}) do
      local id = extract_tab_id(ti.tab)
      if not id and ti.tab_id then
        id = ti.tab_id
      end
      if id then
        live[tostring(id)] = true
      end
    end
  end)
  if not ok or next(live) == nil then
    return   -- never wipe on enumeration failure
  end
  for _, key in ipairs({ "macos_tab_desk", "macos_help_tabs", "macos_sidebar_tabs" }) do
    local g = wezterm.GLOBAL[key]
    if g then
      local keep = {}
      for id, v in pairs(g) do
        if live[tostring(id)] then
          keep[id] = v
        end
      end
      wezterm.GLOBAL[key] = keep
    end
  end
end

return M
