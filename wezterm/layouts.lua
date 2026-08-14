-- =============================================================================
--  AI STAR CUBE · macOS · layouts (M2 skeleton)
--  M2: gate-first discipline only. Agent picker + 3-pane spawn land in M4.
--  Contract: gate (R1) must run BEFORE any spawn; unbound tab → toast, zero spawn.
-- =============================================================================

local wezterm = require("wezterm")
local desk = require("desk")
local agents = require("agents")

local M = {}

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 3000)
  end)
end

--- M4 contract preview: gate-first, then spawn. Called by Cmd+Shift+D / Fn+F6.
function M.open_workbench(window, pane)
  local _, root = desk.ensure(window, pane)
  if not desk.is_strong_path(root) then
    toast(window, "AI 对话桌", "未绑定项目 — 先在任务上绑定（Init 面板 M3 交付）", 4500)
    return
  end
  -- M4 will: show equal-footing agent picker (default = desk-roots column 3 first),
  -- then spawn agent + shell + monitor three panes under this root.
  toast(window, "AI 对话桌", "三栏布局在 M4 交付 · 项目根已确认: " .. desk.short_path(root, 42), 3000)
end

function M.apply(config)
  -- Reserved for M4 launch-menu wiring.
end

return M
