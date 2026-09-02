<p align="center">
<img src="logo.png" width=300/>
</p>

# dotfiles

跨 macOS / Linux / Windows 的开发环境配置。一条命令把新机器装成可用状态 ——
包括 zsh、Nerd Fonts、现代 CLI 工具链、AI 编码 CLI 与密钥管理。

平台自动识别，无需手工选择。

[![CI](https://github.com/m9rco/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/m9rco/dotfiles/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 安装

```sh
git clone https://github.com/m9rco/dotfiles.git ~/lab/dotfiles
cd ~/lab/dotfiles
```

**macOS / Linux / WSL：**

```sh
./bootstrap.sh --dry-run    # 先看会做什么，不改任何东西
./bootstrap.sh              # 装全部 core 模块
```

**Windows 原生（PowerShell）：**

```powershell
.\bootstrap.ps1 -DryRun     # 先看会做什么
.\bootstrap.ps1
```

Windows 上两种方式都可以：原生 PowerShell 走 `bootstrap.ps1`（scoop/winget
装工具、写用户注册表装字体），WSL 里走 `bootstrap.sh` 拿到完整的 zsh 环境。
两者互不干扰 —— WSL 内的字体模块会自动跳过并提示在宿主机安装。

先跑一次 `--dry-run` 是推荐做法：它列出将创建的符号链接与将安装的软件包，
但不写入任何文件。

## 常用命令

```sh
./bootstrap.sh --info            # 打印平台探测结果
./bootstrap.sh --list            # 列出全部模块及其是否适用于本机
./bootstrap.sh --help            # 用法（可用标签由磁盘上的模块动态生成）

./bootstrap.sh --only zsh,git    # 只装指定模块（依赖会被自动带上）
./bootstrap.sh --skip fonts      # 装除指定模块之外的全部
./bootstrap.sh --tag ai          # 只装带某标签的模块
```

模块清单不在本文档里硬编码 —— 用 `--list` 看当前实际有哪些。
它读的是 `modules/` 目录，所以永远是最新的。

## 装了什么

用 `./bootstrap.sh --list` 看完整清单。大致分组：

| 标签 | 内容 |
|---|---|
| `shell` | zsh + 分片配置、oh-my-zsh 与插件、starship prompt、补全缓存、惰性加载 |
| `fonts` | JetBrainsMono Nerd Font、Maple Mono NF（中英等宽） |
| `cli` | ripgrep、fd、bat、eza、fzf、zoxide、delta、jq、yq、gh、lazygit、starship、direnv、tmux |
| `git` | gitconfig、全局 gitignore、delta 集成 |
| `ai` | Claude Code / Codex CLI / Gemini CLI、MCP 与 agent/skill 配置 |
| `secrets` | 密钥库接入、gitleaks pre-commit 守卫 |

prompt 由 starship 渲染，配置是单一的 `config/starship.toml` —— zsh 与
PowerShell 共用同一份，所以三个平台的 prompt 长得一样。

可选项默认不装，需要时显式启用。两种写法等价：

```sh
DOT_WANT_ATUIN=1 ./bootstrap.sh --only modern-cli        # atuin 会接管 Ctrl-R
DOT_CLI_OPTIONAL="btop dust duf procs" ./bootstrap.sh --only modern-cli
DOT_WANT_OLLAMA=1 ./bootstrap.sh --only secrets          # 本地推理，体积大
```

可选的 CLI 工具：`htop` `btop`（进程/资源监控）、`dust` `duf`（磁盘占用）、
`procs`（ps 替代）、`tldr`（命令速查）、`hyperfine`（基准测试）、
`xh`（HTTP 客户端）、`sd`（sed 替代）、`atuin`（历史加强版）。
完整清单见 `config/cli/tools.txt`。

### 包源贫乏的发行版

RHEL / CentOS 的 base 仓库里没有多数现代 CLI 工具，所以在 `DOT_DISTRO=rhel`
上引导会先自动启用 **EPEL**（Fedora 项目维护的附加仓库，RHEL 生态的事实
标准）。启用后 ripgrep、fd、bat、zoxide、delta、direnv、duf 都能直装。

仍有几个工具（`eza` `lazygit` `gh` `yq`）在任何 RHEL 仓库里都没有。它们
装不上只告警、不影响退出码 —— shell 配置对缺失工具已做优雅降级。只有标为
`essential` 的工具（目前只有 `starship`，因为它是 prompt）失败才会让模块
失败，而 starship 有官方安装脚本兜底，拉的是预编译二进制。

两个开关：

```sh
DOT_NO_EPEL=1   ./bootstrap.sh    # 不动系统仓库（离线，或内部镜像已自带这些包）
DOT_NO_RUSTUP=1 ./bootstrap.sh    # 不为源码编译安装 Rust 工具链（约 600MB）
```

默认行为是缺 cargo 时装 rustup，因为那是 `eza` 这类工具在老发行版上的唯一
出路。代价是工具链约 600MB、且之后每个工具都要现场编译 —— 小机器上可能
几十分钟。不想付这个代价就设 `DOT_NO_RUSTUP=1`，装不上的工具会被明确列出。

## 目录结构

```
bootstrap.sh          Unix 入口（POSIX sh，可在 dash 下运行）
bootstrap.ps1         Windows 原生入口（PowerShell 5.1+）
lib/                  共享函数：日志、平台探测、幂等文件操作、包安装、模块运行器
platform/             平台适配层（macOS / Linux / Windows 的差异都收敛在这里）
config/               被链接到 $HOME 的配置文件（只有内容，没有安装逻辑）
modules/              安装模块，一个子目录一个，自动发现
bin/                  用户命令：dot-secret、dot-bench、dot-ai-upgrade
test/                 断言测试与 lint
legacy/               历史资产归档，不参与安装
```

两条关键约定：

- **配置与逻辑分离**：改一行配置只需动 `config/`，不碰任何脚本。
- **模块自动发现**：在 `modules/` 下新建一个合规目录即可，不需要修改
  `bootstrap.sh` 或任何中心清单。格式见 `modules/README.md`。

## 安全

这是一个**公开仓库**，所以：

- 凭据一律不入库。真源是系统密钥库（macOS keychain / libsecret /
  Windows 凭据管理器）、1Password CLI，或权限 600 且不入库的
  `~/.config/dotfiles/env.local`。
- git 身份（name/email）写进不入库的 `~/.gitconfig.local`。
- 安装 gitleaks 并配置 pre-commit 守卫，阻止凭据被提交；CI 另外扫描
  工作区与全部历史。

```sh
bin/dot-secret set ANTHROPIC_API_KEY   # 存入密钥库（输入不回显）
bin/dot-secret list                    # 列出可用来源与条目名（不显示值）
bin/dot-secret scan                    # 用 gitleaks 扫一遍仓库
```

在 shell 里按需注入（**启动时不会读取密钥**，避免拖慢启动与弹授权框）：

```sh
dot_secret_load ANTHROPIC_API_KEY
ai-keys                                # 一次注入常用的几个
```

## 安全性与幂等

- **改动前先备份**：任何将被替换的真实文件都先移到
  `~/.dotfiles-backup/<时间戳>/`，保留原本的相对路径。
- **幂等**：重复运行不产生变更、不新增备份、退出码为 0。
- **可预演**：`--dry-run` 只打印计划，零写入、零下载。

## 开发

```sh
sh test/run_all.sh                      # 跑全部断言测试
DOT_TEST_SHELL=dash sh test/run_all.sh  # 用 dash 验证 POSIX 兼容性
sh test/lint.sh                         # shellcheck + shfmt + 项目约定
sh test/lint.sh --fix                   # 顺手修好格式
sh test/lint_ps.sh                      # PowerShell 语法 + PSScriptAnalyzer
bin/dot-bench                           # 测量 zsh 启动耗时（预算 200ms）
```

CI 有 6 个 job 定义、展开成 10 次运行（`test` 与 `smoke` 带平台矩阵）：
静态检查、密钥扫描（工作区 + 全部历史）、macOS/Ubuntu × sh/dash 测试矩阵、
引导冒烟、Windows runner（PowerShell 5.1 与 7 都验证）、以及一个
`debian:stable-slim` 容器 job 做真实安装 —— 那个容器的 `/bin/sh`
是 dash 且几乎什么都没预装，能在那里跑通才说明引导没有隐式依赖。

## 从旧版本升级

旧版本是一个 1200 行的 `private/install.sh`，用法是 `install.sh <task>`。
新结构完全替换了它（旧脚本归档在 `legacy/private/install.sh`）。

升级步骤：

```sh
cd ~/lab/dotfiles && git pull
./bootstrap.sh --dry-run     # 看清将替换哪些 $HOME 下的文件
./bootstrap.sh
```

会被替换的文件（`~/.zshrc`、`~/.gitconfig` 等）**都会先移到
`~/.dotfiles-backup/<时间戳>/`**，可随时取回。旧的 `~/.gitconfig` 里如果
写着 git 身份，取回时能在备份里找到 —— 新结构把身份放在
`~/.gitconfig.local`（不入库）。

`git submodule` 不再使用：原先的 24 个 gitlink 已全部移除，
`git clone` 不需要 `--recurse-submodules`。详见 `legacy/README.md`，完整升级说明见 `docs/UPGRADING.md`。

## 纠错

发现问题欢迎提 [issue](https://github.com/m9rco/dotfiles/issues) 或
[pull request](https://github.com/m9rco/dotfiles/pulls)。

## License

MIT
