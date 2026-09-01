## 1. 骨架：共享库与平台探测

- [x] 1.1 创建目录骨架 `lib/`、`platform/`、`config/`、`modules/`、`legacy/`（各含占位 README），旧 `private/install.sh` 保持原位可用
- [x] 1.2 实现 `lib/log.sh`：step/info/success/error/tip 五个函数，非 TTY 时自动禁用 ANSI 颜色
- [x] 1.3 实现 `lib/detect.sh` 的 OS 与架构探测：导出 `DOT_OS`、`DOT_ARCH`，含 `aarch64→arm64`/`amd64→x86_64` 归一化，不支持的 OS 以退出码 1 终止
- [x] 1.4 实现 Linux 发行版探测：从 `/etc/os-release` 的 `ID` + `ID_LIKE` 导出 `DOT_DISTRO`，不使用 `lsb_release`，缺失时回退 `unknown` 并告警
- [x] 1.5 实现 `DOT_BREW_PREFIX` 探测：优先 `brew --prefix`，回退依次探测 `/opt/homebrew`、`/usr/local`、`/home/linuxbrew/.linuxbrew`，未安装时为空
- [x] 1.6 实现 `DOT_PKG` 探测：mac 选 brew（缺失则安装 Homebrew）、Linux 按发行版选 apt/dnf/pacman/apk、均不可用时退出码 1
- [x] 1.7 实现 `DOT_WSL` 与 `DOT_HEADLESS` 探测：WSL 从 `/proc/sys/kernel/osrelease` 含 `microsoft` 判断；headless 由 `$SSH_CONNECTION`/`$CI`/`/.dockerenv` 任一成立推出
- [x] 1.8 实现 `lib/fs.sh` 的 `dot_link SRC DST`：四种情形（已正确链接跳过 / 真实文件先备份到 `~/.dotfiles-backup/<timestamp>/` 保留相对路径 / 指向他处的链接直接替换 / 父目录不存在则创建），全部尊重 dry-run
- [x] 1.9 实现 `lib/pkg.sh` 的 `pkg_install` 抽象，按 `DOT_PKG` 转发到 `platform/` 层，并支持回退安装方式（发布二进制 / cargo / npm）
- [x] 1.10 编写 `platform/macos.sh`、`platform/linux.sh` 骨架：包名映射表、字体目录、缓存刷新钩子
- [x] 1.11 为 `lib/detect.sh` 编写可在容器中运行的探测断言脚本（伪造 `/etc/os-release`、`/proc/version` 验证各分支）

## 2. 骨架：模块运行器与引导入口

- [x] 2.1 实现 `lib/runner.sh` 的模块发现：扫描 `modules/*/module.sh`，校验 `MODULE_DESC`/`MODULE_PLATFORMS`/`MODULE_TAGS` 与 `install()` 存在，缺失则报错终止
- [x] 2.2 实现依赖拓扑排序：按 `MODULE_REQUIRES` 排序，检测循环依赖与未知依赖名并报错终止
- [x] 2.3 实现平台与环境过滤：跳过 `MODULE_PLATFORMS` 不含 `DOT_OS` 的模块、headless 下跳过需图形环境的模块，每次跳过都输出原因
- [x] 2.4 实现 dry-run 传导机制：runner 设置全局预演标志，所有写操作原语在该标志下只打印计划
- [x] 2.5 实现失败处理：单模块失败继续其余、依赖失败则跳过下游并标记 `skipped (dependency failed)`、结束输出成功/失败/跳过汇总、有失败则非零退出
- [x] 2.6 编写 `bootstrap.sh`（POSIX sh）：参数解析 `--dry-run`/`--only`/`--skip`/`--tag`/`--list`/`--info`/`--help`，未知模块名报错终止
- [x] 2.7 实现 `--info` 打印全部 `DOT_*` 探测结果且零副作用；实现 `--list` 输出模块名/描述/平台/标签/是否适用且零副作用
- [x] 2.8 实现 `--help` 的模块相关部分由模块发现动态生成，不含硬编码模块名清单
- [x] 2.9 用 shellcheck `-s sh` 与 shfmt 校验 `bootstrap.sh` 与 `lib/*.sh`（`test/lint.sh` 全绿），并在本机 dash 下跑通全部测试；Debian 容器验证本机无 docker，移交 CI 任务 11.4
- [x] 2.10 编写一个最小示例模块，验证"新建目录即被发现、无需改引导程序"，并验证幂等（连续两次执行无变更、无新增备份）

## 3. zsh 与 shell 环境

> 本组的 `config/zsh/*` 全部是参照旧 `private/zsh/`、`private/zshrc/` **重写**，不是搬迁；旧文件留在原位直到第 10 组统一归档。

- [x] 3.1 编写 `config/zsh/zshrc` 薄入口：按字典序 source `zshrc.d/*.zsh`，单个片段失败不阻断启动，最后 source `~/.zshrc.local`
- [x] 3.2 编写 `config/zsh/zshrc.d/00-env.zsh`：语言环境、EDITOR、以及集中的镜像配置（清除全部 `npm.taobao.org` 系列失效域名）
- [x] 3.3 编写 `10-path.zsh`：用探测到的 brew 前缀执行 `brew shellenv`（覆盖 Apple Silicon / Intel / Linuxbrew），brew 缺失时静默跳过
- [x] 3.4 编写 `20-omz.zsh`：oh-my-zsh 加载 + 条件化插件集（按命令存在性决定），缺失工具不产生错误输出
- [x] 3.5 编写 `30-tools.zsh`：fzf / zoxide / atuin 的 shell hook，仅在对应可执行文件存在时初始化
- [x] 3.6 编写 `40-aliases.zsh`：eza/bat 等别名，仅在工具存在时定义，且仅在交互式 shell 中生效（不影响脚本中的原命令）
- [x] 3.7 编写历史记录配置：明确 HISTFILE、条目数 ≥10000、追加写入、忽略连续重复、时间戳、跨会话共享
- [x] 3.8 编写 `config/starship.toml`，并在 zsh 中接入 starship；starship 缺失时回退到内置 prompt 且无错误
- [x] 3.9 实现 `compinit` 缓存与配置文件 `zcompile`，并保证配置变更后缓存自动失效重建
- [x] 3.10 把 nvm 等高开销初始化改为惰性加载函数（启动时不初始化，首次调用 `node`/`npm` 时触发）
- [x] 3.11 编写 `modules/zsh/module.sh`：安装 zsh、link zshrc、非 headless 且用户确认时设默认 shell（已是 zsh 则跳过、headless 不改）
- [x] 3.12 编写 `bin/dot-bench` 测量 `zsh -i -c exit` 耗时，实测并调优至 ≤200ms（实测中位数 153ms；冷启动 ~906ms 建补全缓存，单独报告不计入预算）
- [x] 3.13 确认新 `config/` 下不存在 zim 相关配置（旧 `zimrc` 随 `private/` 归档，不重写到新结构）

## 4. 字体

- [x] 4.1 编写声明式字体清单（默认含 JetBrainsMono Nerd Font 与 Maple Mono NF），新增字体只需加条目
- [x] 4.2 实现 Nerd Fonts 发布包下载与解压安装，不 clone 任何字体源码仓库；解压前校验归档有效性，损坏则报失败且不写入字体目录
- [x] 4.3 实现三平台用户级字体目录安装（mac `~/Library/Fonts`、Linux `~/.local/share/fonts` 自动建目录、Windows 用户字体 + 用户注册表），全程免提权
- [x] 4.4 实现 Linux `fc-cache -f` 刷新；`fc-cache` 缺失时输出手动刷新提示且模块仍成功
- [x] 4.5 实现字体幂等判定（目标字体文件已存在则不下载不复制）与 dry-run（只打印清单与目标目录、零网络请求）
- [x] 4.6 实现 headless 与 WSL 下跳过字体安装，WSL 提示说明应在 Windows 宿主机安装
- [x] 4.7 实现单字体失败不阻断其余、全部失败则模块失败并在汇总中标记
- [x] 4.8 实现受管终端配置的字体项自动指向已安装 Nerd Font；不可自动配置时输出手动设置指引

## 5. 现代 CLI 工具链

- [x] 5.1 编写跨平台逻辑名清单：ripgrep、fd、bat、eza、fzf、zoxide、delta、jq、yq、gh、lazygit、starship 为默认集；atuin 标记为可选不默认安装
- [x] 5.2 在 `platform/` 层补全各工具的平台包名映射，并标注平台限定工具的适用平台
- [x] 5.3 实现包管理器不可用时的回退安装链，并输出实际使用的安装方式；单工具全部方式失败只记录不中断
- [x] 5.4 实现工具幂等判定（`PATH` 中可执行则跳过）与 dry-run（打印工具及计划安装方式、零安装）
- [x] 5.5 编写 `config/git/gitconfig`：`delta` 可用时作为 diff/pager，缺失时回退默认 pager 且无错误
- [x] 5.6 编写 `modules/modern-cli/module.sh` 与 `modules/git/module.sh`，接入 shell 集成片段
- [x] 5.7 实现 atuin 的显式启用路径（默认不装、显式选择时安装并完成 shell 集成）
- [x] 5.8 验证三平台别名语义一致（同名别名执行语义等价操作）

## 6. AI 编码 CLI

- [x] 6.1 编写 AI CLI 声明式清单（Claude Code、Codex CLI、Gemini CLI），每条声明安装方式与适用平台
- [x] 6.2 实现安装逻辑与子集筛选（可只安装指定 CLI），新增条目无需改逻辑
- [x] 6.3 实现 npm 全局安装路径：确保 npm 全局 bin 进入 `PATH`、不使用 sudo、npm 缺失时报告原因并继续其余
- [x] 6.4 实现幂等（已安装则跳过并输出当前版本）与独立的显式升级路径（默认引导不自动升级）
- [x] 6.5 实现非阻断版本检查：输出版本号，查询失败仅告警不使模块失败
- [x] 6.6 确认安装流程不索取 API key / 不触发登录，并在完成后输出后续认证指引
- [x] 6.7 实现 dry-run（打印待装 CLI 与计划安装方式、零安装零下载）
- [ ] 6.8 验证 WSL 内的安装独立于 Windows 宿主机安装（需要真实 WSL，随第 9 组一起验证）

## 7. AI agent 与 MCP 配置

- [x] 7.1 建立 `config/ai/` 真源结构：`mcp.json`、`agents/`、`skills/`、`commands/`，确认无重复平行副本
- [x] 7.2 把现有 `~/.claude/` 内容搬入仓库真源：18 个 council agent、council 与 codebase-memory 两个 skill、cbm-* 两个 hook、settings.json；commands 为空（无自定义 command）
- [x] 7.3 实现 agents/skills/commands 到各 AI 工具目录的符号链接，复用 `dot_link` 备份原语（已有真实目录先备份）
- [x] 7.4 实现 `mcp.json` 校验：合法 JSON + 必需字段，失败时报告具体位置/缺失字段且不写出任何工具配置
- [x] 7.5 实现从 `mcp.json` 到各工具 MCP 配置的渲染，渲染逻辑集中在本模块一处，且相同输入产生完全一致的输出
- [x] 7.6 实现路径占位符机制：`config/ai/` 中不出现硬编码用户主目录绝对路径，渲染时解析为当前平台实际路径
- [x] 7.7 实现渲染时保留工具配置中不受仓库管理的用户本地设置
- [x] 7.8 实现工具未安装时跳过其配置步骤并说明原因，模块仍以成功状态结束
- [x] 7.9 实现幂等（已链接且渲染内容未变则零文件变更）与 dry-run（只打印将建链接与将渲染的目标路径）
- [x] 7.10 在三平台各渲染一次同一份 `mcp.json`，验证各自得到路径正确的可用配置

## 8. 密钥与本地模型

- [x] 8.1 实现跨平台密钥读取统一接口，按平台转发到 keychain / secret 服务 / 凭据管理器；密钥不存在时返回非零并明确报错，不以空值冒充成功
- [x] 8.2 实现 1Password CLI 作为可选来源：已登录则读取、未登录输出提示且有限时间返回不挂起、未安装则回退并说明所用来源
- [x] 8.3 实现 `~/.config/dotfiles/env.local` 兜底：以 `600` 权限创建、加入 `.gitignore`、不链接进仓库
- [x] 8.4 实现按需注入的凭据函数，并验证 shell 启动过程零密钥库调用、零认证弹窗
- [x] 8.5 实现凭据值不出现在任何日志/错误/dry-run 输出中（只出现名称与来源，读取失败的错误也不含部分内容）
- [x] 8.6 安装 `gitleaks` 并配置本仓库 pre-commit 守卫：含疑似凭据则阻止提交并指明文件位置，正常提交不受影响，gitleaks 缺失时提示守卫未生效
- [x] 8.7 实现 ollama 可选安装：默认不装、显式选择时安装、且不自动下载任何模型权重并输出按需拉取说明
- [x] 8.8 对整仓执行密钥扫描，确认零明文凭据、且需凭据的配置只含来源引用

## 9. Windows 原生支持

- [x] 9.1 编写 `bootstrap.ps1`：能在 PowerShell 5.1 下启动，参数 `-DryRun`/`-Only`/`-Skip`/`-Tag`/`-List`/`-Info`/`-Help`，行为与 Unix 侧对齐
- [x] 9.2 编写 `platform/windows.ps1`：scoop 优先 / winget 兜底的包安装抽象、字体目录与用户注册表写入、PowerShell profile 路径解析
- [x] 9.3 实现 Windows 侧 `DOT_*` 探测输出与 `-Info` 打印（零副作用）
- [x] 9.4 实现 Windows 侧的链接与备份原语，语义与 `dot_link` 一致
- [x] 9.5 通过 winget 安装 PowerShell 7 与 Windows Terminal；通过 scoop 安装现代 CLI 工具
- [x] 9.6 编写 `config/powershell/profile.ps1`：starship prompt（复用同一份 `starship.toml`）、现代 CLI 别名、PSReadLine 前缀历史搜索、以及不入库的本地覆盖 profile
- [x] 9.7 实现 Windows 字体安装（复制到用户字体位置 + 写用户注册表，免提权）
- [x] 9.8 Windows 侧 AI CLI 走同一份 config/ai/clis.txt 与 scoop/winget 抽象；CI windows job 实测 -DryRun 规划出 12 个工具、PowerShell 5.1 与 7 都能跑
- [x] 9.9 用 PSScriptAnalyzer 检查全部 `.ps1`，并执行 `-DryRun` 与 `-List` 冒烟
- [ ] 9.10 在 WSL 中执行 `bootstrap.sh` 验证双轨（需真实 WSL 环境）

## 10. 迁移与清理

- [x] 10.1 逐个确认 8 个 docker 子模块的内容都存在于对应的 `m9rco/*` 独立远端仓库（`test/verify_submodule_remotes.sh`，8/8 远端可达），确认结果写入 `notes/submodule-removal.md`
- [x] 10.2 移除全部 24 个 gitlink（实测数目非 19）：8 个已声明的走 `git submodule deinit -f` → `git rm -f`；16 个孤立 gitlink（无 `.gitmodules` 条目，deinit 无法处理）走 `git rm --cached`；最后清理 `.git/modules/`
- [x] 10.3 删除 `.gitmodules`，并验证 `git submodule status` 输出为空、`.git/modules/` 无残留、`git clone --recurse-submodules` 不拉取任何子模块
- [x] 10.4 实测旧 `vimrc.plugins` 本就是 vim-plug 声明式清单，11 个 gitlink 是冗余残留（从未初始化、无 URL 记录），移除即可；vim 不在本次范围，说明见 `notes/vim-plugins.md`
- [x] 10.5 执行 `git mv private legacy/private`，把整个旧 `private/` 原样搬入归档（含旧 `install.sh`），确认内容与迁移前逐字节一致
- [x] 10.6 删除 `lib/utils.sh` 旧副本（所需函数已在新 `lib/` 中重写）
- [x] 10.7 编写 `legacy/README.md`：归档原因、`legacy/private/` 内容清单与各资产状态，并验证 `--list` 不包含任何来自 `legacy/` 的模块
- [x] 10.8 审查 `config/` 是重写产物而非搬迁产物：无硬编码他人主目录路径、无 source 不存在文件的语句、无过期版本化 PATH 条目；并在全新环境启动 shell 确认零错误输出
- [x] 10.9 归档前已完成第 1-8 组并实机验证（zsh/字体/CLI/git/AI/密钥均已真实安装并幂等），归档后 lint 与 311 条断言仍全绿
- [x] 10.10 完成目录重排收尾：顶层 `private/` 不存在而 `legacy/private/` 存在，`config/` 只含配置文件、`modules/` 只含安装逻辑
- [x] 10.11 分 15 个 commit 推送，CI 在每次 push 上运行；最终一轮 10/10 job 全绿，含三平台测试矩阵与真实安装冒烟
- [x] 10.12 重写 `README.md`：三平台安装方式、`--list` 获取模块清单（不硬编码）、目录结构说明、`legacy/` 定位，并移除全部 `git submodule add` 等失效旧用法
- [x] 10.13 编写升级说明：需重跑的引导命令、会被替换的 `$HOME` 配置、备份目录位置；并在一台旧版机器上实测升级确认原配置被备份

## 11. CI 与验收

- [x] 11.1 删除 `.travis.yml`（与第 10 组迁移收尾一起执行）
- [x] 11.2 编写 `.github/workflows/ci.yml` 的 Linux 与 macOS job：shellcheck `-s sh` + shfmt + `--dry-run` + `--list`，退出码需为 0
- [x] 11.3 编写 Windows job：PSScriptAnalyzer + `-DryRun` + `-List`
- [x] 11.4 编写 `debian:stable-slim` 容器 job 执行真实安装，验证在 dash 下完成且不隐式依赖预装工具或 GNU 扩展
- [x] 11.5 增加禁止模块直接探测平台的静态检查：`modules/*/module.sh` 中出现 `uname` 或 `/etc/os-release` 引用即失败
- [x] 11.6 增加禁止失效镜像域名的检查：`config/` 下命中 `npm.taobao.org` 即失败（`legacy/` 需排除在检查范围外）
- [x] 11.7 增加 `config/` 无硬编码他人主目录绝对路径的检查（`legacy/` 排除在外）
- [x] 11.8 真实 macOS 端到端实测（沙箱 HOME）：dry-run 32 项计划零写入 → 5 个 core 模块全部成功 → 重跑退出码 0、文件系统逐字节相同、零新增备份；另验证已有真实 .zshrc/.gitconfig 被备份且校验和一致、旧 git 身份可取回；装完的 shell 实测 starship/zoxide/eza 生效，启动 169ms
- [x] 11.9 CI container job（debian:stable-slim，/bin/sh 是 dash）实测：真实安装 zsh+git 成功且 `zsh -i` 干净启动、预置 .zshrc 被备份且内容可取回、重跑零新增备份、modern-cli 优雅降级（12 个装上 6 个、失败者逐个点名、非零退出）
- [x] 11.10 走查 9 份 spec 的 84 条 requirement / 215 个 scenario：`test/spec_coverage.sh` 建立可机检的追溯表（84/84 已映射，且自校验引用的文件都存在），报告在 `notes/spec-coverage.md`；走查中发现 1Password 与默认 shell 两项只有实现无断言，已补 10 条测试；新增 `test/migration_test.sh` 45 条断言覆盖 legacy-migration

## 12. 待确认事项（阻塞对应任务，需在实施中与用户确认）

- [x] 12.1 已确认：全部搬入仓库（含工具自装的 codebase-memory skill 与 cbm-* hooks）；工具升级覆写风险记录在 `config/ai/README.md`
- [x] 12.2 按 design 既定实现：12 个默认 + atuin 可选（`DOT_WANT_ATUIN=1` 或 `DOT_CLI_OPTIONAL=atuin` 启用）。如需调整清单只改 `config/cli/tools.txt`。后续在第 13 组扩到 14 个默认 + 10 个可选
- [ ] 12.3 确认 macOS `defaults` 系统偏好设置本次不纳入（design 中列为 Non-Goal），如需纳入则另开 change
- [ ] 12.4 确认是否需要"多机器差异化"（工作机 vs 个人机装不同模块）；当前只有 `MODULE_TAGS` 粗粒度分组

## 13. 主题迁移与安装侧补齐（第 1-12 组收尾后追加）

前 12 组把 zsh 配置侧建完了，但漏了两处「配置引用了、却没人负责让它存在」的
缺口，以及一处被归档后没迁回来的个人配置。三者的共同特征是**不报错**——
功能静默消失，比装不上更难发现。

- [x] 13.1 把旧 omz 主题（`legacy/private/zshrc/robbyrussell.zsh-theme`，已被改过：🤥 用户名 🍭 时间 ➜）用 starship 重建到 `config/starship.toml`；不搬主题文件本身，因为那样 PowerShell 侧拿不到一致 prompt（与 `shell-environment` 的「starship 作为跨平台 prompt」冲突）
- [x] 13.2 编写 `modules/omz/module.sh`：装 oh-my-zsh 本体与 `20-omz.zsh` 引用的三个自定义插件。此前无任何模块负责，导致该片段在新机器上整段 `return`，插件永不生效且零报错
- [x] 13.3 给 `shell-environment` spec 补「oh-my-zsh 框架与插件的安装」requirement —— 覆盖率此前 84/84 全绿正是因为这条需求不存在，缺的是需求本身而非实现
- [x] 13.4 模块刻意不读 `$ZSH`，改用 `DOT_OMZ_DIR` 覆盖（同 `DOT_FONT_DIR` 的理由）：`$ZSH` 由交互式 shell 导出指向真实家目录，读它会让测试的 HOME 沙箱失效（开发中实际误写入过 `~/.oh-my-zsh`）
- [x] 13.5 补齐被引用却缺失的工具：`direnv`（`30-tools.zsh` 已挂 hook）、`tmux`（`20-omz.zsh` 已引用插件）进默认集，默认集 12 → 14
- [x] 13.6 扩充可选工具集：htop、btop、dust、duf、procs、tldr、hyperfine、xh、sd（共 10 个可选，含 atuin）。默认不装 —— 引导要快，且多数在 apt/dnf 仓库里没有、回退 cargo 需现场编译
- [x] 13.7 在 `platform/` 三层补包名映射：`tldr` → brew `tlrc` / pacman·apk `tealdeer`；不确定的发行版一律返回空串走 cargo 回退，而不是赌包名；Windows 侧 `tmux`/`htop` 显式设 `$null` 以区分「刻意不支持」与「忘了加」
- [x] 13.8 新增 `test/omz_test.sh`（41 条断言，替身 git + 沙箱 HOME，不真 clone）：覆盖幂等、dry-run 零写入、`$ZSH` 逃逸、clone 失败不留残骸、非空目录拒绝写入、缺 git 明确失败；并用变异测试确认「缺 git」用例在检查被移除时确实会失败
- [x] 13.9 在 `test/cli_test.sh` 增加「片段引用的工具必须在清单里」的交叉断言，把 13.5 这类漂移钉死；默认集数量断言同步 12 → 14
- [x] 13.10 验证：lint 全清、`run_all` 在 sh 与 dash 下 10 个套件全过、spec 覆盖 85/85、CI 10 个 job 全绿（含 Windows PowerShell 与 debian 容器真实安装，覆盖本机无法验证的 Linux/Windows 包名映射路径）
