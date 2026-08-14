-- =============================================================================
--  AI STAR CUBE · macOS · agent registry (equal-footing)
--  Single source of truth: ~/.config/wezterm/workbench/agents.tsv (same file
--  the zsh Init panel reads). Rows with unresolvable exe are hidden.
--  Config-load safe: only io.open / os.getenv — never run_child_process.
-- =============================================================================

local wezterm = require("wezterm")

local M = {}

local home = wezterm.home_dir
local agents_file = home .. "/.config/wezterm/workbench/agents.tsv"

local BUILTIN = {
  codex = { label = "OpenAI Codex CLI", mode = "flag", flag = "-C", clear = false },
  grok = { label = "Grok Build CLI", mode = "flag", flag = "--cwd", clear = false },
  kimi = { label = "Kimi Code CLI", mode = "cwd", flag = "", clear = false },
  deepseek = { label = "DeepSeek CLI", mode = "cwd", flag = "", clear = true },
}

local ABS_CANDIDATES = {
  home .. "/.local/bin",
  home .. "/.kimi-code/bin",
  home .. "/.codex/bin",
  home .. "/.grok/bin",
  home .. "/.deepseek-cli/bin",
  home .. "/.npm-global/bin",
  "/opt/homebrew/bin",
  "/usr/local/bin",
}

local function file_exists(p)
  if not p or p == "" then
    return false
  end
  local f = io.open(p, "r")
  if f then
    f:close()
    return true
  end
  return false
end

--- Read agents.tsv rows: { {id,label,exe,mode,flag,clear}, ... }
function M.read_registry()
  local rows = {}
  local f = io.open(agents_file, "r")
  if f then
    for line in f:lines() do
      line = line:gsub("^\239\187\191", "")
      line = line:match("^%s*(.-)%s*$") or ""
      if line ~= "" and not line:match("^#") then
        local id, label, exe, mode, flag, clear = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if id and id ~= "" and exe and exe ~= "" then
          rows[#rows + 1] = {
            id = id,
            label = label ~= "" and label or id,
            exe = exe,
            mode = (mode == "flag") and "flag" or "cwd",
            flag = flag or "",
            clear = clear == "1",
          }
        end
      end
    end
    f:close()
  end
  -- Built-in fallback when the registry file is absent
  if #rows == 0 then
    for id, def in pairs(BUILTIN) do
      rows[#rows + 1] = {
        id = id,
        label = def.label,
        exe = id,
        mode = def.mode,
        flag = def.flag,
        clear = def.clear,
      }
    end
  end
  return rows
end

--- Resolve an exe spec (name or absolute path) to a runnable path or nil
function M.resolve_exe(spec)
  if not spec or spec == "" then
    return nil
  end
  if spec:sub(1, 1) == "/" then
    if file_exists(spec) then
      return spec
    end
    return nil
  end
  local path_env = os.getenv("PATH") or ""
  for dir in path_env:gmatch("[^:]+") do
    dir = tostring(dir):gsub("^%s+", ""):gsub("%s+$", "")
    if dir ~= "" then
      local p = dir .. "/" .. spec
      if file_exists(p) then
        return p
      end
    end
  end
  for _, dir in ipairs(ABS_CANDIDATES) do
    local p = dir .. "/" .. spec
    if file_exists(p) then
      return p
    end
  end
  return nil
end

--- Resolved registry (exe hidden rows dropped), file read fresh each call
function M.installed()
  local rows = M.read_registry()
  local out = {}
  for _, r in ipairs(rows) do
    local p = M.resolve_exe(r.exe)
    if p then
      local e = {}
      for k, v in pairs(r) do
        e[k] = v
      end
      e.exe_path = p
      e.display = e.label
      out[#out + 1] = e
    end
  end
  return out
end

function M.registry_order()
  local order = {}
  for _, r in ipairs(M.installed()) do
    order[#order + 1] = r.id
  end
  return order
end

function M.is_installed(id)
  for _, e in ipairs(M.installed()) do
    if e.id == id then
      return true
    end
  end
  return false
end

function M.entry(id)
  for _, e in ipairs(M.installed()) do
    if e.id == id then
      return e
    end
  end
  return nil
end

--- Default agent for a project root (D-005): bound column-3 first, then first installed
function M.default_for(path)
  local desk = require("desk")
  local bound = desk.agent_for_path(path)
  if bound and M.is_installed(bound) then
    return bound
  end
  local installed = M.installed()
  if #installed > 0 then
    return installed[1].id
  end
  return nil
end

--- New-session args for an agent bound to <root>
function M.new_args(id, root)
  local entry = M.entry(id)
  if not entry then
    return nil
  end
  if entry.mode == "flag" and entry.flag ~= "" then
    return { entry.exe_path, entry.flag, root }
  end
  return { entry.exe_path }
end

--- Resume args (most recent session via official interface)
function M.resume_args(id, root)
  local entry = M.entry(id)
  if not entry then
    return nil
  end
  if entry.mode == "flag" and entry.flag ~= "" then
    return { entry.exe_path, entry.flag, root, "--continue" }
  end
  return { entry.exe_path, "--continue" }
end

local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local splash_file = home .. "/.config/wezterm/splash.txt"

--- Splash-prefixed spawn args: cat splash (300ms) then exec the agent.
--- Line-based REPLs (clear=1) clear after splash so cat art never lingers.
function M.splash_args(id, root)
  local entry = M.entry(id)
  if not entry then
    return nil
  end
  local cmd = "cat " .. sh_quote(splash_file) .. " 2>/dev/null; sleep 0.3"
  if entry.clear then
    cmd = cmd .. "; clear"
  end
  if entry.mode == "flag" and entry.flag ~= "" then
    cmd = cmd .. "; exec " .. sh_quote(entry.exe_path) .. " " .. entry.flag .. " " .. sh_quote(root)
  else
    cmd = cmd .. "; exec " .. sh_quote(entry.exe_path)
  end
  return { "/bin/zsh", "-l", "-c", cmd }
end

function M.spawn_cwd(id, root)
  return root
end

return M
