# config/ai/

AI 工具配置的**真源**。跨工具共享的内容只在这里维护一份，由
`modules/ai-agent-config` 链接或渲染到各工具期望的位置。

不要直接编辑 `~/.claude/` 下被链接或生成的文件 —— 改这里。

## 内容

| 路径 | 说明 | 部署方式 |
|---|---|---|
| `agents/` | 18 个 council agent 定义 | 符号链接到 `~/.claude/agents` |
| `skills/council/` | `/council` 多角色审议 skill | 符号链接 |
| `skills/codebase-memory/` | 知识图谱工具的使用说明 skill | 符号链接（见下方"工具托管"） |
| `hooks/` | `cbm-*` 两个 hook 脚本 | 符号链接到 `~/.claude/hooks` |
| `mcp.json` | MCP server 清单真源 | 渲染成各工具的 MCP 配置 |
| `settings.json` | Claude Code 设置真源 | 渲染到 `~/.claude/settings.json` |

## 占位符

配置里不写绝对路径 —— 换机器或换用户名就失效，而且这是公开仓库。
渲染时替换：

| 占位符 | 展开为 |
|---|---|
| `{{HOME}}` | 用户主目录 |
| `{{DOTFILES}}` | 本仓库根目录 |
| `{{EXE}}` | Windows 上是 `.exe`，其余平台为空 |

## 工具托管的文件（会被上游覆写）

以下内容原本由 `codebase-memory-mcp` 自己安装，升级时它会重新写入
`~/.claude/`。我们把它们纳入仓库以便新机器开箱可用，代价是**工具升级后
仓库版本可能落后**：

- `skills/codebase-memory/SKILL.md`
- `hooks/cbm-code-discovery-gate`
- `hooks/cbm-session-reminder`
- `mcp.json` 里的 `codebase-memory-mcp` 条目

发现工具行为与仓库内容不一致时，以工具生成的版本为准，并把差异同步回这里。
`hooks/cbm-code-discovery-gate` 已相对上游做了一处修改：上游硬编码二进制的
绝对路径，我们改成运行时查找，否则这个文件只能在一台机器上用。

## 凭据

**这里不放任何明文凭据。** 需要 API key 的地方只写环境变量名
（如 `NVIDIA_API_KEY`、`CURSOR_API_KEY`），由运行时从密钥库解析。
`skills/council/` 已经是这个模式 —— 它读 `api_key_env` 指定的变量名，
从不内联值。

本仓库是公开的，任何明文凭据都会立即泄露。
