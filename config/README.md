# config/

被链接到 `$HOME` 的配置文件。**只放内容，不放安装逻辑** —— 安装逻辑在 `modules/`。

这样"改一行配置"就不需要碰任何脚本，这是旧 `private/install.sh` 最大的痛点（配置内容与 link 逻辑纠缠在同一个 1200 行文件里）。

| 目录 | 内容 |
|---|---|
| `zsh/` | `zshrc` 薄入口 + `zshrc.d/*.zsh` 有序片段 |
| `powershell/` | Windows 侧 profile |
| `git/` | `gitconfig`、全局 gitignore |
| `ai/` | MCP 清单、agents / skills / commands 定义（跨 AI 工具共享的真源） |
| `starship.toml` | prompt 配置，zsh 与 PowerShell 共用同一份 |

## 约定

- **这里的内容是参照 `legacy/private/` 重写的，不是搬迁过来的。** 旧配置留在归档里可查阅，但不要把其中的机器专属残留带进来。
- 不得出现硬编码的他人主目录绝对路径（CI 会检查）。
- 不得出现已下线的镜像域名，如 `npm.taobao.org` 系列（CI 会检查）。
- 不要 source 不存在的文件 —— 全新环境启动 shell 必须零错误输出。
- 本机专属配置走不入库的本地覆盖文件（`~/.zshrc.local`），不要写进这里。
