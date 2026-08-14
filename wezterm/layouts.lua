-- =============================================================================
--  AI STAR CUBE · macOS · layouts (M4: three-pane AI desk)
--  Contract (upstream D-008 + H-1 hardening):
--    - Gate FIRST: unbound tab → toast, zero spawn. Never spawn before R1.
--    - Equal-footing agent picker: default = desk-roots column 3 routed first,
--      single installed agent skips the picker, Esc cancels with zero spawn.
--    - Three panes: agent (splash) + shell + git monitor, all under project root.
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action
local desk = require("desk")
local agents = require("agents")

local M = {}

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 3000)
  end)
end

local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- Git monitor pane (right-bottom): title + git status, stays in shell
local function monitor_args(name, root)
  return {
    "/bin/zsh",
    "-l",
    "-c",
    "echo '  ══ 任务监视 · Task Monitor ══'; "
      .. "echo '  项目: " .. name .. "'; "
      .. "git -C " .. sh_quote(root) .. " status -sb 2>/dev/null; "
      .. "echo; echo '  常用: git status | git diff --stat'; "
      .. "exec zsh -l",
  }
end

--- Spawn the three-pane desk in a new tab (gate already passed upstream)
function M.spawn_workbench(window, pane, root, agent_id)
  local name = desk.project_label(root)
  local entry = agents.entry(agent_id)
  local tab, main
  local ok, err = pcall(function()
    tab, main = window:mux_window():spawn_tab({
      args = agents.splash_args(agent_id, root),
      cwd = root,
    })
  end)
  if not ok or not main then
    toast(window, "AI 对话桌", "页签创建失败: " .. tostring(err or "nil"), 4500)
    return
  end
  local shell = main:split({
    direction = "Right",
    size = 0.30,
    args = { "/bin/zsh", "-l" },
    cwd = root,
  })
  if shell then
    shell:split({
      direction = "Bottom",
      size = 0.42,
      args = monitor_args(name, root),
      cwd = root,
    })
  end
  main:activate()
  if tab then
    pcall(function()
      tab:set_title("✦ " .. name)
    end)
    desk.bind_tab(tab, root, main)
  end
  toast(window, "AI 对话桌", entry.display .. " · " .. name .. " · " .. desk.short_path(root, 42), 3500)
end

--- Equal-footing agent picker; single agent skips; Esc cancels zero spawn
function M.pick_and_spawn(window, pane, root)
  local installed = agents.installed()
  if #installed == 0 then
    toast(window, "AI 对话桌", "未检测到 agent CLI — 请先安装（codex 等）", 4500)
    return
  end
  if #installed == 1 then
    M.spawn_workbench(window, pane, root, installed[1])
    return
  end
  local preferred = desk.agent_for_path(root)
  local order = {}
  if preferred then
    table.insert(order, preferred)
  end
  for _, id in ipairs(installed) do
    if id ~= preferred then
      table.insert(order, id)
    end
  end
  local choices = {}
  for _, id in ipairs(order) do
    local entry = agents.entry(id)
    local label = entry.display
    if id == preferred then
      label = label .. "  ★默认(绑定)"
    elseif not preferred and id == agents.registry_order[1] then
      label = label .. "  ★默认"
    end
    table.insert(choices, { id = id, label = label })
  end
  window:perform_action(
    act.InputSelector({
      title = "AGENT · " .. desk.project_label(root),
      fuzzy = false,
      choices = choices,
      action = wezterm.action_callback(function(w, p, id, _)
        if id then
          M.spawn_workbench(w, p, root, id)
        end
      end),
    }),
    pane
  )
end

--- Cmd+Shift+D / Fn+F6: gate first, then picker, then spawn
function M.open_workbench(window, pane)
  local _, root = desk.ensure(window, pane)
  if not desk.is_strong_path(root) then
    toast(window, "AI 对话桌", "未绑定项目 — 先 Cmd+Shift+L 选任务或 Cmd+Shift+N 新建", 4500)
    return
  end
  M.pick_and_spawn(window, pane, root)
end

function M.apply(config)
end

return M
