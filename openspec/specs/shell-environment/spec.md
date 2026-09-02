# shell-environment Specification

## Purpose
TBD - created by archiving change modernize-dotfiles. Update Purpose after archive.
## Requirements
### Requirement: zsh 安装与默认 shell 设置

在 Unix 平台上，系统 SHALL 确保 zsh 已安装，并在用户确认后将其设为默认 shell。当 zsh 已是默认 shell 时 MUST 跳过设置操作。`DOT_HEADLESS` 为 `1` 时 MUST NOT 修改默认 shell（避免破坏 CI 或远程会话）。

#### Scenario: zsh 未安装时安装

- **WHEN** 系统上不存在 zsh 且 shell 模块执行
- **THEN** 通过当前平台的包管理器安装 zsh

#### Scenario: 已是默认 shell 则跳过

- **WHEN** 当前用户的默认 shell 已是 zsh
- **THEN** 不执行 `chsh`
- **AND** 输出提示说明已就位

#### Scenario: headless 环境不改默认 shell

- **WHEN** `DOT_HEADLESS` 等于 `1`
- **THEN** 系统不调用 `chsh`
- **AND** 输出提示说明跳过原因

### Requirement: zshrc 分片架构

系统 SHALL 以薄入口 + 有序片段的形式组织 zsh 配置：`config/zsh/zshrc` 作为入口，按文件名字典序 source `config/zsh/zshrc.d/*.zsh`。片段 MUST 按数字前缀分层：`00-env`、`10-path`、`20-omz`、`30-tools`、`40-aliases`、`90-local`。新增配置关注点 MUST 通过新增片段文件实现，MUST NOT 堆积到入口文件。

#### Scenario: 片段按序加载

- **WHEN** 启动一个交互式 zsh
- **THEN** `zshrc.d` 下的片段按文件名字典序依次被 source
- **AND** `00-env.zsh` 在 `20-omz.zsh` 之前生效

#### Scenario: 新增片段自动生效

- **WHEN** 在 `config/zsh/zshrc.d/` 下新增 `35-foo.zsh`
- **THEN** 下次启动 shell 时该片段被自动加载
- **AND** 无需修改入口 `zshrc`

#### Scenario: 单个片段出错不阻断启动

- **WHEN** 某个片段中的命令返回非零状态
- **THEN** 其余片段继续加载
- **AND** shell 仍进入可用的交互状态

### Requirement: 本地覆盖不入库

系统 SHALL 在所有片段加载完成后 source `~/.zshrc.local`（若存在），使本机专属配置能覆盖仓库配置。`~/.zshrc.local` MUST NOT 被纳入版本控制，且 MUST NOT 由安装流程创建为符号链接。

#### Scenario: 本地文件最后生效

- **WHEN** `~/.zshrc.local` 中重新定义了某个仓库片段已设置的别名
- **THEN** 交互式 shell 中生效的是 `~/.zshrc.local` 的定义

#### Scenario: 本地文件不存在时不报错

- **WHEN** `~/.zshrc.local` 不存在
- **THEN** shell 正常启动，无错误输出

### Requirement: Homebrew 环境正确加载

zsh 配置 SHALL 使用探测得到的 Homebrew 前缀加载 brew 环境，MUST NOT 硬编码 `/usr/local/bin/brew`。Apple Silicon 与 Intel Mac 以及 Linuxbrew MUST 都能正确加载。

#### Scenario: Apple Silicon 上加载 brew

- **WHEN** 在 Apple Silicon Mac 上启动 shell 且 Homebrew 位于 `/opt/homebrew`
- **THEN** `brew` 命令在 `PATH` 中可用
- **AND** `HOMEBREW_PREFIX` 等于 `/opt/homebrew`

#### Scenario: Homebrew 未安装时不报错

- **WHEN** 系统上没有安装 Homebrew
- **THEN** shell 正常启动且无错误输出

### Requirement: 失效镜像地址移除

zsh 配置 MUST NOT 包含已下线的镜像域名（含 `npm.taobao.org` 系列）。仍需要的镜像配置 SHALL 使用当前有效地址，并集中在单一片段中以便统一维护。

#### Scenario: 无失效域名

- **WHEN** 对 `config/zsh/` 下所有文件检索 `npm.taobao.org`
- **THEN** 没有任何匹配

#### Scenario: 镜像配置集中

- **WHEN** 查看镜像相关的环境变量定义
- **THEN** 它们全部位于同一个片段文件中

### Requirement: 单一 zsh 框架

系统 SHALL 只维护一套 zsh 框架配置（oh-my-zsh）。仓库 MUST NOT 同时保留 zim 的并行配置。

#### Scenario: 仓库内无 zim 配置

- **WHEN** 检查 `config/` 目录
- **THEN** 不存在 `zimrc` 或任何 zim 框架配置文件

### Requirement: oh-my-zsh 框架与插件的安装

系统 SHALL 安装 oh-my-zsh 框架本体与配置片段所引用的自定义插件。插件目录名 MUST 与 `20-omz.zsh` 的探测路径一致。安装 MUST 幂等，MUST NOT 覆盖或删除目标位置已有的用户内容；单个插件安装失败 MUST NOT 中断其余插件。

「条件化插件加载」只规定了配置侧按存在性加载，未规定谁负责让它们存在 —— 结果是片段在新机器上整段空转：`$ZSH/oh-my-zsh.sh` 不存在时它直接 return，插件列表里的 `zsh-autosuggestions` 等永远不生效，且没有任何报错。本 requirement 补上安装侧。

#### Scenario: 新机器上框架与插件都被装上

- **WHEN** 在未装过 oh-my-zsh 的机器上运行引导
- **THEN** `$ZSH/oh-my-zsh.sh` 就位
- **AND** `zsh-autosuggestions`、`zsh-syntax-highlighting`、`zsh-history-substring-search` 各自的 `*.plugin.zsh` 就位
- **AND** 下次 shell 启动时 `20-omz.zsh` 的插件列表包含这三者

#### Scenario: 重复运行不重复安装

- **WHEN** 在已装好的机器上再次运行引导
- **THEN** 框架与插件都报告为已存在
- **AND** 不产生任何网络请求

#### Scenario: 目标位置已有用户内容时拒绝写入

- **WHEN** `$ZSH` 目录非空但没有 `oh-my-zsh.sh`
- **THEN** 模块报错并说明原因
- **AND** 目录中原有文件保持不变

### Requirement: 条件化插件加载

系统 SHALL 按对应命令是否存在来决定加载哪些 zsh 插件，缺失的工具 MUST NOT 导致启动错误或错误输出。插件条件判断 MUST 位于专门的片段中，MUST NOT 散落在入口文件。

#### Scenario: 工具缺失时静默跳过插件

- **WHEN** 系统上未安装 `fzf` 而 shell 启动
- **THEN** fzf 相关的 shell 集成不被加载
- **AND** 启动过程无错误输出

#### Scenario: 工具存在时加载集成

- **WHEN** 系统上已安装 `zoxide`
- **THEN** zoxide 的 shell hook 被初始化
- **AND** `z` 命令可用

### Requirement: starship 作为跨平台 prompt

系统 SHALL 使用 starship 作为 zsh 与 PowerShell 的共同 prompt，配置真源为单一的 `config/starship.toml`。starship 不可用时 MUST 回退到内置 prompt，MUST NOT 使 shell 无提示符或报错。

#### Scenario: starship 驱动 prompt

- **WHEN** starship 已安装且 shell 启动
- **THEN** prompt 由 starship 渲染
- **AND** 使用的配置文件是仓库内 `config/starship.toml`

#### Scenario: mac 与 Windows 共用同一配置

- **WHEN** 在 macOS 的 zsh 与 Windows 的 PowerShell 中分别启动
- **THEN** 两者读取的是同一份 `starship.toml` 内容

#### Scenario: starship 缺失时回退

- **WHEN** starship 未安装且 shell 启动
- **THEN** 使用回退 prompt
- **AND** 无错误输出

### Requirement: 历史记录配置

系统 SHALL 配置 zsh 历史记录：历史文件路径明确、条目数不少于 10000、追加写入、忽略连续重复命令、记录时间戳、并在多个并行 shell 之间共享。

#### Scenario: 历史跨会话保留

- **WHEN** 在一个 shell 中执行命令后退出，再开启新 shell
- **THEN** 新 shell 的历史中包含该命令

#### Scenario: 连续重复命令只记一条

- **WHEN** 连续两次执行完全相同的命令
- **THEN** 历史中只保留一条记录

### Requirement: 启动性能预算

交互式 zsh 的启动时间 SHALL 不超过 200 毫秒（以 `zsh -i -c exit` 的实测耗时为准）。高开销的初始化（如 nvm、conda）MUST 采用惰性加载。系统 SHALL 提供一个测量启动耗时的命令供本地验证。

#### Scenario: 启动在预算内

- **WHEN** 在已完成安装的机器上测量 `zsh -i -c exit` 的耗时
- **THEN** 平均耗时不超过 200 毫秒

#### Scenario: nvm 惰性加载

- **WHEN** 启动 shell 但未执行任何 node 相关命令
- **THEN** nvm 未被初始化

#### Scenario: 首次调用触发惰性加载

- **WHEN** 在 shell 中首次执行 `node --version`
- **THEN** nvm 被初始化
- **AND** 命令正常返回版本号

#### Scenario: 提供性能测量命令

- **WHEN** 用户执行仓库提供的启动耗时测量命令
- **THEN** 输出交互式 shell 的启动耗时

### Requirement: 补全缓存

系统 SHALL 使用缓存化的 `compinit` 以避免每次启动都重建补全索引，并对配置文件生成 zsh 编译缓存（`.zwc`）。缓存 MUST 在配置文件变更后自动失效重建。

#### Scenario: 使用补全缓存

- **WHEN** 非首次启动交互式 shell
- **THEN** `compinit` 使用已有缓存而不重新扫描全部补全定义

#### Scenario: 配置变更后缓存重建

- **WHEN** 修改了某个 zsh 配置片段后启动 shell
- **THEN** 对应的编译缓存被重新生成
- **AND** 新配置生效

### Requirement: PowerShell profile

在 Windows 原生环境中，系统 SHALL 安装 PowerShell 7 并部署 profile，提供与 zsh 侧对齐的能力：starship prompt、现代 CLI 工具别名、历史搜索（PSReadLine）、以及不入库的本地覆盖文件。

#### Scenario: profile 就位

- **WHEN** 在 Windows 上完成引导后启动 PowerShell 7
- **THEN** profile 被加载
- **AND** prompt 由 starship 渲染

#### Scenario: PSReadLine 历史搜索可用

- **WHEN** 在 PowerShell 中输入命令前缀并按上方向键
- **THEN** 匹配该前缀的历史命令被检索出来

#### Scenario: Windows 侧本地覆盖

- **WHEN** 存在本地覆盖 profile 文件
- **THEN** 它在仓库 profile 之后被加载
- **AND** 该文件未被纳入版本控制

### Requirement: 跨 shell 共享配置

在 zsh 与 PowerShell 之间语义等价的配置（starship 配置、git 配置、AI 工具配置、以及现代 CLI 工具的别名语义）SHALL 只维护一份真源。

#### Scenario: 别名语义一致

- **WHEN** 在 zsh 与 PowerShell 中分别执行同名的仓库定义别名
- **THEN** 两者执行语义等价的操作

#### Scenario: starship 配置单一真源

- **WHEN** 修改 `config/starship.toml`
- **THEN** zsh 与 PowerShell 两侧的 prompt 都反映该修改
- **AND** 无需在第二处重复修改

