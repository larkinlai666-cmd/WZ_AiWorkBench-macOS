-- =============================================================================
--  AI STAR CUBE · macOS · Init hub (M4, static panel)
--  Contract inherited from upstream D-009/D-010/D-012 (bf1f6ef):
--    - Cold start / new tab land on the Init static panel, never a bare shell.
--    - The panel itself is the two-step flow (task -> agent), line input driven.
--    - D-012: agent spawned -> panel exits -> sole-pane tab closes itself.
--  Implementation: init.sh runs inside the pane (zsh, the macOS builtin
--  runtime — symmetric to upstream's use of the Windows builtin PowerShell).
-- =============================================================================

local wezterm = require("wezterm")

local M = {}

local home = wezterm.home_dir
local init_script = home .. "/.config/wezterm/init.sh"

--- Spawn args for the Init panel pane
function M.panel_args()
  return { "/bin/zsh", "-l", "-c", "exec zsh " .. init_script }
end

--- Spawn a new Init tab and activate it
function M.open_init_tab(window, pane)
  local tab, main
  pcall(function()
    tab, main = window:mux_window():spawn_tab({ args = M.panel_args(), cwd = home })
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
  end
end

function M.apply(config)
  wezterm.on("gui-startup", function(cmd)
    local tab, pane, window
    pcall(function()
      if cmd and cmd.args and #cmd.args > 0 then
        tab, pane, window = wezterm.mux.spawn_window(cmd)
      else
        tab, pane, window = wezterm.mux.spawn_window({
          args = M.panel_args(),
          cwd = home,
        })
      end
    end)
    if tab then
      pcall(function()
        tab:set_title("Init")
      end)
    end
  end)
end

return M
