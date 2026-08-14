# Agent 注册表规范（平权接入所有）

## 目标

- 接入任何公司的 CLI agent = 加一条注册表记录，工作台逻辑零改动。
- 探测不到 → UI 隐藏但保留条目；任一缺失不阻断其他（继承 D-005）。
- 会话数据只走官方公开 CLI 接口，不解析私有存储。

## 注册表条目结构

每条记录一个 Lua 表，字段如下：

| 字段 | 说明 |
|---|---|
| id | 内部唯一 id（如 codex） |
| display | UI 显示名（如 Codex） |
| detect | 探测候选列表：全路径（io.open 存在性）或 PATH 环境名 |
| launch_mode | `flag`（CLI 自带 cwd 参数，如 -C/--cwd）或 `cwd`（依赖 spawn 进程 cwd） |
| launch_args | 新会话模板：`<exe>`、`<root>` 占位 |
| resume_last | 续最近会话模板 |
| resume_picker | 官方会话选择器模板 |
| session_root | 会话目录（仅 UI 提示，不解析） |
| notes | 平台/安装/验证说明 |

## 缺省解析（继承 D-005）

1. 显式指定（desk-roots 第三列 / 新建向导选择 / -Agent 参数）优先。
2. 无显式 → 按注册表顺序取第一个已探测到的 agent。
3. desk-roots 写出方一律显式写第三列。

## 内置条目（macOS 首版）

### 1. codex（首选）

- detect：`~/.local/bin/codex`、`/opt/homebrew/bin/codex`、`/usr/local/bin/codex`、`~/.codex/bin/codex`
- launch：flag 模式，`codex -C <root>`
- resume_last：`codex resume --last -C <root>`；resume_picker：`codex resume -C <root>`
- session_root：`~/.codex/sessions`（不解析）
- 状态：本机已验证 0.144.4 ✅

### 2. deepseek

- 社区版 `@kavienw/deepseek-cli`（npm 全局）
- detect：npm 全局 bin（`~/.npm-global/bin` 等）、PATH
- launch：cwd 模式（无 --cwd）；resume：`deepseek --continue` / `--resume`
- session_root：`~/.deepseek-cli/sessions/<sha256(cwd)[0:16]>.json`（不解析）
- 备注：npm shim 在 macOS 可直接 argv0 执行（无 Windows .cmd 垫片问题）

### 3. kimi

- launch：cwd 模式；resume：`kimi --continue`
- session_root：`~/.kimi-code/sessions`
- 状态：macOS 支持待验证（条目保留，探测不到自动隐藏）

### 4. grok

- launch：flag 模式，`grok --cwd <root>`；resume：Grok 自有
- 状态：macOS 支持待验证（条目保留）

## 运行期规则

- Init「AGENT 区」与 F6 选择器只显示探测到的 agent。
- 单一已装 agent → F6 自动跳过选择器直接三栏。
- 零 agent → Init 仍可用（建项目 + 纯 shell 逃生），Doctor 警告不阻断安装。
- 探测结果缓存 30 秒，避免每次渲染做文件 IO。

## 新增 agent 检查清单

1. 确认 macOS 安装落点与启动参数。
2. 判定 launch_mode（是否自带 cwd 参数）。
3. 确认官方 resume/continue 接口。
4. 注册表加一条 + 探测路径。
5. 冒烟三态：已装 / 未装 / 绑定第三列路由。
