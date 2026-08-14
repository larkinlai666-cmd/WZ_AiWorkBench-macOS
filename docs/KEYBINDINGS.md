# 键位契约（M1 · 已对默认键位做冲突核对）

核对基准：WezTerm 20240203 默认 macOS 键表（`wezterm -n show-keys --lua`，2026-08-14 实测）。

## 原则

1. 工作台键全部为 Cmd / Cmd+Shift 组合，被 WezTerm 层完整拦截，绝不下发终端 → 与任何 agent TUI 零冲突。
2. 不绑任何 Ctrl+*、裸 F 键、裸字母键；agent 字母键（F2、Ctrl+; 等）原样穿透。
3. 复用 WezTerm 默认键（Cmd+T 新标签、Cmd+R 重载、Cmd+C/V 复制粘贴、Cmd+1–9 切标签、Cmd+Shift+P 命令面板），不重复绑定。
4. Fn+F 别名仅作兼容入口，不为稳定性依赖。
5. 无 Leader 层（继承 D-007）。

## 主键表

| 动作 | 主键 | 别名 | 默认冲突核对 |
|---|---|---|---|
| 新 Init 面板页签 | Cmd+T | Fn+F3 | 复用默认 Cmd+T 语义（default_prog=面板） |
| 三栏 AI 桌（agent 平权选择器） | Cmd+Shift+D | Fn+F6 | 无冲突 |
| Explorer 侧栏 | Cmd+Shift+E | Fn+F7 | 无冲突 |
| 速查面板 | Cmd+Shift+H | Fn+F1 | 无冲突（Cmd+H 默认=隐藏应用，保留） |
| 关闭窗格 | Cmd+Shift+W | Fn+F4 | 无冲突（Cmd+W 默认=关标签带确认，保留） |
| 重载配置 | Cmd+R（默认，直接复用） | Fn+F5 | 默认键，零新增 |

## Init 面板内键（静态屏行输入，仅面板 pane 生效）

- 数字 = 任务号；`n<号>` = 强制新会话；两位数 `<任务><agent>` = 一次直启（≤9 任务）。
- `c` = 新建任务向导；`s` = 纯 shell；`r` = 刷新；`q` = 退出面板（关标签）。
- step2 行输入：数字 = agent 号；Enter 空 = 默认（绑定列优先）；q = 取消零 spawn。

## 保留的 WezTerm 默认键（不覆盖）

Cmd+C/V 复制粘贴、Cmd+F 搜索、Cmd+W 关标签、Cmd+N 新窗口、Cmd+T 新标签、Cmd+R 重载、Cmd+1–9 切标签、Cmd+{/}/[/] 标签导航、Cmd+Shift+P 命令面板、Cmd+0/-/= 字号。

## 待验证项（M2 冻结前）

- 目标 WezTerm 版本升级后，重跑 `wezterm -n show-keys --lua` 核对默认表；若出现占用，工作台键整体换前缀（如 Cmd+Alt）而非局部让位。
