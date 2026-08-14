-- =============================================================================
--  AI STAR CUBE · macOS edition (WZ_AiWorkBench-macOS)
--  Entry point. Load safety contract inherited from upstream bf1f6ef:
--    - Config evaluation must NEVER call run_child_process / heavy IO.
--    - Modules are soft-required; one broken file cannot wipe the whole config.
--    - package.loaded is cleared for our modules so reloads pick up new code.
-- =============================================================================

local wezterm = require("wezterm")

local config_dir = wezterm.config_file:match("(.*)/[^/]+$")
if config_dir then
  package.path = config_dir .. "/?.lua;" .. package.path
end

do
  local doomed = {}
  for k in pairs(package.loaded) do
    if
      type(k) == "string"
      and (
        k == "options" or k == "keys" or k == "desk" or k == "agents" or k == "status" or k == "layouts"
      )
    then
      table.insert(doomed, k)
    end
  end
  for _, k in ipairs(doomed) do
    package.loaded[k] = nil
  end
end

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Minimal baseline if modules fail
config.color_scheme = "Catppuccin Mocha"
config.check_for_updates = false
config.automatically_reload_config = true

local load_errors = {}

local function safe_require(name)
  local ok, mod = pcall(require, name)
  if not ok then
    table.insert(load_errors, name .. ": " .. tostring(mod))
    pcall(function()
      wezterm.log_error("[macos-workbench] require failed: " .. name .. " -> " .. tostring(mod))
    end)
    return nil
  end
  return mod
end

local function safe_apply(label, mod)
  if not mod or type(mod.apply) ~= "function" then
    table.insert(load_errors, label .. ": missing apply()")
    return
  end
  local ok, err = pcall(mod.apply, config)
  if not ok then
    table.insert(load_errors, label .. ".apply: " .. tostring(err))
    pcall(function()
      wezterm.log_error("[macos-workbench] apply failed: " .. label .. " -> " .. tostring(err))
    end)
  end
end

-- Load order: options (chrome) -> keys -> status -> layouts
safe_apply("options", safe_require("options"))
safe_apply("keys", safe_require("keys"))
safe_apply("status", safe_require("status"))
safe_apply("layouts", safe_require("layouts"))

if #load_errors > 0 then
  wezterm.GLOBAL = wezterm.GLOBAL or {}
  wezterm.GLOBAL.macos_workbench_load_errors = load_errors
  wezterm.on("gui-attached", function()
    pcall(function()
      local msg = table.concat(load_errors, " | ")
      if #msg > 180 then
        msg = msg:sub(1, 177) .. "..."
      end
      for _, gui in ipairs(wezterm.gui.gui_windows() or {}) do
        gui:toast_notification("AI STAR CUBE 模块加载告警", msg, nil, 8000)
      end
    end)
  end)
end

return config

-- reload-bump: 2026-08-14T20:00:00-m2-core-shell
