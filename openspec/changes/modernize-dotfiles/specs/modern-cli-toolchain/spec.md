## ADDED Requirements

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

当某工具在当前平台的包管理器中不可用时，系统 SHALL 尝试受支持的回退安装方式（如官方发布二进制、cargo、npm）。回退也失败时 MUST 记录该工具失败并继续处理其余工具，MUST NOT 中断整个模块。

#### Scenario: 使用回退方式安装

- **WHEN** 某工具在当前包管理器的仓库中不存在但存在受支持的回退方式
- **THEN** 系统通过回退方式完成安装
- **AND** 输出说明所使用的安装方式

#### Scenario: 单个工具失败不阻断其余

- **WHEN** 某工具的所有安装方式均失败
- **THEN** 其余工具继续安装
- **AND** 汇总中列出该工具及失败原因

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
