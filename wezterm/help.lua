-- =============================================================================
--  AI STAR CUBE · macOS · cheatsheet panel (M4)
--  Toggle: split a right pane printing cheatsheet.txt; toggle again closes it.
--  Detection: foreground argv contains cheatsheet.txt (works across versions).
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local cheatsheet_file = wezterm.home_dir .. "/.config/wezterm/cheatsheet.txt"

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 2500)
  end)
end

local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function is_help_pane(pane)
  if not pane then
    return false
  end
  local hit = false
  pcall(function()
    local info = pane:get_foreground_process_info()
    if info and info.argv then
      for _, a in ipairs(info.argv) do
        local s = tostring(a)
        if s:find("wz-help-pane", 1, true) or s:find("cheatsheet.txt", 1, true) then
          hit = true
          return
        end
      end
    end
  end)
  return hit
end

local function find_help_pane(window)
  local ok, mux_win = pcall(function()
    return window:mux_window()
  end)
  if not ok or not mux_win then
    return nil
  end
  local ok_tabs, tabs = pcall(function()
    return mux_win:tabs_with_info()
  end)
  if not ok_tabs or not tabs then
    return nil
  end
  for _, ti in ipairs(tabs) do
    local ok_panes, panes = pcall(function()
      return ti.tab:panes_with_info()
    end)
    if ok_panes and panes then
      for _, pi in ipairs(panes) do
        if is_help_pane(pi.pane) then
          return pi.pane
        end
      end
    end
  end
  return nil
end

function M.toggle(window, pane)
  local existing = find_help_pane(window)
  if existing then
    pcall(function()
      window:perform_action(act.CloseCurrentPane({ confirm = false }), existing)
    end)
    toast(window, "AI STAR CUBE", "速查面板已关闭", 1800)
    return
  end
  local ok, side = pcall(function()
    return pane:split({
      direction = "Right",
      size = 0.38,
      args = {
        "/bin/zsh",
        "-l",
        "-c",
        "cat " .. sh_quote(cheatsheet_file) .. " 2>/dev/null; exec -a wz-help-pane zsh -l",
      },
      cwd = wezterm.home_dir,
    })
  end)
  if not ok or not side then
    toast(window, "AI STAR CUBE", "速查面板打开失败", 3500)
    return
  end
  pcall(function()
    side:activate()
  end)
  toast(window, "AI STAR CUBE", "速查面板 · Cmd+Shift+H 或面板内 q/exit 关闭", 2800)
end

function M.apply(config)
end

return M
