# 键位契约（M4 · 2026-08-15 实测修订）

核对基准：WezTerm 20240203 默认 macOS 键表 + 本机实测 `show-keys --lua` + GUI 键事件日志（debug_key_events）逐键验证。

## 实测教训（为什么 V1 键位被推翻）

V1 用 Cmd+Shift+字母（D/E/H/W）。`show-keys --lua` 实测发现：**WezTerm 把 `SHIFT|SUPER + 字母` 规范化为 `大写字母 + SUPER`**，与裸 Cmd+字母完全等价：

- Cmd+Shift+H 实际绑定成了裸 Cmd+H → 抢走 macOS 默认"隐藏应用"
- Cmd+Shift+W 实际绑定成了裸 Cmd+W → 抢走 WezTerm 默认"关标签页"
- Cmd+Shift+D/E 同理变成裸 Cmd+D/E，裸按即触发工作台动作

结论：**任何 Cmd+Shift+字母组合在本平台不可用**，一律改用 Cmd+F 键系（F 键无此规范化问题，实测 `Cmd+F3` 以 `SUPER + Function(3)` 送达 WezTerm）。

## 原则

1. 主键 = Cmd+F 键系 + Cmd+T/Cmd+R；F 键裸按（Fn+F）作为别名。
2. 工作台键全部被 WezTerm 层消化，绝不下发终端 → 与任何 agent TUI 零冲突。
3. 不绑任何 Ctrl+*（D-M1-003）；Ctrl+F 键系经实测被 macOS 系统层吞掉（Ctrl+F3 未送达）。
4. Cmd+W 关标签、Cmd+H 隐藏应用、Cmd+D/E 等 macOS/WezTerm 默认键保持原样不覆盖。
5. 无 Leader 层（继承 D-007）。

## 主键表（实测有效）

| 动作 | 主键 | F 键别名 | 实测状态 |
|---|---|---|---|
| 新 Init 面板页签 | Cmd+T | F3 / Fn+F3 | 已 GUI 实测通过 |
| 三栏 AI 桌 | Cmd+F6 | F6 / Fn+F6 | 已 GUI 实测通过（先弹 agent 选择器） |
| Explorer 常驻侧栏 | Cmd+F7 | F7 / Fn+F7 | 已 GUI 实测通过（当前页签左侧展开，绑定任务根，singleton 聚焦刷新） |
| 速查面板 | Cmd+F1 | F1 / Fn+F1 | 已 GUI 实测通过（同页签开关） |
| 关闭窗格 | Cmd+F4 | F4 / Fn+F4 | 实测通过（确认弹窗） |
| 重载配置 | Cmd+R（默认） | F5 / Fn+F5 | 实测通过 |

F 键说明：媒体键模式（macOS 默认）下需按住 Fn（Fn+F1...）；开启系统设置"将 F1、F2 等键用作标准功能键"后可直接裸按，与 Windows 手感一致。F2 留空给 agent 自身。

## 已知状态依赖（重要）

- Explorer/三栏在"当前活动页签无法解析项目根"时只弹 toast 提示（不 spawn），属门禁行为而非失效。
- 速查面板 toggle 只作用于当前页签（跨页签关闭会误杀其他页签，2026-08-15 已修）。

## 回归防线

`scripts/check.sh` 含 effective-keymap 断言：`wezterm show-keys --lua` 实际生效表中必须存在 6 个 F 键 + Cmd+F 系绑定，且 Cmd+W/H 必须保持默认动作（防键位被抢占回归）。
