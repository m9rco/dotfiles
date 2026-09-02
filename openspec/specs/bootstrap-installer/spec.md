# bootstrap-installer Specification

## Purpose
TBD - created by archiving change modernize-dotfiles. Update Purpose after archive.
## Requirements
### Requirement: 双入口引导程序

系统 SHALL 提供两个引导入口：`bootstrap.sh` 用于 macOS、Linux 与 WSL；`bootstrap.ps1` 用于 Windows 原生环境。`bootstrap.sh` MUST 是 POSIX sh 兼容脚本（可在 `dash` 下执行），MUST NOT 依赖 bash 专有语法或任何尚未安装的第三方工具。`bootstrap.ps1` MUST 能在 Windows 自带的 PowerShell 5.1 下启动。

#### Scenario: Unix 上无参数运行

- **WHEN** 用户在 macOS 上执行 `./bootstrap.sh`
- **THEN** 系统完成平台探测，执行所有适用于当前平台的 `core` 标签模块
- **AND** 以退出码 `0` 结束

#### Scenario: dash 下可执行

- **WHEN** 在 `/bin/sh` 为 `dash` 的 Debian 系统上执行 `sh ./bootstrap.sh --dry-run`
- **THEN** 脚本正常完成，无语法错误

#### Scenario: PowerShell 5.1 下可启动

- **WHEN** 在仅有 PowerShell 5.1 的 Windows 上执行 `.\bootstrap.ps1 -Info`
- **THEN** 脚本正常输出探测结果，不因语法或 cmdlet 缺失而失败

### Requirement: 模块自描述与目录发现

系统 SHALL 通过扫描 `modules/*/module.sh` 发现模块，模块清单 MUST NOT 在引导程序或任何中心文件中重复声明。每个 `module.sh` MUST 声明 `MODULE_DESC`（描述）、`MODULE_PLATFORMS`（空格分隔的支持平台列表）、`MODULE_TAGS`（`core`/`ai`/`optional` 之一或多个），MAY 声明 `MODULE_REQUIRES`（依赖的模块名），并 MUST 定义 `install()` 函数。缺少必需声明或 `install()` 的模块 MUST 被拒绝并报错。

#### Scenario: 新增模块自动被发现

- **WHEN** 在 `modules/` 下新建目录并放入合规的 `module.sh`
- **THEN** 该模块出现在 `--list` 输出中
- **AND** 无需修改 `bootstrap.sh` 或任何清单文件

#### Scenario: 模块缺少必需元数据

- **WHEN** 某个 `module.sh` 未声明 `MODULE_PLATFORMS`
- **THEN** 系统输出该模块的校验错误并以非零退出码终止
- **AND** 不执行任何模块

#### Scenario: 模块缺少 install 函数

- **WHEN** 某个 `module.sh` 声明了全部元数据但未定义 `install()`
- **THEN** 系统报告该模块无效并终止

### Requirement: 平台适用性过滤

系统 SHALL 在执行前过滤模块：`MODULE_PLATFORMS` 不含当前 `DOT_OS` 的模块 MUST 被跳过；`DOT_HEADLESS` 为 `1` 时标记为需要图形环境的模块 MUST 被跳过。每个被跳过的模块 MUST 输出跳过原因。

#### Scenario: 跳过不适用平台的模块

- **WHEN** 在 Linux 上运行且某模块 `MODULE_PLATFORMS="macos"`
- **THEN** 该模块被跳过
- **AND** 输出包含跳过原因 `platform not supported`

#### Scenario: 跳过输出包含原因

- **WHEN** 任意模块因平台或环境原因被跳过
- **THEN** 输出明确指出该模块名与跳过原因

### Requirement: 依赖排序

系统 SHALL 按 `MODULE_REQUIRES` 对模块做拓扑排序，被依赖的模块 MUST 先于依赖它的模块执行。检测到循环依赖时 MUST 报错终止；引用了不存在的模块名时 MUST 报错终止。

#### Scenario: 依赖先于被依赖者执行

- **WHEN** 模块 `zsh-plugins` 声明 `MODULE_REQUIRES="zsh"`
- **THEN** `zsh` 模块在 `zsh-plugins` 之前执行

#### Scenario: 循环依赖被拒绝

- **WHEN** 模块 A 依赖 B 且模块 B 依赖 A
- **THEN** 系统输出循环依赖错误并以非零退出码终止
- **AND** 不执行任何模块

#### Scenario: 依赖不存在的模块

- **WHEN** 某模块声明 `MODULE_REQUIRES="nonexistent"`
- **THEN** 系统报告未知依赖并终止

### Requirement: 幂等执行

系统 SHALL 保证所有模块的安装操作幂等：在同一台机器上连续执行两次引导，第二次 MUST NOT 产生任何文件变更、MUST NOT 创建额外备份、且 MUST 以退出码 `0` 结束。

#### Scenario: 重复运行无变更

- **WHEN** 在已完成安装的机器上再次执行 `./bootstrap.sh`
- **THEN** 所有已就位的链接与配置被识别为已安装并跳过
- **AND** `~/.dotfiles-backup/` 下没有新增目录
- **AND** 退出码为 `0`

### Requirement: 预演模式

系统 SHALL 支持 `--dry-run`（PowerShell 侧 `-DryRun`）：打印每个模块将要执行的动作，但 MUST NOT 写入、删除或移动任何文件，MUST NOT 安装任何软件包。

#### Scenario: dry-run 不产生副作用

- **WHEN** 在全新环境执行 `./bootstrap.sh --dry-run`
- **THEN** 输出列出将创建的符号链接与将安装的软件包
- **AND** `$HOME` 下没有任何文件被创建或修改
- **AND** 没有软件包被实际安装

#### Scenario: dry-run 覆盖所有模块

- **WHEN** 执行 `./bootstrap.sh --dry-run`
- **THEN** 所有适用于当前平台的模块都被遍历并输出其计划动作

### Requirement: 选择性执行

系统 SHALL 支持 `--only <module>[,<module>...]` 只执行指定模块（连同其依赖），`--skip <module>[,...]` 排除指定模块，以及 `--tag <tag>` 按标签筛选。指定不存在的模块名时 MUST 报错终止而非静默忽略。

#### Scenario: 只安装指定模块

- **WHEN** 执行 `./bootstrap.sh --only fonts`
- **THEN** 只有 `fonts` 模块及其声明的依赖被执行
- **AND** 其他模块未被执行

#### Scenario: 按标签安装

- **WHEN** 执行 `./bootstrap.sh --tag ai`
- **THEN** 只有 `MODULE_TAGS` 含 `ai` 的模块被执行

#### Scenario: 未知模块名报错

- **WHEN** 执行 `./bootstrap.sh --only doesnotexist`
- **THEN** 系统输出未知模块错误并以非零退出码终止

### Requirement: 模块清单查询

系统 SHALL 支持 `--list` 列出所有已发现模块及其描述、支持平台、标签与当前是否适用。该命令 MUST NOT 修改任何文件。

#### Scenario: 列出模块

- **WHEN** 执行 `./bootstrap.sh --list`
- **THEN** 输出每个模块的名称、`MODULE_DESC`、`MODULE_PLATFORMS`、`MODULE_TAGS` 与是否适用于当前平台
- **AND** 文件系统未发生变更

### Requirement: 链接前备份

系统 SHALL 通过统一的 `dot_link SRC DST` 原语创建所有符号链接，行为如下：`DST` 已是指向 `SRC` 的链接则跳过；`DST` 是真实文件或目录则先移动到 `~/.dotfiles-backup/<timestamp>/` 保留原相对路径后再建链接；`DST` 是指向他处的符号链接则直接替换。系统 MUST NOT 在未备份的情况下删除用户的真实文件。

#### Scenario: 已有真实文件被备份

- **WHEN** `~/.zshrc` 是用户自己的真实文件且 zsh 模块执行安装
- **THEN** 原 `~/.zshrc` 被移动到 `~/.dotfiles-backup/<timestamp>/.zshrc`
- **AND** `~/.zshrc` 成为指向仓库内 `config/zsh/zshrc` 的符号链接
- **AND** 备份文件内容与原文件完全一致

#### Scenario: 已正确链接则跳过

- **WHEN** `~/.zshrc` 已是指向 `config/zsh/zshrc` 的符号链接
- **THEN** 不执行任何写操作
- **AND** 不创建备份

#### Scenario: 替换指向他处的链接

- **WHEN** `~/.zshrc` 是指向其他路径的符号链接
- **THEN** 该链接被替换为指向 `config/zsh/zshrc`
- **AND** 不创建备份（链接本身无内容）

#### Scenario: 目标父目录不存在

- **WHEN** 链接目标为 `~/.config/foo/bar` 且 `~/.config/foo` 不存在
- **THEN** 系统先创建父目录再建立链接

### Requirement: 统一日志输出

系统 SHALL 提供统一的日志函数（step / info / success / error / tip），所有模块 MUST 通过这些函数输出。当输出目标不是终端（如管道或 CI）时，MUST 自动禁用 ANSI 颜色转义。

#### Scenario: 终端下带颜色

- **WHEN** 在交互式终端中运行引导
- **THEN** 输出包含 ANSI 颜色转义序列

#### Scenario: 管道下无颜色

- **WHEN** 引导输出被重定向到文件或管道
- **THEN** 输出不含任何 ANSI 转义序列

### Requirement: 失败处理与退出码

系统 SHALL 在单个模块失败时继续执行其余模块（除非该模块是他人的依赖），并在结束时输出成功与失败模块的汇总。存在任何模块失败时，引导程序 MUST 以非零退出码结束。依赖失败的模块 MUST 被跳过而非执行。

#### Scenario: 单模块失败不中断整体

- **WHEN** 某个非依赖型模块安装失败
- **THEN** 其余模块继续执行
- **AND** 结束时输出失败模块列表
- **AND** 退出码非零

#### Scenario: 依赖失败则跳过下游

- **WHEN** 模块 `zsh` 失败且 `zsh-plugins` 声明依赖 `zsh`
- **THEN** `zsh-plugins` 被跳过并标记为 `skipped (dependency failed)`

#### Scenario: 全部成功

- **WHEN** 所有适用模块均安装成功
- **THEN** 输出成功汇总
- **AND** 退出码为 `0`

### Requirement: 帮助信息

系统 SHALL 支持 `--help` 输出用法说明，包含全部受支持的参数。帮助文本中的模块相关信息 MUST 由模块发现动态生成，MUST NOT 手写硬编码的模块名清单。

#### Scenario: 帮助信息动态生成

- **WHEN** 新增一个模块后执行 `./bootstrap.sh --help`
- **THEN** 帮助信息中关于可用模块的部分反映当前实际存在的模块
- **AND** 不存在与实际模块不一致的硬编码清单

