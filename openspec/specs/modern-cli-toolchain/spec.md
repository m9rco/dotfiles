# modern-cli-toolchain Specification

## Purpose
TBD - created by archiving change modernize-dotfiles. Update Purpose after archive.
## Requirements
### Requirement: 声明式工具清单

系统 SHALL 以声明式清单定义要安装的现代 CLI 工具，清单 MUST 是跨平台的逻辑名列表，平台特有的包名映射 MUST 收敛在 `platform/` 层。新增工具 MUST 只需修改清单，MUST NOT 需要新增安装代码。

#### Scenario: 声明式新增工具

- **WHEN** 在工具清单中增加一个工具的逻辑名
- **THEN** 下次执行该模块时该工具被安装
- **AND** 无需修改安装逻辑代码

#### Scenario: 包名映射位于平台层

- **WHEN** 某工具在不同平台的包名不同
- **THEN** 映射关系定义在 `platform/` 对应文件中
- **AND** 清单中只出现逻辑名

### Requirement: 默认工具集

系统 SHALL 默认安装以下工具：`ripgrep`、`fd`、`bat`、`eza`、`fzf`、`zoxide`、`delta`、`jq`、`yq`、`gh`、`lazygit`、`starship`。`atuin` SHALL 作为可选工具提供（因其改变 shell 历史行为），MUST NOT 默认安装。

#### Scenario: 默认工具全部就位

- **WHEN** 在支持的平台上执行该模块
- **THEN** 默认集中的每个工具在 `PATH` 中可执行

#### Scenario: atuin 需显式启用

- **WHEN** 不带任何可选参数执行引导
- **THEN** `atuin` 未被安装

#### Scenario: 显式安装 atuin

- **WHEN** 用户显式选择安装 `atuin`
- **THEN** `atuin` 被安装并完成 shell 集成

### Requirement: 包管理器不可用时的回退

当某工具在当前平台的包管理器中不可用时，系统 SHALL 尝试受支持的回退安装方式（如官方发布二进制、cargo、npm）。回退也失败时 MUST 记录该工具失败并继续处理其余工具，MUST NOT 中断整个模块。当某回退方式所需的工具链本身缺失时，系统 MUST 明确说明该方式未被尝试及原因，MUST NOT 报告为「已尝试」。

回退 MUST 只在包管理器不可用或安装失败之后才被尝试 —— 声明了回退 MUST NOT 导致仓库中本来存在的包被绕过。

工具清单中空的回退列 MUST 表示一个结论（该工具没有可用的回退方式，或它在各平台仓库里都有），MUST NOT 表示尚未考察。该结论的理由 SHALL 记录在清单中。

#### Scenario: 使用回退方式安装

- **WHEN** 某工具在当前包管理器的仓库中不存在但存在受支持的回退方式
- **THEN** 系统通过回退方式完成安装
- **AND** 输出说明所使用的安装方式

#### Scenario: 包管理器有包时不走回退

- **WHEN** 某工具同时存在于当前包管理器的仓库中、且声明了回退方式
- **THEN** 系统从包管理器安装
- **AND** 不发起回退方式所需的网络请求

#### Scenario: 单个工具失败不阻断其余

- **WHEN** 某工具的所有安装方式均失败
- **THEN** 其余工具继续安装
- **AND** 汇总中列出该工具及失败原因

#### Scenario: 回退方式所需工具链缺失

- **WHEN** 某工具声明了 cargo 回退但当前机器没有 cargo
- **THEN** 输出说明 cargo 不可用、该回退未被尝试
- **AND** MUST NOT 声称已尝试该回退方式

#### Scenario: 预编译二进制优先于源码编译

- **WHEN** 某工具同时声明了预编译二进制（官方脚本或发布二进制）与 cargo 回退
- **THEN** 先尝试预编译二进制
- **AND** 仅在其失败后才尝试 cargo

#### Scenario: 空回退列是刻意的结论

- **WHEN** 某工具的回退列为空
- **THEN** 清单中说明该工具为何不需要或无法使用回退方式

### Requirement: 发布二进制的获取与校验

当某工具通过项目自己的 GitHub release 安装预编译二进制时，系统 SHALL 满足以下约束。

二进制 MUST 装入用户目录（不需要提权），MUST NOT 写入系统目录。

来源仓库 MUST 在工具清单中可见 —— 这是公开仓库里的供应链事实，MUST NOT 只存在于实现代码中。资产文件名与归档内部结构属于机械细节，SHOULD 收敛在实现层，MUST NOT 要求清单的读者理解它们。

下载的内容 MUST 在解包**之前**校验。校验 MUST NOT 只依赖 HTTP 状态码 —— 代理与 CDN 会以 200 返回 HTML 错误页或登录页。校验失败时输出 MUST 说明实际收到的是什么，以便与「资产改名」这类失败区分开。

当本平台（OS 与架构的组合）没有对应资产时，系统 MUST 说明该情况且 MUST NOT 报告为「已尝试」。

无人值守的引导 MUST NOT 因为网络不可达而逐个工具超时等待：首次判定不可达之后，后续同类回退 MUST 被短路跳过。系统 SHALL 提供显式关闭该回退的开关，以适配气隙环境或不放行相关域名的代理。

#### Scenario: 从发布二进制安装

- **WHEN** 某工具在当前包管理器的仓库中不存在，但项目发布了适配本平台的预编译二进制
- **THEN** 系统下载该二进制并装入用户目录
- **AND** 二进制具有可执行权限
- **AND** 输出说明使用的是发布二进制这条路径

#### Scenario: 来源仓库在清单中可见

- **WHEN** 某工具声明了发布二进制回退
- **THEN** 工具清单中出现该二进制的来源仓库
- **AND** 资产文件名不出现在清单中

#### Scenario: 拿到的不是归档

- **WHEN** 下载返回的内容不是声明的归档格式（如代理以 200 返回 HTML 错误页）
- **THEN** 系统在解包之前判定失败
- **AND** 输出说明实际收到的内容是什么
- **AND** 不产生任何已安装的文件

#### Scenario: 本平台没有对应资产

- **WHEN** 某工具声明了发布二进制回退，但项目未为当前 OS 与架构的组合发布资产
- **THEN** 输出说明本平台没有可用资产
- **AND** MUST NOT 声称已尝试该回退方式

#### Scenario: 网络不可达时不重复等待

- **WHEN** 首次获取发布二进制因网络不可达而失败，且后续仍有工具声明了同类回退
- **THEN** 后续的同类回退被跳过而不再各自等待超时
- **AND** 输出说明跳过原因

#### Scenario: 显式关闭发布二进制回退

- **WHEN** 设置了关闭该回退的开关
- **THEN** 系统不发起任何相关的网络请求
- **AND** 其余安装方式照常进行

### Requirement: 附加仓库的启用

在 RHEL 族（`DOT_DISTRO` 为 `rhel`）上，系统 SHALL 在安装工具前启用 EPEL —— 该发行版的 base 仓库缺少多数现代 CLI 工具。启用 MUST 在一次引导内只执行一次，已启用时 MUST NOT 重复安装。启用失败 MUST NOT 使模块失败（缺少 EPEL 只是让更多工具走回退链）。Fedora MUST NOT 启用 EPEL（其官方仓库已收录这些包）。系统 SHALL 提供关闭该行为的开关，以适配离线环境或已自带这些包的内部镜像。

#### Scenario: RHEL 族启用 EPEL

- **WHEN** `DOT_DISTRO` 为 `rhel` 且 EPEL 未启用
- **THEN** 系统在安装第一个包之前安装 `epel-release`
- **AND** 随后的工具安装从 EPEL 取得包

#### Scenario: 已启用则不重复

- **WHEN** EPEL 已在仓库列表中
- **THEN** 不再安装 `epel-release`

#### Scenario: Fedora 不需要 EPEL

- **WHEN** `DOT_DISTRO` 为 `fedora`
- **THEN** 不安装 `epel-release`

#### Scenario: 显式关闭

- **WHEN** 设置了关闭开关
- **THEN** 不进行任何 EPEL 相关操作
- **AND** 工具安装照常进行（缺包者走回退链）

### Requirement: 工具失败的致命性分级

清单中的每个工具 SHALL 标注 `essential`、`default` 或 `optional`。只有 `essential` 工具安装失败时模块才 MUST 以失败状态结束；`default` 工具失败 MUST 只告警并使模块成功结束 —— shell 配置对缺失工具已做优雅降级，让整台机器的引导因一个便利工具装不上而失败是不成比例的。未知标签值 MUST 报错，MUST NOT 静默当作默认值处理。

#### Scenario: 非必需工具失败不影响退出码

- **WHEN** 某 `default` 工具的所有安装方式均失败
- **THEN** 输出列出该工具并说明它不是必需的
- **AND** 模块以成功状态结束

#### Scenario: 必需工具失败导致模块失败

- **WHEN** 某 `essential` 工具的所有安装方式均失败
- **THEN** 输出单独标注哪些是必需工具
- **AND** 模块以失败状态结束

#### Scenario: 标签拼写错误被拒绝

- **WHEN** 清单中某行的标签值不是三个合法值之一
- **THEN** 系统报错并指出该标签值
- **AND** MUST NOT 把该行静默当作 `default` 处理

### Requirement: 工具安装幂等

系统 SHALL 在工具已安装时跳过安装动作。判定 MUST 基于该工具的可执行文件在 `PATH` 中是否可用。

#### Scenario: 已安装则跳过

- **WHEN** `ripgrep` 已安装且再次执行该模块
- **THEN** 不触发安装动作
- **AND** 输出提示说明已就位

### Requirement: shell 集成 hook

系统 SHALL 为需要 shell hook 的工具（`fzf`、`zoxide`、可选的 `atuin`）配置初始化，且 MUST 仅在对应可执行文件存在时才初始化。hook 配置 MUST 位于专门的 shell 配置片段中。

#### Scenario: zoxide hook 生效

- **WHEN** `zoxide` 已安装且启动交互式 shell
- **THEN** zoxide 的 shell hook 被初始化
- **AND** 目录跳转命令可用

#### Scenario: fzf 键位绑定生效

- **WHEN** `fzf` 已安装且启动交互式 shell
- **THEN** fzf 的键位绑定与补全被加载

#### Scenario: 工具缺失时不初始化

- **WHEN** `zoxide` 未安装且启动交互式 shell
- **THEN** 不尝试初始化 zoxide
- **AND** 启动过程无错误输出

### Requirement: 别名与传统命令共存

系统 SHALL 为现代替代工具提供别名（如 `ls` 系列指向 `eza`、`cat` 类查看指向 `bat`），且 MUST 保证：别名仅在对应工具存在时定义；原始命令仍可通过明确方式调用；别名 MUST NOT 破坏脚本中对原命令输出格式的依赖（即别名只影响交互式 shell）。

#### Scenario: 交互式 shell 中别名生效

- **WHEN** `eza` 已安装且在交互式 shell 中执行列目录别名
- **THEN** 由 `eza` 处理该命令

#### Scenario: 非交互式脚本不受影响

- **WHEN** 一个非交互式 shell 脚本中调用 `ls`
- **THEN** 执行的是系统原始 `ls`
- **AND** 输出格式未被别名改变

#### Scenario: 工具缺失时无别名

- **WHEN** `bat` 未安装
- **THEN** 相关别名未被定义
- **AND** 原始命令行为不变

### Requirement: delta 集成 git

系统 SHALL 在 `delta` 可用时把它配置为 git 的 diff/pager。`delta` 不可用时 git 配置 MUST 退回到默认 pager 且 MUST NOT 产生错误。

#### Scenario: delta 作为 git pager

- **WHEN** `delta` 已安装且执行 `git diff`
- **THEN** 输出由 delta 渲染

#### Scenario: delta 缺失时 git 仍可用

- **WHEN** `delta` 未安装且执行 `git diff`
- **THEN** 使用默认 pager 输出
- **AND** 无错误信息

### Requirement: 跨平台一致的工具体验

同一工具在 macOS、Linux 与 Windows 上 SHALL 提供一致的别名与配置语义。仅在某平台不可用的工具 MUST 在清单中显式标注其适用平台。

#### Scenario: 三平台别名语义一致

- **WHEN** 在 macOS、Linux 与 Windows 上分别执行同名的仓库定义别名
- **THEN** 三者执行语义等价的操作

#### Scenario: 平台限定工具被标注

- **WHEN** 某工具只在部分平台可用
- **THEN** 清单中标注了其适用平台
- **AND** 在不适用的平台上该工具被跳过并说明原因

### Requirement: 预演模式不安装

在 `--dry-run` 下，该模块 MUST 只输出将要安装的工具清单及计划使用的安装方式，MUST NOT 执行任何实际安装。

#### Scenario: dry-run 输出计划

- **WHEN** 执行 `./bootstrap.sh --dry-run --only modern-cli`
- **THEN** 输出每个待安装工具及其计划安装方式
- **AND** 没有任何软件包被实际安装

