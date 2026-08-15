-- =============================================================================
--  AI STAR CUBE · macOS · cheatsheet panel (M4)
--  Toggle: split a right pane printing cheatsheet.txt; toggle again closes it.
--  Same-tab scope only (cross-tab close killed unrelated tabs — 2026-08-15).
--  Tracking: wezterm.GLOBAL.macos_help_tabs[tab_id] = pane_id.
--  ACCESSOR LESSON: in this WezTerm build PaneInformation.pane_id and
--  TabInformation.tab_id are NIL — must use pi.pane:pane_id() /
--  ti.tab:tab_id() instead (verified via key-event diag logs).
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

local function tab_id_of(tab)
  if not tab then
    return nil
  end
  local ok, v = pcall(function()
    return tab:tab_id()
  end)
  if ok and v ~= nil and tostring(v) ~= "" then
    return tostring(v)
  end
  return nil
end

local function pane_id_of(pi)
  if not pi or not pi.pane then
    return nil
  end
  local ok, v = pcall(function()
    return pi.pane:pane_id()
  end)
  if ok and v ~= nil then
    return v
  end
  return nil
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

--- returns tab, tab_id for the tab containing <pane>
local function current_tab_info(window, pane)
  local mux_win = window:mux_window()
  if not mux_win then
    return nil, nil
  end
  local ok_pid, pid = pcall(function()
    return pane:pane_id()
  end)
  if not ok_pid or pid == nil then
    return nil, nil
  end
  local ok_tabs, tabs = pcall(function()
    return mux_win:tabs_with_info()
  end)
  if not ok_tabs or not tabs then
    return nil, nil
  end
  for _, ti in ipairs(tabs) do
    local ok_panes, panes = pcall(function()
      return ti.tab:panes_with_info()
    end)
    if ok_panes and panes then
      for _, pi in ipairs(panes) do
        if pane_id_of(pi) == pid then
          return ti.tab, tab_id_of(ti.tab)
        end
      end
    end
  end
  return nil, nil
end

--- returns help pane object within <tab>, or nil
local function help_pane_in(tab, expect_id)
  local ok_panes, panes = pcall(function()
    return tab:panes_with_info()
  end)
  if not ok_panes or not panes then
    return nil
  end
  for _, pi in ipairs(panes) do
    local pid = pane_id_of(pi)
    if expect_id and pid == expect_id then
      return pi.pane
    end
    if is_help_pane(pi.pane) then
      return pi.pane
    end
  end
  return nil
end

function M.toggle(window, pane)
  local ok, err = pcall(toggle_inner, window, pane)
  if not ok then
    wezterm.log_error("help.toggle failed: " .. tostring(err))
    toast(window, "AI STAR CUBE", "速查面板错误: " .. tostring(err), 5000)
  end
end

function toggle_inner(window, pane)
  local tab, tab_id = current_tab_info(window, pane)
  if not tab then
    return
  end
  local record = wezterm.GLOBAL.macos_help_tabs or {}
  local recorded_id = tab_id and record[tab_id] or nil

  -- 1) deterministic record lookup (primary path)
  local help_here = recorded_id and help_pane_in(tab, recorded_id) or nil

  -- 2) argv fallback (record lost on reload; foreground info may be nil)
  if not help_here then
    help_here = help_pane_in(tab, nil)
  end

  if help_here then
    if tab_id then
      record[tab_id] = nil
    end
    wezterm.GLOBAL.macos_help_tabs = record
    -- activate first: perform_action's pane argument is not honored in this
    -- WezTerm build, so the close must land on the FOCUSED pane
    pcall(function()
      help_here:activate()
    end)
    pcall(function()
      window:perform_action(act.CloseCurrentPane({ confirm = false }), help_here)
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
    toast(window, "AI STAR CUBE", "速查面板打开失败: " .. tostring(side), 3500)
    return
  end
  if tab_id then
    record[tab_id] = side:pane_id()
    wezterm.GLOBAL.macos_help_tabs = record
  end
  pcall(function()
    side:activate()
  end)
  toast(window, "AI STAR CUBE", "速查面板 · Cmd+F1 或再按一次关闭", 2800)
end

function M.apply(config)
end

return M
