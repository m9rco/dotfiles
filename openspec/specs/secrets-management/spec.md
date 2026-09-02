# secrets-management Specification

## Purpose
TBD - created by archiving change modernize-dotfiles. Update Purpose after archive.
## Requirements
### Requirement: 仓库内零明文密钥

仓库 MUST NOT 包含任何明文 API key、token、密码或私钥。所有敏感值 SHALL 通过运行时从系统密钥库、密码管理器或不入库的本地文件读取。

#### Scenario: 仓库无明文密钥

- **WHEN** 对整个仓库执行密钥扫描
- **THEN** 没有发现任何明文凭据

#### Scenario: 配置只引用不内嵌

- **WHEN** 检查任何需要凭据的配置文件
- **THEN** 其中只包含对凭据来源的引用，不包含凭据本身

### Requirement: 平台密钥库集成

系统 SHALL 提供跨平台的密钥读取接口，按平台使用对应的系统密钥库：macOS 使用 keychain、Linux 使用 secret 服务、Windows 使用凭据管理器。调用方 MUST 使用统一接口，MUST NOT 直接调用平台特有命令。

#### Scenario: macOS 从 keychain 读取

- **WHEN** 在 macOS 上通过统一接口读取一个已存入 keychain 的密钥
- **THEN** 返回该密钥的值

#### Scenario: Windows 从凭据管理器读取

- **WHEN** 在 Windows 上通过统一接口读取一个已存入凭据管理器的密钥
- **THEN** 返回该密钥的值

#### Scenario: 密钥不存在时明确报错

- **WHEN** 读取一个不存在的密钥
- **THEN** 返回非零状态并输出可读的错误信息
- **AND** 不返回空值冒充成功

### Requirement: 密码管理器支持

系统 SHALL 支持通过 1Password CLI 读取凭据，作为系统密钥库之外的可选来源。1Password CLI 未安装或未登录时 MUST 给出明确提示并回退到其他来源，MUST NOT 挂起等待交互。

#### Scenario: 通过 1Password 读取

- **WHEN** 1Password CLI 已安装并已登录，且请求一个存放于其中的凭据
- **THEN** 返回该凭据的值

#### Scenario: 未登录时不挂起

- **WHEN** 1Password CLI 已安装但未登录
- **THEN** 系统输出提示说明需要先登录
- **AND** 命令在有限时间内返回，不无限等待

#### Scenario: 未安装时回退

- **WHEN** 1Password CLI 未安装
- **THEN** 系统回退到其他凭据来源
- **AND** 输出说明所使用的来源

### Requirement: 本地环境文件兜底

系统 SHALL 支持 `~/.config/dotfiles/env.local` 作为兜底的凭据来源。该文件 MUST 被 `.gitignore` 排除，MUST 以 `600` 权限创建，且 MUST NOT 由安装流程链接进仓库。

#### Scenario: 文件权限受限

- **WHEN** 系统创建 `~/.config/dotfiles/env.local`
- **THEN** 该文件权限为 `600`

#### Scenario: 被 gitignore 排除

- **WHEN** 检查 `.gitignore`
- **THEN** 本地环境文件的路径模式被排除

#### Scenario: 不链接进仓库

- **WHEN** 执行引导流程
- **THEN** 该文件未被创建为指向仓库的符号链接

### Requirement: shell 启动不同步读取密钥

shell 启动过程 MUST NOT 同步调用密钥库或密码管理器（会显著拖慢启动并可能触发认证弹窗）。系统 SHALL 提供按需注入凭据的函数，仅在用户显式调用时读取。

#### Scenario: 启动不触发密钥库调用

- **WHEN** 启动一个交互式 shell
- **THEN** 没有对系统密钥库或密码管理器的调用发生

#### Scenario: 显式调用时注入

- **WHEN** 用户在 shell 中显式执行凭据注入函数
- **THEN** 相应的环境变量在当前 shell 中被设置

#### Scenario: 启动无认证弹窗

- **WHEN** 启动交互式 shell
- **THEN** 不出现任何密钥库或密码管理器的认证提示

### Requirement: 误提交守卫

系统 SHALL 安装 `gitleaks` 并在本仓库配置 pre-commit 守卫，在提交前检测疑似凭据。检出疑似凭据时 MUST 阻止提交并指明具体文件与位置。

#### Scenario: 阻止含密钥的提交

- **WHEN** 暂存区中的文件包含疑似 API key 并尝试提交
- **THEN** 提交被阻止
- **AND** 输出指明该文件与所在位置

#### Scenario: 正常提交不受影响

- **WHEN** 暂存内容不含任何疑似凭据并尝试提交
- **THEN** 提交正常完成

#### Scenario: gitleaks 缺失时提示

- **WHEN** `gitleaks` 未安装而尝试启用守卫
- **THEN** 系统输出提示说明守卫未生效及安装方式

### Requirement: 本地推理工具可选安装

系统 SHALL 提供 `ollama` 的可选安装，MUST NOT 默认安装（体积大且并非每台机器都需要）。安装 MUST NOT 自动下载任何模型权重。

#### Scenario: 默认不安装

- **WHEN** 执行不带可选项的引导
- **THEN** `ollama` 未被安装

#### Scenario: 显式安装 ollama

- **WHEN** 用户显式选择安装本地推理工具
- **THEN** `ollama` 被安装且可执行

#### Scenario: 不自动拉取模型

- **WHEN** `ollama` 安装完成
- **THEN** 没有模型权重被下载
- **AND** 输出说明如何按需拉取模型

### Requirement: 密钥值不出现在日志

系统 MUST NOT 在任何日志、错误信息或 `--dry-run` 输出中打印凭据的值。涉及凭据的输出 SHALL 只包含凭据的名称或来源。

#### Scenario: 日志只含名称

- **WHEN** 执行涉及凭据读取的操作并产生日志
- **THEN** 日志中出现凭据名称与来源，不出现其值

#### Scenario: 读取失败的错误不泄露

- **WHEN** 凭据读取失败并输出错误
- **THEN** 错误信息中不包含任何部分凭据内容

#### Scenario: dry-run 不打印值

- **WHEN** 在 `--dry-run` 下执行涉及凭据的模块
- **THEN** 输出中不包含任何凭据的值

