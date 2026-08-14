# 验收清单与里程碑

## 验收清单（原版 A1–C4 逐项转写为 macOS 语境）

### A · 身份与门禁

| # | 项 | 通过标准 |
|---|---|---|
| A1 | Init 任务表 | 冷启动/新标签出现 Init 面板；TASK 来自 desk-roots；home 不在正式 TASK |
| A2 | 弱路径拒开 agent | 未绑定页签 F6 只弹 toast 零 spawn；Init SYS 行拒 Enter；侧栏在 home 按启动被拒 |
| A3 | 新建冻结 | 向导一次写目录 + desk-roots 显式三列 + `.wz-project`；agent 仅以该路径为 cwd 启动 |
| A4 | 路径槽 | 左状态栏路径槽 = 当前页签 DESK（强路径），与 agent 启动 cwd 一致 |
| A5 | 项目名 | 页签/列表项目名 = 绑定名，不是会话标题/cwd leaf |

### B · 键位与布局

| # | 项 | 通过标准 |
|---|---|---|
| B1 | 三栏 | 绑定任务上 Cmd+Shift+D → agent 平权选择器（默认=第三列路由第一，↑↓+Enter，Esc 零 spawn）；单 agent 自动跳过；未绑定只 toast |
| B2 | 侧栏同根 | 先点 AI 窗格再 Cmd+Shift+E → 侧栏根 = 页签 DESK |
| B3 | 速查 | Cmd+Shift+H 开/关 cheatsheet |
| B4 | Init 两步流 | `wz>` 任务号（`n<号>` 新会话）→ `agent>` 模型号/Enter=默认/q 取消零 spawn；两位数直启；9 行封顶；键入零重绘 |
| B5 | 重载 | Cmd+R toast「配置已重载」 |
| B6 | 不抢 agent | Cmd 绑定全部窗口内消化；无 Ctrl 绑定；agent 字母键原样穿透；无 Leader |

### C · 启动与可移植

| # | 项 | 通过标准 |
|---|---|---|
| C1 | spawn 纪律 | 开 agent 走 wezterm spawn 页签，不叠独立 OS 窗口 |
| C2 | Doctor | 安装器 Doctor 全绿（≥1 已装 agent 通过；零 agent 警告不阻断） |
| C3 | 纯 shell 逃生 | Init 面板按 `s` 得纯 zsh 页签 |
| C4 | 配置一致性 | 发布快照与用户配置目录 md5 一致；校验器全绿 |

### D · 已知可接受残留

- 旧侧栏不自动跟新对话（关闭后重开）。
- Fn+F 别名依赖用户环境，主路径 Cmd 不受影响。
- agent 私有会话数据不解析，续聊一律走官方 resume 接口。

## 里程碑

| # | 里程碑 | 交付 | 验收 |
|---|---|---|---|
| M1 | 设计契约包 | DECISIONS/DESIGN/KEYBINDINGS/AGENT_REGISTRY/ACCEPTANCE | 本包被用户确认 |
| M2 | 核心壳 | wezterm.lua + options/status/keys + desk.lua POSIX 化 + desk-roots 绑定 | A4/A5 + 门禁逻辑静态验证 |
| M3 | Init 中枢 + agent 适配 | init.lua 两步流 + agents.lua 注册表 + codex 启动/续聊 | A1/A2/A3/B4/C3 |
| M4 | 三栏 + 侧栏 + 动画 | layouts.lua + sidebar.lua + splash | B1/B2/B3 |
| M5 | 安装器 + 收口 | Install-WZ.sh + Doctor + 防线全绿 | C1/C2/C4 + 全清单打勾 |

## 工程防线（每轮收口必跑）

- load guard：加载期零副作用静态扫描。
- lua 配平检查。
- 镜像 md5：发布快照与 ~/.config/wezterm 一致。
- 管道冒烟：Init 主循环非交互输入冒烟。
- `wezterm -n show-keys --lua` 键位冲突核对。
