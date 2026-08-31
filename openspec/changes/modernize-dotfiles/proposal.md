## Why

当前 dotfiles 是一个 ~1200 行的单体 `private/install.sh`，只支持 macOS 与 Linux，任务清单硬编码在 `usage()` 里，且大量内容已经过时（Sublime Text 2/3、Alfred workflow、CLion/PyCharm 2018 设置、8 个 docker 子模块、11 个 vim 插件子模块、Travis CI）。它假定 `/usr/local/bin/brew`（Intel 路径）、taobao 镜像域名已失效，也完全没有 Windows 支持。

同时，日常开发的重心已经转向 AI 辅助编码：AI 编码 CLI、MCP server 配置、agent/skill 定义、以及以 Rust 系工具为主的现代命令行链条，这些在当前仓库里一个都没有。需要一次结构性重构，把 dotfiles 变成"换一台机器（mac / win / linux）跑一条命令就能进入 AI 开发状态"的基础设施。

## What Changes

- **BREAKING**: 单体 `private/install.sh` 不再是安装入口（随 `private/` 一起归档到 `legacy/private/install.sh`），改为 `bootstrap.sh`（Unix）/ `bootstrap.ps1`（Windows）双入口 + 模块化 `modules/<name>/install.sh`。旧的 `install.sh <task>` 调用方式不再可用。
- **BREAKING**: 移除仓库内**全部** git 子模块 —— `docker/*`（8 个）与 `private/vim/plugins/*`（11 个），并删除 `.gitmodules` 与 `.git/modules/` 下的残留。新仓库不再使用 git submodule 机制；vim 插件改由插件管理器在运行时拉取，docker 镜像定义留在各自的独立远端仓库。
- **BREAKING**: 目录结构重排 —— 整个 `private/` 目录**原样归档**为 `legacy/private/`（不逐文件拆分搬迁），新结构在顶层重建：`config/`（被 link 的配置文件）、`modules/`（安装逻辑）、`platform/`（平台适配层）、`lib/`（共享函数）、`legacy/`（归档）。新的 `config/` 内容是参照 `legacy/private/` 重写的，而非移动过来的。
- 新增自动平台识别：检测 OS（darwin/linux/windows）、架构（arm64/x86_64）、Linux 发行版与包管理器（brew/apt/dnf/pacman/winget/scoop）、以及是否运行在 WSL / SSH / 容器中，据此分派。
- 新增 Windows 双轨支持：宿主机走 PowerShell 7 + winget/scoop（Windows Terminal、字体、AI CLI、PowerShell profile），WSL 内复用 Linux 路径安装 zsh 环境。
- zsh 配置重写：修正 Homebrew 前缀检测（支持 Apple Silicon `/opt/homebrew`）、替换失效的 taobao 镜像、拆分为 `zshrc` + 按需加载的 `zshrc.d/*.zsh` 片段、启用 zsh 编译缓存以加快启动。
- 字体安装从 Adobe Source Code Pro 换为 Nerd Fonts（含 powerline/图标字形），三平台统一，避免 clone 整个字体仓库。
- 新增现代 CLI 工具链模块：ripgrep、fd、bat、eza、fzf、zoxide、delta、jq/yq、gh、lazygit、atuin、starship。
- 新增 AI 编码 CLI 模块：Claude Code、Codex CLI、Gemini CLI 的安装与版本检查。
- 新增 AI agent 配置托管：MCP server 清单与共享配置、agents/skills/commands 目录的跨工具符号链接管理。
- 新增密钥与本地模型模块：API key 走 keychain / 1Password / 不入库的 `.env.local`；可选安装 ollama 及本地模型工具。
- 所有安装操作要求幂等、支持 `--dry-run` 与 `--only <module>`，link 前自动备份已存在的真实文件。
- Travis CI 替换为 GitHub Actions：在 macOS / Ubuntu / Windows runner 上跑 shellcheck、shfmt、PSScriptAnalyzer 与 dry-run 冒烟测试。
- 历史资产整体归档到 `legacy/private/`（含 Sublime 2/3、Alfred workflow、JetBrains 设置、astyle、emacs、terminfo、旧 zshrc、以及旧 `install.sh` 本身），保留在库内可随时查阅，但不参与安装、不被模块发现。

## Capabilities

### New Capabilities

- `platform-detection`: 识别 OS、架构、Linux 发行版、包管理器、以及 WSL/SSH/容器/CI 等运行环境，向上层提供稳定的能力查询接口与平台分派规则。
- `bootstrap-installer`: 双入口引导程序与模块运行器 —— 模块发现与依赖排序、幂等执行、`--dry-run` / `--only` / `--list` 参数、link 前备份、统一日志与失败处理、退出码约定。
- `shell-environment`: zsh 配置（Unix）与 PowerShell profile（Windows）的内容与安装 —— 框架选择、插件集、prompt、history、PATH/环境变量、跨平台共享片段、启动性能预算。
- `font-provisioning`: Nerd Fonts 的选择、下载与三平台安装（`~/Library/Fonts`、`~/.local/share/fonts` + fc-cache、Windows 用户字体注册），含终端配置指向。
- `modern-cli-toolchain`: 现代 CLI 替代工具的安装清单与 shell 集成（别名、补全、fzf/zoxide/atuin 的 shell hook、delta 的 git 集成）。
- `ai-coding-clis`: AI 编码 CLI（Claude Code、Codex CLI、Gemini CLI）的安装、升级、版本校验与 PATH 接入。
- `ai-agent-config`: MCP server 清单与共享配置、agents/skills/commands 定义的托管与跨工具链接、以及配置的平台无关表示。
- `secrets-management`: API key 与敏感配置的存放策略（keychain / 1Password / 不入库的本地文件）、防误提交守卫、以及可选的本地推理工具（ollama）安装。
- `legacy-migration`: 旧结构到新结构的迁移规则 —— 全部子模块移除、整个 `private/` 原样归档到 `legacy/private/`、新 `config/` 为重写而非搬迁、CI 从 Travis 迁到 GitHub Actions、以及既有用户的升级路径。

### Modified Capabilities

（无。`openspec/specs/` 目前为空，本次全部为新建能力。）

## Impact

- **归档**: 整个 `private/` 原样 `git mv` 到 `legacy/private/`（含旧 `install.sh`）；`lib/utils.sh` 的旧副本删除，需要的函数在新 `lib/` 中重写。
- **删除**: `.travis.yml`；`.gitmodules` 整个文件删除；`docker/`、`private/vim/plugins/` 作为子模块彻底移除（不进 `legacy/`，内容在各自独立远端仓库）。
- **新建**: `config/` 下的配置文件参照 `legacy/private/` 重写（不是移动），`bootstrap.sh`、`bootstrap.ps1`、`lib/*.sh`、`platform/{macos,linux,windows}`、`modules/*/`、`.github/workflows/ci.yml`、包清单。
- **外部依赖**: Homebrew（mac/linux）、apt/dnf/pacman（linux）、winget + scoop（windows）、PowerShell 7、Nerd Fonts 发布包、npm（部分 AI CLI）。
- **对使用者的影响**: 需要重新执行新的 bootstrap；旧的 `~/.zshrc` 等符号链接指向会变化（安装时自动备份原文件）。
- **CI**: Travis 构建停止，改由 GitHub Actions 三平台矩阵验证。
- **风险**: 安装脚本会写入 `$HOME`；必须保证幂等与备份，`--dry-run` 是默认的验证手段。
