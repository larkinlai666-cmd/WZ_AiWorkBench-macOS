-- =============================================================================
--  AI STAR CUBE · macOS · key contract (D-M1-003)
--  Cmd+Shift primary; Fn+F aliases; no Leader (D-007); zero Ctrl bindings.
--  Workbench keys are fully digested by WezTerm — never reach agent TUIs.
--  Key names use lowercase letters + explicit SHIFT|SUPER mods (canonical form).
--  Default keys (Cmd+T/R/C/V/W/F/N/Q/H, Cmd+1-9, Cmd+Shift+P) are preserved.
--  M2 scope: N/D/E/H actions toast their milestone; real flows land in M3/M4.
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 2500)
  end)
end

local function cb(fn)
  return wezterm.action_callback(fn)
end

local function pending(window, pane, name, milestone)
  toast(window, "AI STAR CUBE", name .. " — " .. milestone .. " 交付中（契约已绑定）", 2200)
end

function M.apply(config)
  config.leader = nil
  config.disable_default_key_bindings = false

  config.keys = {
    ------------------------------------------------------------------
    -- Primary: Cmd+Shift family (window-local, agent-transparent)
    ------------------------------------------------------------------
    { key = "n", mods = "SHIFT|SUPER", action = cb(function(w, p) pending(w, p, "新建项目向导", "M3") end) },
    { key = "d", mods = "SHIFT|SUPER", action = cb(function(w, p) pending(w, p, "三栏 AI 桌", "M4") end) },
    { key = "e", mods = "SHIFT|SUPER", action = cb(function(w, p) pending(w, p, "Explorer 侧栏", "M4") end) },
    { key = "h", mods = "SHIFT|SUPER", action = cb(function(w, p) pending(w, p, "速查面板", "M4") end) },
    { key = "w", mods = "SHIFT|SUPER", action = act.CloseCurrentPane({ confirm = true }) },

    ------------------------------------------------------------------
    -- Aliases: Fn+F keys (macOS media-key layer; not a stability dependency)
    ------------------------------------------------------------------
    { key = "F3", mods = "NONE", action = cb(function(w, p) pending(w, p, "新建项目向导", "M3") end) },
    { key = "F4", mods = "NONE", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "F5", mods = "NONE", action = act.ReloadConfiguration },
    { key = "F6", mods = "NONE", action = cb(function(w, p) pending(w, p, "三栏 AI 桌", "M4") end) },
    { key = "F7", mods = "NONE", action = cb(function(w, p) pending(w, p, "Explorer 侧栏", "M4") end) },
    { key = "F1", mods = "NONE", action = cb(function(w, p) pending(w, p, "速查面板", "M4") end) },
  }

  wezterm.on("window-config-reloaded", function(window, pane)
    pcall(function()
      window:toast_notification(
        "AI STAR CUBE",
        "配置已重载 · Cmd+Shift+N 新建 · Cmd+Shift+D 三栏 · Cmd+Shift+E 侧栏",
        nil,
        5000
      )
    end)
  end)
end

return M
