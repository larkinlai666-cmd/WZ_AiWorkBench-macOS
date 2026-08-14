# WZ_AiWorkBench-macOS

**AI STAR CUBE（WZ-AiWorkBench）macOS 独立版** —— 以 WezTerm 为壳、任意 Agent CLI 平权接入的个人 AI 终端工作台。

> 本仓库是**独立开发项目**，不是 [WZ_AiStarCube](https://github.com/larkinlai666-cmd/WZ_AiStarCube) 的移植或补充：只蒸馏其产品设计理念，独立实现 macOS 版代码。

## 设计基准

- 蒸馏来源：[WZ_AiStarCube](https://github.com/larkinlai666-cmd/WZ_AiStarCube) 最新提交 `bf1f6ef`（2026-08-14）
- 蒸馏内容：任务身份模型、门禁 R1–R6、agent 平权（D-004/D-005）、Init 两步流（D-009/D-010）、颜色标准（D-013）、交接契约 `.wz-handoff.md`、工程防线
- 不追求：与原版代码高一致性

## 核心要求（用户定义）

轻便、稳定、牢固、高不同公司 agent 兼容性。

## 技术选型

| 维度 | 选择 | 理由 |
|---|---|---|
| 宿主 | WezTerm（macOS） | 继承原版形态 |
| 实现语言 | 纯 Lua（零外部运行时） | 轻便、单运行时 |
| Agent | 注册表平权接入（探测降级） | 高公司兼容性 |
| 键位 | Cmd 优先 + Fn+F 别名 | macOS 原生、稳定 |
| 会话数据 | 只走各 agent 官方 resume 接口 | 牢固（不依赖私有格式） |

## 文档索引

- [DECISIONS.md](docs/DECISIONS.md) — 权威决策
- [DESIGN.md](docs/DESIGN.md) — 设计理念蒸馏（继承/重表达）
- [KEYBINDINGS.md](docs/KEYBINDINGS.md) — 键位契约
- [AGENT_REGISTRY.md](docs/AGENT_REGISTRY.md) — Agent 注册表规范
- [ACCEPTANCE.md](docs/ACCEPTANCE.md) — 验收清单与里程碑

## 当前状态

M1 设计契约包（进行中）。代码实现自 M2 开始。
