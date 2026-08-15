-- =============================================================================
--  AI STAR CUBE · macOS · key contract (D-M1-009)
--  REGRESSION LESSON (2026-08-15): WezTerm canonicalizes SHIFT|SUPER + letter
--  to UPPERCASE + SUPER — so Cmd+Shift+W/H/D/E were actually bound as plain
--  Cmd+W/H/D/E, hijacking macOS defaults (Cmd+W close-tab, Cmd+H hide-app).
--  New primary set uses Cmd+F-keys (no canonicalization issue; verified to
--  reach WezTerm with SUPER modifier on this machine) + Fn+F aliases.
--  Cmd+W / Cmd+H / Cmd+D / Cmd+E stay 100% default macOS behavior.
--  No Leader (D-007); zero Ctrl bindings (D-M1-003).
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
    { key = "F1", mods = "SUPER", action = cb(function(w, p) help.toggle(w, p) end) },
    { key = "F3", mods = "SUPER", action = cb(function(w, p) init.open_init_tab(w, p) end) },
    { key = "F4", mods = "SUPER", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "F6", mods = "SUPER", action = cb(function(w, p) layouts.open_workbench(w, p) end) },
    { key = "F7", mods = "SUPER", action = cb(function(w, p) sidebar.show(w, p) end) },

    ------------------------------------------------------------------
    -- Aliases: Fn+F keys (macOS media-key layer)
    --   media mode (default): Fn+F1..F7 deliver these same keycodes
    --   standard mode: bare F1..F7 deliver them directly
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
        "配置已重载 · Cmd+T Init · Cmd+F1 速查 · Cmd+F3 Init · Cmd+F4 关窗格 · Cmd+F6 三栏 · Cmd+F7 Explorer",
        nil,
        5000
      )
    end)
  end)
end

return M
