-- =============================================================================
--  AI STAR CUBE · macOS · Explorer entry (M4)
--  Cmd+Shift+E / Fn+F7 opens a static Explorer panel tab (explorer.sh) rooted
--  at the current tab DESK — same static-screen form as the upstream
--  Show-Listing sidebar (F-006 contract).
-- =============================================================================

local wezterm = require("wezterm")
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

--- Open the Explorer panel tab rooted at the current tab DESK
function M.open(window, pane)
  local _, root = desk.ensure(window, pane)
  if not desk.is_strong_path(root) then
    toast(window, "Explorer", "未绑定项目 — 在 Init 面板 wz> 选任务，或 c 新建（Cmd+T 开面板）", 4500)
    return
  end
  local tab, main
  local ok, err = pcall(function()
    tab, main = window:mux_window():spawn_tab({
      args = { "/bin/zsh", "-l", "-c", "exec zsh " .. explorer_script .. " " .. sh_quote(root) },
      cwd = root,
    })
  end)
  if not ok or not main then
    toast(window, "Explorer", "页签创建失败: " .. tostring(err or "nil"), 4500)
    return
  end
  if tab then
    pcall(function()
      tab:set_title("Explorer")
    end)
  end
  if main then
    pcall(function()
      main:activate()
    end)
  end
end

-- Back-compat alias (keys.lua calls sidebar.show)
M.show = M.open

function M.apply(config)
end

return M
