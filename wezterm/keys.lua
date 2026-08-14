-- =============================================================================
--  AI STAR CUBE · macOS · key contract (D-M1-003)
--  Cmd+Shift primary; Fn+F aliases; no Leader (D-007); zero Ctrl bindings.
--  Workbench keys are fully digested by WezTerm — never reach agent TUIs.
--  Key names use lowercase letters + explicit SHIFT|SUPER mods (canonical form).
--  M3 wiring: Cmd+T = Init hub tab; Cmd+Shift+L = task panel; Cmd+Shift+N = wizard.
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action
local init = require("init")

local M = {}

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 2500)
  end)
end

local function cb(fn)
  return wezterm.action_callback(fn)
end

--- Cmd+T: new tab = Init hub (welcome screen + auto task picker)
local function new_init_tab(window, pane)
  local tab, main
  pcall(function()
    tab, main = window:mux_window():spawn_tab({ args = init.welcome_args(), cwd = wezterm.home_dir })
  end)
  if tab then
    pcall(function()
      tab:set_title("Init")
    end)
  end
  if main then
    pcall(function()
      main:activate()
    end)
    wezterm.time.call_after(0.4, function()
      pcall(function()
        init.show_hub(window, window:active_pane())
      end)
    end)
  end
end

function M.apply(config)
  config.leader = nil
  config.disable_default_key_bindings = false

  config.keys = {
    ------------------------------------------------------------------
    -- Primary: Cmd family (window-local, agent-transparent)
    ------------------------------------------------------------------
    { key = "t", mods = "SUPER", action = cb(new_init_tab) },
    { key = "l", mods = "SHIFT|SUPER", action = cb(function(w, p) init.show_hub(w, p) end) },
    { key = "n", mods = "SHIFT|SUPER", action = cb(function(w, p) init.new_project(w, p) end) },
    { key = "d", mods = "SHIFT|SUPER", action = cb(function(w, p)
      toast(w, "AI STAR CUBE", "三栏 AI 桌 — M4 交付中（agent 单页签已可用：选任务即可启动）", 2500)
    end) },
    { key = "e", mods = "SHIFT|SUPER", action = cb(function(w, p)
      toast(w, "AI STAR CUBE", "Explorer 侧栏 — M4 交付中", 2500)
    end) },
    { key = "h", mods = "SHIFT|SUPER", action = cb(function(w, p)
      toast(w, "AI STAR CUBE", "速查面板 — M4 交付中", 2500)
    end) },
    { key = "w", mods = "SHIFT|SUPER", action = act.CloseCurrentPane({ confirm = true }) },

    ------------------------------------------------------------------
    -- Aliases: Fn+F keys (macOS media-key layer; not a stability dependency)
    ------------------------------------------------------------------
    { key = "F3", mods = "NONE", action = cb(function(w, p) init.new_project(w, p) end) },
    { key = "F4", mods = "NONE", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "F5", mods = "NONE", action = act.ReloadConfiguration },
    { key = "F6", mods = "NONE", action = cb(function(w, p)
      toast(w, "AI STAR CUBE", "三栏 AI 桌 — M4 交付中", 2500)
    end) },
    { key = "F7", mods = "NONE", action = cb(function(w, p)
      toast(w, "AI STAR CUBE", "Explorer 侧栏 — M4 交付中", 2500)
    end) },
    { key = "F1", mods = "NONE", action = cb(function(w, p)
      toast(w, "AI STAR CUBE", "速查面板 — M4 交付中", 2500)
    end) },
  }

  wezterm.on("window-config-reloaded", function(window, pane)
    pcall(function()
      window:toast_notification(
        "AI STAR CUBE",
        "配置已重载 · Cmd+T Init · Cmd+Shift+L 任务面板 · Cmd+Shift+N 新建",
        nil,
        5000
      )
    end)
  end)
end

return M
