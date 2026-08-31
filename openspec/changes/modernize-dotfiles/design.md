## Context

现有仓库是 2018-2019 年风格的 dotfiles：`private/install.sh` 单文件 1200+ 行，包含 ~50 个 `install_*` 函数与一个手写的 `usage()` 任务清单和 `case` 分派表。`lib/utils.sh` 是它的一份近似副本。平台判断只有 `is_mac` / `is_linux` 两个函数，Homebrew 前缀硬编码 `/usr/local/bin/brew`（Apple Silicon 失效），镜像地址指向已下线的 `npm.taobao.org`。仓库还携带 8 个 docker 子模块与 11 个 vim 插件子模块，clone 一次成本很高。CI 是 Travis。

目标状态：一个跨 mac / linux / windows 的模块化 dotfiles，自动识别平台，单条命令完成"新机器 → 可用的 AI 开发环境"。已确定的方向性决策（来自需求澄清）：自研 POSIX sh + PowerShell 方案（不引入 chezmoi / Nix / Makefile 抽象）；Windows 原生 + WSL 双轨；AI 部分四块全要（编码 CLI、MCP/agent 配置、现代 CLI 工具链、密钥与本地模型）；移除全部 git 子模块；整个旧 `private/` 原样归档到 `legacy/private/`，新配置参照它重写而非搬迁。

约束：
- 引导阶段不能依赖任何未安装的东西。`bootstrap.sh` 只能用 POSIX sh 与 coreutils；`bootstrap.ps1` 只能用 Windows 自带的 PowerShell 5.1 起步（之后可自行安装 PowerShell 7）。
- 脚本会写 `$HOME`，必须幂等且可预演。
- 中国大陆网络环境：包下载需要可切换镜像，且旧镜像地址已失效，不能再硬编码。

## Goals / Non-Goals

**Goals:**

- 单入口引导：`./bootstrap.sh`（mac/linux/WSL）与 `.\bootstrap.ps1`（windows 原生）自动识别平台并完成安装。
- 模块化：每个能力是 `modules/<name>/` 下的一个自描述目录，新增能力不需要改动引导程序或任何中心清单。
- 幂等 + 可预演：重复运行结果一致；`--dry-run` 打印将要执行的操作而不落盘。
- 配置与逻辑分离：`config/` 只放被链接的配置文件，`modules/` 只放安装逻辑，两者不混。
- 平台差异收敛在 `platform/` 一层，模块代码里不出现 `uname` 判断。
- zsh 启动时间预算 ≤ 200ms（`zsh -i -c exit` 实测）。
- CI 在三平台上验证脚本能跑通 dry-run 且通过静态检查。

**Non-Goals:**

- 不做 dotfiles 管理框架（不引入 chezmoi / yadm / Nix）；不做通用工具，只服务本人的机器。
- 不管理系统级配置（不改 `/etc`、不装系统包管理器本身、不做 macOS `defaults` 全量调优 —— 后者留作后续独立 change）。
- 不迁移 legacy 编辑器配置（Sublime / JetBrains / Alfred / emacs）到新结构，只归档。
- 不做密钥同步或密钥托管服务；只定义存放位置与读取方式。
- 不在 CI 里做真实安装（只做 dry-run + 静态检查），真实安装验证靠本地与一次性容器手测。

## Decisions

### D1. 目录结构

```
bootstrap.sh              # Unix 入口（POSIX sh）
bootstrap.ps1             # Windows 原生入口
lib/
  log.sh                  # msg/step/info/success/error/tip（沿用现有配色约定）
  detect.sh               # 平台探测，导出 DOT_OS / DOT_ARCH / DOT_DISTRO / DOT_PKG / DOT_WSL ...
  fs.sh                   # link/backup/mkdir 幂等原语
  pkg.sh                  # pkg_install 抽象，转发到 platform 层
  runner.sh               # 模块发现、排序、执行、dry-run
platform/
  macos.sh                # brew 安装/前缀检测、Brewfile、字体目录、defaults 钩子
  linux.sh                # 发行版探测、apt/dnf/pacman 适配、fc-cache
  windows.ps1             # winget/scoop、字体注册、PowerShell profile 路径
config/                   # 被 link 的配置文件（内容，不含逻辑）——参照 legacy/private/ 重写
  zsh/{zshrc,zshrc.d/*.zsh}
  powershell/profile.ps1
  git/{gitconfig,gitignore_global}
  ai/{mcp.json,agents/,skills/}
  starship.toml
  ...
modules/<name>/
  module.sh               # 声明元数据 + install() ；由 runner 加载
legacy/
  private/                # 整个旧 private/ 原样归档（含旧 install.sh），不参与安装
  README.md               # 归档说明
.github/workflows/ci.yml
```

**理由**：`config/` 与 `modules/` 分离，使"改一行配置"不再需要碰安装脚本 —— 这是当前 `install.sh` 最大的痛点（配置内容与 link 逻辑纠缠）。`platform/` 单独一层，让模块只调 `pkg_install ripgrep`，不关心是 brew 还是 apt。

`legacy/private/` 采取**整体原样归档**而非逐文件搬迁：旧 `private/` 里的内容质量参差（`private/zshrc/.zshrc` 里有硬编码的 `/Users/pushaowei/...` 路径、指向不存在的 `~/Applications/font_highlighting/`、以及 `go@1.8` 这类早已过期的 PATH），逐文件判断"搬哪些、改哪些"的成本高于直接参照着重写。整体归档让旧内容作为一份可查阅的参考留在库内，新 `config/` 从干净状态建立，两者不产生"半迁移"的混淆状态。

**替代方案**：把 `private/` 下仍有用的文件逐个 `git mv` 到 `config/` 再修改。否决：会让 `config/` 继承一批需要逐行审查的陈旧内容，且迁移过程中难以判断某文件是"已迁移待改"还是"已定稿"。

**替代方案**：按平台分顶层目录（`macos/`、`linux/`、`windows/`），各自完整一套。否决：三份配置会漂移，共享部分（zshrc、gitconfig、AI 配置）无处安放。

### D2. 模块自描述 + 目录发现，取代中心 case 分派

每个 `modules/<name>/module.sh` 定义元数据变量与一个 `install()` 函数：

```sh
MODULE_DESC="Nerd Fonts 安装"
MODULE_PLATFORMS="macos linux windows"   # 支持的平台
MODULE_REQUIRES="fonts-cache"            # 依赖的其他模块（可空）
MODULE_TAGS="core"                       # core | ai | optional
install() { ... }
```

runner 扫描 `modules/*/module.sh`，按 `MODULE_REQUIRES` 做拓扑排序，跳过 `MODULE_PLATFORMS` 不含当前平台的模块。

**理由**：现有 `install.sh` 每加一个任务要改三处（函数、`usage()` 文案、`case` 分支），必然漂移 —— 实测 `usage()` 列出的任务名与 `case` 分支已经不一致（如 `zsh_rc` vs `zsh_omz`）。目录发现让清单唯一来源是文件系统。

**替代方案**：YAML/TOML 清单 + 解析器。否决：POSIX sh 里解析 YAML 需要额外依赖（yq），而引导阶段不能有依赖。

### D3. 平台探测的输出契约

`lib/detect.sh` 导出（只读）：

| 变量 | 取值 |
|---|---|
| `DOT_OS` | `macos` \| `linux` \| `windows` |
| `DOT_ARCH` | `arm64` \| `x86_64` |
| `DOT_DISTRO` | `debian` \| `ubuntu` \| `fedora` \| `arch` \| `alpine` \| `unknown`（仅 linux） |
| `DOT_PKG` | `brew` \| `apt` \| `dnf` \| `pacman` \| `apk` \| `winget` \| `scoop` |
| `DOT_WSL` | `1` \| `0` |
| `DOT_HEADLESS` | `1`（SSH / 容器 / CI，跳过 GUI 应用与字体）\| `0` |
| `DOT_BREW_PREFIX` | `/opt/homebrew` \| `/usr/local` \| `/home/linuxbrew/.linuxbrew` |

Linux 发行版从 `/etc/os-release` 的 `ID` + `ID_LIKE` 读，不用 `lsb_release`（不一定装）。WSL 从 `/proc/sys/kernel/osrelease` 含 `microsoft` 判断。`DOT_HEADLESS` 由 `$SSH_CONNECTION` 非空、`$CI` 非空、或 `/.dockerenv` 存在推出。

**理由**：把所有环境判断集中成一组变量，模块内不再出现 `uname`。Homebrew 前缀必须探测而非硬编码 —— 这是当前脚本在 Apple Silicon 上直接失效的原因。

### D4. Windows 双轨：原生走 PowerShell，WSL 走 Unix 路径

- 宿主机 `bootstrap.ps1`：安装 PowerShell 7、Windows Terminal、Nerd Fonts（用户字体，无需管理员）、git、AI CLI、现代 CLI 工具（scoop 优先，winget 兜底）、link PowerShell profile。
- WSL 内直接跑 `bootstrap.sh`，`DOT_WSL=1`，跳过 GUI 类模块（字体交给宿主机装）与 macOS 专属模块。

包管理器策略：**scoop 优先、winget 兜底**。scoop 装 CLI 工具无需管理员、版本新、卸载干净；winget 用于 PowerShell 7、Windows Terminal 这类系统级应用。

**替代方案**：只用 winget。否决：winget 的 CLI 工具覆盖与更新滞后，且部分包需要提权。

### D5. zsh 配置架构

- 框架：保留 **oh-my-zsh**（已有配置资产、插件生态最全），但插件加载改为条件化片段，去掉当前 `zshrc` 里那一大段 `is_program_exists` 拼 `plugins=()` 的写法。
- prompt：换成 **starship**（跨 shell，PowerShell 侧可复用同一份 `starship.toml`），替代 `robbyrussell` / zim 的 `pure`。
- 拆分：`config/zsh/zshrc` 是薄入口，按序 source `config/zsh/zshrc.d/*.zsh`（`00-env.zsh`、`10-path.zsh`、`20-omz.zsh`、`30-tools.zsh`、`40-aliases.zsh`、`90-local.zsh`）。
- 本地覆盖：`~/.zshrc.local` 不入库，最后 source（沿用现有约定）。
- 性能：`compinit` 用带 `-C` 的缓存路径；`zcompile` 生成的 `.zwc`；重活（nvm、conda）改为 lazy 加载函数。
- **移除 zim 分支**：当前仓库同时维护 omz 与 zim 两套（`private/zsh/omz/` 与 `private/zsh/zim/`），实际只用一套，双份维护是纯负担。

**理由**：starship 让 mac/linux/windows 的 prompt 完全一致，是"三平台一套配置"目标里唯一能同时覆盖 zsh 与 PowerShell 的选择。

**替代方案**：zinit / zsh4humans 替代 omz。否决：迁移成本大于收益，omz 的启动开销在做完 lazy 加载与 compinit 缓存后可接受。

### D6. 字体：Nerd Fonts 发布包，不 clone 仓库

从 `ryanoasis/nerd-fonts` 的 GitHub Release 下载单个字体的 zip（如 `JetBrainsMono.zip`、`Maple` 系列），解压到平台字体目录。默认装 `JetBrainsMono Nerd Font`（终端）+ `Maple Mono NF`（中文等宽对齐）。

安装目录：macOS `~/Library/Fonts`；Linux `~/.local/share/fonts` 后 `fc-cache -f`；Windows 复制到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts` 并写用户注册表（免提权）。

**理由**：当前实现 `git clone` 整个 `adobe-fonts/source-code-pro`（含所有历史与格式）只为拿 TTF，慢且浪费。Nerd Fonts 提供图标字形，是 starship / eza / lazygit 正常显示的前提。

**替代方案**：`brew install --cask font-*`。否决：只解决 macOS，Linux/Windows 仍需另写，且 cask 字体名不稳定。

### D7. AI 配置的单一来源与跨工具链接

`config/ai/` 存平台无关的真源：

```
config/ai/
  mcp.json           # MCP server 清单（真源）
  agents/*.md        # agent 定义
  skills/*/          # skill 定义
  commands/*.md      # slash command
```

安装时按工具各自的期望位置建符号链接（如 `~/.claude/agents` → `config/ai/agents`）。MCP 配置各工具 schema 不同，用一个小的生成步骤从 `mcp.json` 渲染出各工具的配置文件，而不是维护多份。

**理由**：agents/skills 是纯 markdown，多工具可直接共享；只有 MCP 的 JSON schema 有差异，值得一个渲染步骤。

**风险**：各 AI CLI 的配置路径与 schema 仍在快速演进 —— 因此渲染逻辑集中在一个模块内，改起来只碰一处。

### D8. 密钥：仓库内零明文

- 真源在系统 keychain（macOS `security` / Linux `secret-tool` / Windows Credential Manager）或 1Password CLI（`op read`）。
- shell 启动时不同步读取密钥（会拖慢启动）；提供 `dotenv-load` 函数按需注入。
- `~/.config/dotfiles/env.local` 作为兜底，`.gitignore` 屏蔽，权限 `600`。
- 安装 `gitleaks` 作为 pre-commit 守卫，防止密钥误提交。

**理由**：dotfiles 是公开仓库（GitHub 上的 `m9rco/dotfiles`），任何明文密钥都会立即泄露。

### D9. 幂等与备份原语

`lib/fs.sh` 的 `dot_link SRC DST`：
1. `DST` 已是指向 `SRC` 的符号链接 → 跳过（幂等）。
2. `DST` 是真实文件/目录 → 移动到 `~/.dotfiles-backup/<timestamp>/` 后建链接。
3. `DST` 是指向别处的符号链接 → 直接替换（无内容可丢）。
4. `--dry-run` → 只打印将执行的动作。

**理由**：当前 `lnif()` 直接 `rm -rf "$2"`，会无声吞掉用户已有的真实配置文件 —— 这是最需要修掉的行为。

### D10. CI：GitHub Actions 三平台矩阵

- `ubuntu-latest` / `macos-latest`：shellcheck（`-s sh` 对 POSIX 脚本）、shfmt、`./bootstrap.sh --dry-run --list`。
- `windows-latest`：PSScriptAnalyzer、`.\bootstrap.ps1 -DryRun -List`。
- 额外一个 `container: debian:stable-slim` job 做最小环境真实安装（验证不隐式依赖 brew/coreutils GNU 扩展）。

## Risks / Trade-offs

- **[大爆炸式重构，中途不可用]** → 分阶段落地：先建新骨架（lib/platform/runner）并与旧 `install.sh` 并存，逐模块迁移，全部模块通过 dry-run + 手测后再删旧脚本。任何单个 commit 后仓库都可用。
- **[脚本写 `$HOME`，可能损坏现有配置]** → D9 的备份原语是硬要求：所有写操作必经 `lib/fs.sh`；`--dry-run` 作为默认验证手段；CI 在容器里跑真实安装。
- **[POSIX sh 可移植性陷阱]**（`local`、`[[ ]]`、`echo -e` 在 dash 下行为不同）→ shellcheck `-s sh` 在 CI 强制；`debian:stable-slim` job 用 dash 作 `/bin/sh` 实测。
- **[Windows 侧无法充分测试]**（无 Windows 物理机时只靠 CI）→ Windows 模块保持薄，逻辑尽量放进声明式包清单；PSScriptAnalyzer + `-DryRun` 在 CI 上门槛；宿主机模块与 WSL 模块解耦，WSL 路径先可用。
- **[AI CLI 与 MCP 配置格式快速变动]** → 渲染逻辑集中在 `modules/ai-agent-config` 一处；版本检查失败只警告不中断安装。
- **[彻底移除全部子模块是破坏性操作]** → 移除前逐个确认远端存在：`.gitmodules` 里 8 个 docker 子模块都指向独立的 `m9rco/*` 仓库，内容不会随本次删除丢失；11 个 vim 插件子模块都是上游第三方仓库，改由插件管理器按需拉取。移除方式为完整三步（`git submodule deinit` → `git rm` → 清理 `.git/modules/<path>`），不留半残留状态；`.gitmodules` 整个文件删除，新仓库不再引入 submodule 机制。
- **[starship 替换 omz 主题会改变视觉与 prompt 行为]** → `starship.toml` 入库并可回退；保留一个 `ZSH_THEME` 兜底分支，starship 未安装时不至于无 prompt。
- **[zsh 启动 ≤200ms 预算可能与 omz 插件集冲突]** → 若超预算，先砍插件与改 lazy 加载，而不是放宽预算；CI 不做性能门禁（runner 抖动大），改为提供 `bin/dot-bench` 本地测量。

## Migration Plan

1. **建骨架**：新增 `lib/`、`platform/`、`bootstrap.sh`、`bootstrap.ps1`、空 `modules/`。旧 `private/install.sh` 保持原位可用。
2. **迁核心模块**：zsh、fonts、git、modern-cli。`config/` 下的配置参照 `private/` 重写（不移动），每迁一个就 dry-run + 本机实测。
3. **加 AI 模块**：ai-coding-clis、ai-agent-config、secrets。
4. **归档与清理子模块**：对全部 19 个子模块执行 `git submodule deinit -f` → `git rm -f` → `rm -rf .git/modules/<path>`，删除 `.gitmodules`；删 `.travis.yml`、加 `.github/workflows/ci.yml`。
5. **归档 private**：`git mv private legacy/private`（整个目录原样搬入，含旧 `install.sh`），删除 `lib/utils.sh` 旧副本，写 `legacy/README.md`，重写 `README.md`。这一步在新引导已能覆盖等价功能之后执行。

回退：每阶段独立 commit；`legacy/private/` 完整保留旧 `private/` 的全部内容（含旧 `install.sh`），随时可查阅或取回；`~/.dotfiles-backup/<timestamp>/` 保留被替换的原始文件，可手工恢复。

## Open Questions

- 现代 CLI 工具链的具体成员是否需要收敛？（当前列了 12 个，其中 atuin 会改变 history 行为、需要确认是否想要）
- `config/ai/` 的 agents/skills 真源与已存在的 `~/.claude/` 现有内容如何合并 —— 是把现有内容搬进仓库，还是从空开始？
- macOS `defaults` 系统偏好设置是否要纳入本次 change，还是留作独立 change？（design 里暂列为 Non-Goal）
- 是否需要支持"多机器差异化"（工作机 vs 个人机装不同模块）？当前设计只有 `MODULE_TAGS` 粗粒度分组。
