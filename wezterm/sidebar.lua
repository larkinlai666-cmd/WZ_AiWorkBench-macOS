-- =============================================================================
--  AI STAR CUBE · macOS · Explorer sidebar (M4, pure Lua)
--  Contract (upstream F-006 + B2):
--    - Same task root as the focused AI pane / current tab DESK.
--    - Clickable entries: dirs descend, files open with `open`.
--    - Weak root → toast, zero spawn.
--  Implementation: WezTerm InputSelector as the browsing surface (static,
--  no per-keystroke redraws — same discipline as upstream D-009).
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action
local desk = require("desk")
local layouts = require("layouts")

local M = {}

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 3000)
  end)
end

local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- List one directory level: { dirs = {...}, files = {...} }
local function list_dir(dir)
  local out = { dirs = {}, files = {} }
  local ok, stdout = wezterm.run_child_process({
    "/bin/zsh",
    "-lc",
    "ls -1Ap " .. sh_quote(dir) .. " 2>/dev/null",
  })
  if not ok or not stdout then
    return out
  end
  for line in tostring(stdout):gmatch("[^\r\n]+") do
    line = line:gsub("/$", "")
    if line ~= "" and line ~= "." and line ~= ".." then
      if line:match("/$") then
        table.insert(out.dirs, line:gsub("/$", ""))
      else
        table.insert(out.files, line)
      end
    end
  end
  table.sort(out.dirs)
  table.sort(out.files)
  return out
end

--- Browse one directory level (static selector = one redraw per navigation)
function M.browse(window, pane, dir, desk_root)
  dir = desk.normalize(dir) or wezterm.home_dir
  desk_root = desk.normalize(desk_root) or dir
  local entries = list_dir(dir)

  local choices = {}
  local parent = dir:match("^(.*)/[^/]+$")
  if parent and parent ~= "" then
    table.insert(choices, { id = "UP|" .. parent, label = "⬆ 上级目录" })
  end
  table.insert(choices, {
    id = "LAUNCH|" .. dir,
    label = "⚡ 在此启动 agent（任务根: " .. desk.short_path(desk_root, 34) .. "）",
  })
  for _, name in ipairs(entries.dirs) do
    table.insert(choices, { id = "D|" .. dir .. "/" .. name, label = "📁 " .. name })
  end
  for _, name in ipairs(entries.files) do
    table.insert(choices, { id = "F|" .. dir .. "/" .. name, label = "   " .. name })
  end

  window:perform_action(
    act.InputSelector({
      title = "Explorer · " .. desk.short_path(dir, 44),
      fuzzy = true,
      fuzzy_description = "type to filter: ",
      choices = choices,
      action = wezterm.action_callback(function(w, p, id, _)
        if not id or id == "" then
          return
        end
        local kind, target = id:match("^(%a+)|(.+)$")
        if kind == "UP" then
          M.browse(w, p, target, desk_root)
        elseif kind == "D" then
          M.browse(w, p, target, desk_root)
        elseif kind == "LAUNCH" then
          layouts.pick_and_spawn(w, p, desk_root)
        elseif kind == "F" then
          local ok, err = wezterm.run_child_process({ "open", target })
          if not ok then
            toast(w, "Explorer", "打开失败: " .. tostring(err), 3500)
          end
        end
      end),
    }),
    pane
  )
end

--- Cmd+Shift+E / Fn+F7: sidebar rooted at the current tab DESK
function M.show(window, pane)
  local _, root = desk.ensure(window, pane)
  if not desk.is_strong_path(root) then
    toast(window, "Explorer", "未绑定项目 — 先 Cmd+Shift+L 选任务或 Cmd+Shift+N 新建", 4500)
    return
  end
  M.browse(window, pane, root, root)
end

function M.apply(config)
end

return M
