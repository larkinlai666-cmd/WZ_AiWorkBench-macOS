-- =============================================================================
--  AI STAR CUBE · macOS · Explorer sidebar entry (M5: resident left rail)
--  Upstream design (projects.lua open_sidebar, bf1f6ef) distilled:
--    - resident rail: split Left from the main-stage pane INSIDE the current
--      tab — never a separate tab/window
--    - bound to the main view: root = current tab task desk (tab-first),
--      initial VIEW = focused pane cwd when it lives inside the desk tree
--    - singleton per tab: already open -> focus + in-place "r" refresh,
--      never a second split
--    - rail width 0.21 (≈30% narrower than legacy 0.30)
--  ACCESSOR LESSON (2026-08-15): PaneInformation.pane_id /
--  TabInformation.tab_id are NIL in this WezTerm build — use
--  pi.pane:pane_id() / tab:tab_id(). perform_action(action, other_pane)
--  does NOT target other_pane — activate first, then act.
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action
local desk = require("desk")

local M = {}

local home = wezterm.home_dir
local explorer_script = home .. "/.config/wezterm/explorer.sh"

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 3000)
  end)
end

local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
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

local function is_explorer_pane(pane)
  if not pane then
    return false
  end
  local hit = false
  pcall(function()
    local info = pane:get_foreground_process_info()
    if info and info.argv then
      for _, a in ipairs(info.argv) do
        local s = tostring(a)
        if s:find("explorer%.sh", 1) then
          hit = true
          return
        end
      end
    end
  end)
  return hit
end

local function active_tab(window)
  local ok, tab = pcall(function()
    return window:active_tab()
  end)
  if ok and tab then
    return tab
  end
  return nil
end

--- find existing sidebar pane inside <tab>; expect_id first, argv fallback
local function find_sidebar_in(tab, expect_id)
  local ok_panes, panes = pcall(function()
    return tab:panes_with_info()
  end)
  if not ok_panes or not panes then
    return nil
  end
  if expect_id then
    for _, pi in ipairs(panes) do
      if pane_id_of(pi) == expect_id then
        return pi.pane
      end
    end
  end
  for _, pi in ipairs(panes) do
    if is_explorer_pane(pi.pane) then
      return pi.pane
    end
  end
  return nil
end

--- main-stage host: largest non-explorer pane (upstream host_pane_for_sidebar)
local function host_pane_in(tab, fallback)
  local ok_panes, panes = pcall(function()
    return tab:panes_with_info()
  end)
  if not ok_panes or not panes or #panes == 0 then
    return fallback
  end
  local best, best_area = nil, -1
  for _, pi in ipairs(panes) do
    if pi.pane and not is_explorer_pane(pi.pane) then
      local area = 0
      if type(pi.width) == "number" and type(pi.height) == "number" then
        area = pi.width * pi.height
      end
      if area > best_area then
        best_area = area
        best = pi.pane
      end
    end
  end
  return best or fallback
end

--- Cmd+F7 / F7: resident Explorer rail bound to the current tab's main view
function M.show(window, pane)
  local tab = active_tab(window)
  if not tab then
    return
  end
  local tab_id = tab_id_of(tab)
  local record = wezterm.GLOBAL.macos_sidebar_tabs or {}

  -- singleton: focus + in-place refresh (no second split)
  local existing = find_sidebar_in(tab, tab_id and record[tab_id] or nil)
  if existing then
    pcall(function()
      existing:activate()
    end)
    pcall(function()
      window:perform_action(act.SendString("r\r"), existing)
    end)
    toast(window, "Explorer", "已聚焦现有侧栏并刷新 — 未新建分栏", 3000)
    return
  end

  -- root: tab desk first (bound main view), then focused pane cwd
  local _, root = desk.ensure(window, pane)
  if not desk.is_strong_path(root) then
    local cwd = desk.cwd_from_pane(pane)
    if desk.is_strong_path(cwd) then
      root = cwd
    else
      toast(window, "Explorer", "未绑定项目 — 在 Init 面板 wz> 选任务，或 c 新建（Cmd+T 开面板）", 4500)
      return
    end
  end

  -- initial VIEW: focused pane cwd when it lives inside the desk tree
  local view0 = ""
  local pane_cwd = desk.cwd_from_pane(pane)
  if desk.is_strong_path(pane_cwd) and (pane_cwd == root or pane_cwd:sub(1, #root + 1) == root .. "/") then
    view0 = pane_cwd
  end

  local host = host_pane_in(tab, pane)
  local cmd = "exec zsh " .. explorer_script .. " " .. sh_quote(root)
  if view0 ~= "" then
    cmd = cmd .. " " .. sh_quote(view0)
  end
  local ok, side = pcall(function()
    return host:split({
      direction = "Left",
      size = 0.21,
      args = { "/bin/zsh", "-l", "-c", cmd },
      cwd = root,
    })
  end)
  if not ok or not side then
    toast(window, "Explorer", "侧栏创建失败: " .. tostring(side), 4500)
    return
  end
  if tab_id then
    record[tab_id] = side:pane_id()
    wezterm.GLOBAL.macos_sidebar_tabs = record
  end
  desk.bind_tab(tab, root, side)
  pcall(function()
    side:activate()
  end)
  toast(window, "Explorer", desk.project_label(root) .. " · 常驻侧栏 · 再按 Cmd+F7 聚焦并刷新", 3000)
end

-- Back-compat alias (keys.lua calls sidebar.show)
M.open = M.show

function M.apply(config)
end

return M
