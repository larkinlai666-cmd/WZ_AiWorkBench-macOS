# 设计理念蒸馏（继承 / 重表达）

来源：WZ_AiStarCube @ `bf1f6ef`（2026-08-14）。原则：契约继承、实现独立。

## 一、继承清单（产品契约，跨平台不变）

1. **任务 ≠ 会话**：任务身份 = 项目名 + 冻结路径（desk-roots 三列 + `.wz-project`）；agent 会话只是任务的运行时实例。
2. **门禁 R1–R6**：弱路径（home/Desktop/Documents 根/Downloads/Temp 等）永不当任务根；绑定接口拒绝弱路径与保留名；项目名走路径反向查找。
3. **页签级任务根 + tabs-first**：每标签独立 DESK；选项目开新页签、不藏旧页签；`prefer_to_spawn_tabs`。
4. **Init 中枢两步流**：静态屏 + 行输入；`wz>` 任务号 → `agent>` 模型号；两位数组合直启；默认视图 9 行封顶；键入零重绘（ConPTY 闪烁教训）。
5. **短命 Init 页签**：启动成功即自关（D-012）；存活期标题恒显 Init。
6. **Agent 平权**：注册表 + 缺省解析（显式 > 安装序首装）；任一缺失不阻断。
7. **颜色标准（D-013）**：亮黄 = 全局唯一可输入色并预留；信息 Cyan/White、成功 Green、错误 Red、装饰 Magenta；框线/表头禁黄。
8. **交接契约 `.wz-handoff.md`**：跨模型走文件态，transcript 显式排除；同模型走官方 resume。
9. **键位纪律**：窗口聚焦生效；不抢 agent 字母键；未绑定键原样穿透。
10. **工程防线**：load guard（加载期零副作用）、lua 配平、镜像 md5、管道冒烟、加固审查方法论。

## 二、重表达清单（平台实现，macOS 重写）

| 原版 | macOS 版 |
|---|---|
| Windows 盘符/反斜杠、大小写不敏感 | POSIX `/`、大小写敏感；弱路径表换 macOS 版（home/Desktop/Documents/Downloads/~/Library） |
| powershell.exe / cmd.exe | zsh + spawn 进程 cwd；无 Windows 进程依赖 |
| bootstrap.ps1 / sidebar.ps1（PS TUI） | 纯 Lua 面板（首版 InputSelector 两步流，静态屏自绘为演进项） |
| F 键优先（F1/F3–F7） | Cmd+Shift 系为主 + Fn+F 别名（KEYBINDINGS.md） |
| explorer.exe / wezterm.exe 探测 | `open` 命令打开文件；launcher 扩展结构性不生成链接 |
| Grok 私有会话格式解析 | 只走各 agent 官方 resume 接口，不解析私有存储 |
| Consolas/Segoe UI/YaHei/Acrylic | Menlo / JetBrains Mono；macOS 原生模糊（可选） |
| Install-WZ.ps1（Windows） | macOS 安装脚本：备份/部署/诊断/回滚 + Doctor（≥1 agent 通过） |

## 三、模块映射

| 原版模块 | macOS 版 | 方式 |
|---|---|---|
| wezterm.lua | wezterm/wezterm.lua | 重写（Lua，load guard 结构继承） |
| workbench/options.lua | wezterm/options.lua | 高继承（视觉语言、D-013 配色） |
| workbench/status.lua | wezterm/status.lua | 概念继承（品牌/路径/标签三信息类），路径 POSIX 化 |
| workbench/desk.lua | wezterm/desk.lua | 概念继承、实现重写（POSIX 路径、per-tab DESK、三列 desk-roots） |
| workbench/launch.lua | wezterm/agents.lua | 注册表化（AGENT_REGISTRY.md） |
| workbench/keys.lua | wezterm/keys.lua | 键位契约重写（KEYBINDINGS.md） |
| workbench/layouts.lua | wezterm/layouts.lua | 高继承（三栏/门禁顺序），agent 平权选择器 |
| workbench/projects.lua | wezterm/projects.lua | 概念继承（选择器/收藏） |
| workbench/bootstrap.ps1 | wezterm/init.sh（zsh 静态屏） | 契约全继承（三区/表格/行输入/两步流/D-013），实现用 macOS 内置 zsh（对称原版 Windows 内置 PowerShell）；不用 InputSelector 浮层 |
| workbench/sidebar.ps1 | wezterm/sidebar.lua | 契约继承（同根、单击打开），实现纯 Lua（InputSelector 仅作浏览导航面，非 Init 面板） |
| workbench/help.lua | wezterm/help.lua | 高继承 |
| workbench/hyperlinks.lua | wezterm/hyperlinks.lua | 高继承（POSIX 路径规则） |

## 四、不可回归红线

- 配置加载期零副作用（禁止 run_child_process / 重 IO）。
- 单模块失败不拖垮整份配置（soft-require）。
- 键位永不在 agent TUI 侧产生冲突（Cmd 层消化）。
- 不解析任何 agent 的私有会话存储。
