# macOS 版权威决策（Decisions）

ID 规则：F = 用户提供的事实；D = 用户批准的决策。全部 active，2026-08-14 生效。

## 索引

- F-M1-001 核心要求
- F-M1-002 设计基准
- D-M1-001 独立新仓库
- D-M1-002 纯 Lua 实现
- D-M1-003 Cmd 优先键位
- D-M1-004 Agent 平权注册表
- D-M1-005 蒸馏契约、独立实现
- D-M1-006 Init 静态屏用 zsh（修正 D-M1-002 面板部分）
- D-M1-007 zsh 禁用 path 变量名（保留变量陷阱）
- D-M1-008 walking-cat splash 动画（原版契约蒸馏）
- D-M1-009 键位主键 Cmd+F 系（Cmd+Shift+字母规范化陷阱）

## 记录

### F-M1-001 [active]

- 核心要求：**轻便、稳定、牢固、高不同公司 agent 兼容性**。
- 来源：用户 2026-08-14。
- 影响：全部技术选型与验收标准。

### F-M1-002 [active]

- 设计基准：WZ_AiStarCube 最新提交 `bf1f6ef`（2026-08-14，含 D-001~D-014）。
- 来源：用户确认该提交为最新版本（2026-08-14）。
- 影响：蒸馏清单范围，禁止回退到 2026-08-09 旧快照设计。

### D-M1-001 [active]

- 新建独立仓库，不同仓、不 fork、不引用原仓构建体系。
- 理由：原仓 PPS 验证器按整仓校验，同仓会纠缠生命周期；独立最轻、互不污染契约。
- 影响：仓库组织、验收与发布链路。

### D-M1-002 [active]

- 面板与工作台逻辑**纯 Lua** 实现，零外部脚本运行时依赖。
- 理由：pwsh 7 为百 MB 级外部依赖（违背轻便）；原版面板深度依赖 Windows 键码语义；Lua 运行于 WezTerm 受 load guard 保护的运行时内（稳定牢固）。
- 影响：Init 面板、侧栏实现语言；原版 PS 面板代码不迁移、只迁移契约。

### D-M1-003 [active]

- 键位 **Cmd 优先**（Cmd+Shift 系为主），Fn+F 仅作别名；无 Leader 层（继承 D-007）。
- 理由：macOS F 键默认被系统媒体键抢占，稳定依赖用户改系统设置=外部依赖不牢固；Cmd 组合被 WezTerm 完整拦截不下发终端，与任何 agent TUI 零冲突。
- 影响：KEYBINDINGS.md 键位契约；不绑任何 Ctrl+* 与裸字母键。

### D-M1-004 [active]

- Agent **平权接入所有**：注册表抽象 + 运行时探测；探测不到即从 UI 隐藏但保留条目；任一缺失不阻断其他（继承 D-005）。
- 理由：高不同公司 agent 兼容性的机制保障；接入新 agent = 加一条注册表记录。
- 影响：AGENT_REGISTRY.md 规范；Init AGENT 区、F6 选择器、缺省解析。

### D-M1-005 [active]

- 只蒸馏原版产品契约（身份模型、门禁、两步流、颜色标准、交接契约、工程防线），平台实现独立重写，不追求代码一致性。
- 来源：用户 2026-08-14 明确（"不是原项目的补充，而是额外启动的 macOS 版本开发"）。
- 影响：DESIGN.md 继承/重表达边界；代码评审标准。

### D-M1-006 [active]

- **Init 面板用 macOS 内置 zsh 实现静态屏**（三区 + 表格 + 行输入两步流），不用 WezTerm InputSelector 浮层。
- 理由：WezTerm Lua 无键盘事件捕获 API，无法做行输入循环；InputSelector 浮层与原版静态屏面板形态不一致（用户 2026-08-14 明确质疑）。zsh 是 macOS 系统内置运行时，与"零外部依赖"不冲突，且与原版"Windows 用内置 PowerShell 5.1"完全对称。
- 修正：D-M1-002 的"纯 Lua"限定为窗口/键位/状态/布局层；pane 内交互程序使用系统内置 shell。
- 影响：wezterm/init.sh（新）、init.lua 精简为面板入口；删除 Cmd+Shift+L / Cmd+Shift+N（新建内嵌面板 c 键）。

### D-M1-007 [active]

- **zsh 脚本禁用 `path` 作为变量名**（zsh 保留变量，与 PATH 标量双向同步；`local path=...` 或 `read -r ... path ...` 会直接覆盖 PATH，导致后续外部命令全部找不到）。统一改用 `ppath`。同族陷阱：顶层（函数外）禁止 `local`（read 行为异常回显赋值）；`print -r` 不解释 `\t`（文件数据写入用 `printf '%s\t%s\n'`）。
- 来源：2026-08-15 对抗性审查，explorer.sh 收藏写入触发 mktemp not found（PATH 被 local path 覆盖）。
- 影响：init.sh / explorer.sh / wzlib.zsh 全部变量命名规范；审查清单必查项。

### D-M1-008 [active]

- **agent 启动前播放 walking-cat splash 动画**（原版 Get-AgentSplashScript 契约蒸馏）：5 帧 × 75ms ≈ 300ms 固定窗口，猫猫随读条右移、脸/腿两姿态交替、读条 0%→100%、Magenta 装饰色（D-013 不用黄色）、重定向降级单帧、agent 首屏自动覆盖；无就绪轮询、无启动依赖。
- 实现：独立 wezterm/splash.sh，两条启动路径统一接入（wzlib.launch_agent 与 agents.lua splash_args）；静态 splash.txt 已删除；环境变量 WZ_SPLASH_FRAMES / WZ_SPLASH_MS 可慢放调试。
- zsh 陷阱（本决策附带）：`print` 默认吞转义（`\_`→`_` 猫头反斜杠丢失）必须 `print -r`；含反斜杠的 ASCII art 行用 `print -r "... /\_/\\${X}"`（`\\` 才产出字面反斜杠，`\${X}` 不会展开变量）。
- 来源：用户 2026-08-15 指出"猫猫 loading 动画不会正常播放"。
- 影响：splash.sh + splash_visual_check.py（11 项断言，已入 check.sh 防线）。

### D-M1-009 [active]

- **键位主键改为 Cmd+F 系**（Cmd+T / Cmd+F1 速查 / Cmd+F3 Init / Cmd+F4 关窗格 / Cmd+F6 三栏 / Cmd+F7 Explorer / Cmd+R 重载），F 键裸按（Fn+F1...）作别名；F2 留空。
- 根因：V1 的 Cmd+Shift+D/E/H/W 被 WezTerm 规范化为裸 Cmd+D/E/H/W（`show-keys --lua` 实测 `SHIFT|SUPER+字母 → 大写字母+SUPER`），抢走 Cmd+W 关标签、Cmd+H 隐藏应用等系统默认键，且裸按 Cmd+D/E 即误触发工作台动作。用户实测反馈"很多快捷键完全失效/混乱"正是此因。
- 依据：GUI 键事件日志（debug_key_events）实测 `Cmd+F3` 以 `SUPER+Function(3)` 送达 WezTerm；`Ctrl+F3` 被 macOS 系统层吞掉（Ctrl 系不可用）；合成 F3/F7/F1 键码均送达并正确触发（等价于媒体键模式下 Fn+F 的交付形态）。
- 另一实测根因：`help.toggle` 曾全窗口扫描速查 pane 后 `window:perform_action(action, other_pane)` 关闭——本 WezTerm 版本不按 pane 参数定向，作用于焦点 pane，导致 F1 误杀其他页签的会话。修复为当前页签作用域 + 先 activate 再关闭（2026-08-15，与 773b5e7 之后的键位修复同批）。
- 影响：keys.lua / help.lua / sidebar.lua（错误可见化）/ cheatsheet / KEYBINDINGS.md；check.sh 新增 effective-keymap 断言（show-keys 生效表必须含 F 键系 + Cmd+F 系，且 Cmd+W/H 保持默认）。

### 对抗性审查结论（2026-08-15）

- 修复：status.lua `agents.registry_order` 缺括号（每次 tab 重绘报错，修复前日志 192+ 条）；layouts.lua 三栏选择器在 agents.lua 重写后接口破坏（entry 表当 id）；sidebar 过期键位提示；agents.installed() 无缓存（500ms tick 高频读文件）。
- 补全：Explorer 重做为自绘静态屏（explorer.sh，四区 + 数字导航 + g/gd/b/w/p/f/r/a/q，对齐原版 Show-Listing）；Init 面板补 a 全量视图、d dash(grok)。
- 防线：explorer 视觉回归并入 check.sh；wzlib.zsh 公共库消除双份拷贝；注册表加载按 id 去重。
- 验证：当前 GUI 会话日志零错误；Init a 键、Explorer 数字导航/收藏/D-012、d 键 dash 全部 cli 层实测通过。
