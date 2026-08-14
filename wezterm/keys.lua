-- =============================================================================
--  AI STAR CUBE · macOS · key contract (D-M1-003)
--  Cmd+Shift primary; Fn+F aliases; no Leader (D-007); zero Ctrl bindings.
--  Workbench keys are fully digested by WezTerm — never reach agent TUIs.
--  Key names use lowercase letters + explicit SHIFT|SUPER mods (canonical form).
--  M4 wiring: all actions bound to real implementations.
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action
local init = require("init")
local layouts = require("layouts")
local sidebar = require("sidebar")
local help = require("help")

local M = {}

local function cb(fn)
  return wezterm.action_callback(fn)
end

function M.apply(config)
  config.leader = nil
  config.disable_default_key_bindings = false

  config.keys = {
    ------------------------------------------------------------------
    -- Primary: Cmd family (window-local, agent-transparent)
    ------------------------------------------------------------------
    { key = "t", mods = "SUPER", action = cb(function(w, p) init.open_init_tab(w, p) end) },
    { key = "d", mods = "SHIFT|SUPER", action = cb(function(w, p) layouts.open_workbench(w, p) end) },
    { key = "e", mods = "SHIFT|SUPER", action = cb(function(w, p) sidebar.show(w, p) end) },
    { key = "h", mods = "SHIFT|SUPER", action = cb(function(w, p) help.toggle(w, p) end) },
    { key = "w", mods = "SHIFT|SUPER", action = act.CloseCurrentPane({ confirm = true }) },

    ------------------------------------------------------------------
    -- Aliases: Fn+F keys (macOS media-key layer; not a stability dependency)
    ------------------------------------------------------------------
    { key = "F3", mods = "NONE", action = cb(function(w, p) init.open_init_tab(w, p) end) },
    { key = "F4", mods = "NONE", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "F5", mods = "NONE", action = act.ReloadConfiguration },
    { key = "F6", mods = "NONE", action = cb(function(w, p) layouts.open_workbench(w, p) end) },
    { key = "F7", mods = "NONE", action = cb(function(w, p) sidebar.show(w, p) end) },
    { key = "F1", mods = "NONE", action = cb(function(w, p) help.toggle(w, p) end) },
  }

  wezterm.on("window-config-reloaded", function(window, pane)
    pcall(function()
      window:toast_notification(
        "AI STAR CUBE",
        "配置已重载 · Cmd+T Init 面板 · Cmd+Shift+D 三栏 · Cmd+Shift+E 侧栏 · Cmd+Shift+H 速查",
        nil,
        5000
      )
    end)
  end)
end

return M
