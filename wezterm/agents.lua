-- =============================================================================
--  AI STAR CUBE · macOS · agent registry (equal-footing, detect-and-degrade)
--  D-M1-004: register once, detect at runtime, missing agents hide but never block.
--  Session data is NEVER parsed; resume goes through official CLI interfaces only.
-- =============================================================================

local wezterm = require("wezterm")

local M = {}

local home = wezterm.home_dir

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

-- Detection: full-path candidates + PATH names (pure io/env, load-safe)
local REGISTRY = {
  codex = {
    display = "Codex",
    candidates = {
      home .. "/.local/bin/codex",
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      home .. "/.codex/bin/codex",
    },
    path_names = { "codex" },
    launch_mode = "flag", -- codex -C <root>
    cwd_flag = "-C",
    resume_last = { "<exe>", "resume", "--last", "-C", "<root>" },
    resume_picker = { "<exe>", "resume", "-C", "<root>" },
    session_root = home .. "/.codex/sessions",
  },
  deepseek = {
    display = "DeepSeek",
    candidates = {
      home .. "/.npm-global/bin/deepseek",
      "/opt/homebrew/bin/deepseek",
      "/usr/local/bin/deepseek",
    },
    path_names = { "deepseek" },
    launch_mode = "cwd", -- no --cwd; spawn process cwd carries identity
    resume_last = { "<exe>", "--continue" },
    resume_picker = { "<exe>", "--resume" },
    session_root = home .. "/.deepseek-cli/sessions",
  },
  kimi = {
    display = "Kimi",
    candidates = {
      home .. "/.kimi-code/bin/kimi",
      "/opt/homebrew/bin/kimi",
      "/usr/local/bin/kimi",
    },
    path_names = { "kimi" },
    launch_mode = "cwd",
    resume_last = { "<exe>", "--continue" },
    resume_picker = { "<exe>", "--continue" },
    session_root = home .. "/.kimi-code/sessions",
  },
  grok = {
    display = "Grok",
    candidates = {
      home .. "/.grok/bin/grok",
      "/opt/homebrew/bin/grok",
      "/usr/local/bin/grok",
    },
    path_names = { "grok" },
    launch_mode = "flag",
    cwd_flag = "--cwd",
    resume_last = { "<exe>", "--cwd", "<root>", "--continue" },
    resume_picker = { "<exe>", "--cwd", "<root>" },
    session_root = home .. "/.grok/sessions",
  },
}

M.registry_order = { "codex", "deepseek", "kimi", "grok" }

function M.entry(id)
  return REGISTRY[id]
end

--- Resolve executable: full path found on disk, else bare PATH name, else nil.
--- MUST NOT call run_child_process (config-load safety).
function M.resolve_exe(id)
  local entry = REGISTRY[id]
  if not entry then
    return nil
  end
  for _, p in ipairs(entry.candidates) do
    if file_exists(p) then
      return p
    end
  end
  local path_env = os.getenv("PATH") or ""
  for dir in path_env:gmatch("[^:]+") do
    dir = tostring(dir):gsub("^%s+", ""):gsub("%s+$", "")
    if dir ~= "" and dir:sub(1, 1) ~= "\\" then
      for _, name in ipairs(entry.path_names) do
        local p = dir .. "/" .. name
        if file_exists(p) then
          return p
        end
      end
    end
  end
  return nil
end

function M.is_installed(id)
  return M.resolve_exe(id) ~= nil
end

--- Installed agents in registry order (cached 30s, no per-render file IO)
local detect_cache = { at = 0, result = nil }

function M.installed()
  local now = os.time()
  if detect_cache.result and now - detect_cache.at < 30 then
    return detect_cache.result
  end
  local out = {}
  for _, id in ipairs(M.registry_order) do
    if M.is_installed(id) then
      table.insert(out, id)
    end
  end
  detect_cache = { at = now, result = out }
  return out
end

function M.invalidate_cache()
  detect_cache = { at = 0, result = nil }
end

--- Default agent resolution (D-005): explicit third column > first installed
function M.default_for(path)
  local desk = require("desk")
  local bound = desk.agent_for_path(path)
  if bound and REGISTRY[bound] and M.is_installed(bound) then
    return bound
  end
  local installed = M.installed()
  if #installed > 0 then
    return installed[1]
  end
  return nil
end

--- New-session args for an agent bound to <root>
function M.new_args(id, root)
  local entry = REGISTRY[id]
  if not entry then
    return nil
  end
  local exe = M.resolve_exe(id) or entry.path_names[1]
  if entry.launch_mode == "flag" then
    return { exe, entry.cwd_flag, root }
  end
  return { exe }
end

--- Resume args (most recent session via official interface)
function M.resume_args(id, root)
  local entry = REGISTRY[id]
  if not entry then
    return nil
  end
  local exe = M.resolve_exe(id) or entry.path_names[1]
  local out = {}
  for _, part in ipairs(entry.resume_last) do
    part = part:gsub("<exe>", exe):gsub("<root>", root)
    table.insert(out, part)
  end
  return out
end

--- Spawn cwd for an agent: flag-mode agents get project root as spawn cwd too
function M.spawn_cwd(id, root)
  return root
end

return M
