# ai-coding-clis Specification

## Purpose
TBD - created by archiving change modernize-dotfiles. Update Purpose after archive.
## Requirements
### Requirement: AI 编码 CLI 安装集

系统 SHALL 提供 AI 编码 CLI 的安装：Claude Code、Codex CLI、Gemini CLI。清单 MUST 是声明式的，每个条目 MUST 声明其安装方式与适用平台。用户 SHALL 能只安装其中的部分工具。

#### Scenario: 安装全部 AI CLI

- **WHEN** 执行该模块且未做子集筛选
- **THEN** 清单中每个适用于当前平台的 AI CLI 被安装
- **AND** 各自的可执行文件在 `PATH` 中可用

#### Scenario: 只安装指定的 AI CLI

- **WHEN** 用户指定只安装 Claude Code
- **THEN** 只有 Claude Code 被安装
- **AND** 其他 AI CLI 未被安装

#### Scenario: 声明式新增 AI CLI

- **WHEN** 在清单中增加一个新的 AI CLI 条目
- **THEN** 下次执行该模块时它被安装
- **AND** 无需修改安装逻辑代码

### Requirement: 三平台安装一致

系统 SHALL 在 macOS、Linux 与 Windows 上都能完成 AI CLI 安装，平台差异（包管理器、npm 全局前缀、PATH 写入位置）MUST 由 `platform/` 层吸收。在 WSL 中安装 MUST 独立于 Windows 宿主机的安装。

#### Scenario: macOS 上安装

- **WHEN** 在 macOS 上执行该模块
- **THEN** AI CLI 被安装且可执行

#### Scenario: Windows 原生安装

- **WHEN** 在 Windows 上执行 `bootstrap.ps1`
- **THEN** AI CLI 被安装且在 PowerShell 中可执行

#### Scenario: WSL 内独立安装

- **WHEN** 在 WSL 中执行 `bootstrap.sh`
- **THEN** WSL 内独立安装一份 AI CLI
- **AND** 不依赖 Windows 宿主机上的安装

### Requirement: npm 全局安装的 PATH 处理

对通过 npm 全局安装的 AI CLI，系统 SHALL 确保 npm 全局 bin 目录在 `PATH` 中，MUST NOT 要求使用 `sudo` 进行全局安装。npm 不可用时 MUST 报告该工具无法安装的具体原因。

#### Scenario: npm 全局 bin 加入 PATH

- **WHEN** 某 AI CLI 通过 npm 全局安装完成
- **THEN** npm 全局 bin 目录存在于 `PATH` 中
- **AND** 该 CLI 可直接调用

#### Scenario: 不使用 sudo 安装

- **WHEN** 执行 npm 全局安装
- **THEN** 安装过程未使用 `sudo`

#### Scenario: npm 缺失时报告原因

- **WHEN** 某 AI CLI 需要 npm 但系统上没有 npm
- **THEN** 输出说明该工具因缺少 npm 而未安装
- **AND** 其余 AI CLI 继续安装

### Requirement: 安装幂等与升级

系统 SHALL 在 AI CLI 已安装时跳过安装。系统 SHALL 另外提供一条显式的升级路径，用于把已安装的 AI CLI 更新到最新版本；升级 MUST NOT 在默认引导流程中自动执行。

#### Scenario: 已安装则跳过

- **WHEN** Claude Code 已安装且再次执行该模块
- **THEN** 不重新安装
- **AND** 输出提示说明已就位及当前版本

#### Scenario: 显式升级

- **WHEN** 用户执行升级操作
- **THEN** 已安装的 AI CLI 被更新到最新版本

#### Scenario: 默认引导不自动升级

- **WHEN** 执行普通引导流程
- **THEN** 已安装的 AI CLI 版本未被改变

### Requirement: 版本检查为非阻断

系统 SHALL 在安装后检查并输出各 AI CLI 的版本。版本检查失败（命令不支持版本参数、输出格式变化、或调用超时）MUST 只产生警告，MUST NOT 使模块失败。

#### Scenario: 输出版本信息

- **WHEN** AI CLI 安装完成且支持版本查询
- **THEN** 输出中包含该工具的版本号

#### Scenario: 版本查询失败仅警告

- **WHEN** 某 AI CLI 的版本查询返回非零状态或无法解析
- **THEN** 输出一条警告
- **AND** 该模块仍以成功状态结束

### Requirement: 不在安装期要求凭据

系统 MUST NOT 在安装 AI CLI 的过程中要求用户输入 API key 或执行登录。凭据配置 SHALL 由独立的密钥管理能力负责，安装完成后 SHOULD 输出后续认证步骤的指引。

#### Scenario: 安装过程不索取凭据

- **WHEN** 执行 AI CLI 安装模块
- **THEN** 过程中没有任何要求输入 API key 或登录的交互

#### Scenario: 输出后续认证指引

- **WHEN** AI CLI 安装完成
- **THEN** 输出说明如何完成认证的后续步骤

### Requirement: 预演模式不安装

在 `--dry-run` 下，该模块 MUST 只输出将安装的 AI CLI 及计划使用的安装方式，MUST NOT 执行实际安装或网络下载。

#### Scenario: dry-run 输出计划

- **WHEN** 执行 `./bootstrap.sh --dry-run --tag ai`
- **THEN** 输出每个待安装 AI CLI 及其计划安装方式
- **AND** 没有任何工具被实际安装

