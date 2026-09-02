# font-provisioning Specification

## Purpose
TBD - created by archiving change modernize-dotfiles. Update Purpose after archive.
## Requirements
### Requirement: Nerd Fonts 作为字体来源

系统 SHALL 从 Nerd Fonts 的发布包安装字体，MUST NOT 通过 clone 完整字体源码仓库的方式获取。默认安装集 MUST 包含一款终端等宽字体（JetBrainsMono Nerd Font）与一款中文对齐良好的等宽字体（Maple Mono NF）。字体清单 MUST 是声明式的，新增字体不需要修改安装逻辑。

#### Scenario: 安装默认字体集

- **WHEN** 在图形环境中执行字体模块
- **THEN** JetBrainsMono Nerd Font 与 Maple Mono NF 被安装到平台字体目录
- **AND** 字体文件可被系统枚举到

#### Scenario: 不 clone 字体仓库

- **WHEN** 字体模块执行安装
- **THEN** 不存在对完整字体源码仓库的 git clone 操作
- **AND** 只下载所需字体的发布包

#### Scenario: 声明式新增字体

- **WHEN** 在字体清单中增加一款字体条目
- **THEN** 下次执行字体模块时该字体被安装
- **AND** 无需修改安装脚本逻辑

### Requirement: 平台字体目录

系统 SHALL 按平台把字体安装到用户级字体目录，MUST NOT 要求管理员/root 权限：macOS 为 `~/Library/Fonts`；Linux 为 `~/.local/share/fonts`；Windows 为用户字体位置并注册到用户注册表。

#### Scenario: macOS 安装位置

- **WHEN** 在 macOS 上安装字体
- **THEN** 字体文件位于 `~/Library/Fonts`
- **AND** 安装过程未请求管理员权限

#### Scenario: Linux 安装位置与目录创建

- **WHEN** 在 Linux 上安装字体且 `~/.local/share/fonts` 不存在
- **THEN** 该目录被创建
- **AND** 字体文件被放入其中

#### Scenario: Windows 免提权安装

- **WHEN** 在 Windows 上以普通用户身份安装字体
- **THEN** 字体被复制到用户字体位置并注册到用户注册表
- **AND** 安装过程未请求提权

### Requirement: 字体缓存刷新

在 Linux 上，系统 SHALL 在字体文件落地后刷新字体缓存（`fc-cache -f`），使字体立即可被应用枚举。`fc-cache` 不存在时 MUST 输出提示而非失败。

#### Scenario: 刷新缓存后可用

- **WHEN** 在 Linux 上完成字体安装且 `fc-cache` 可用
- **THEN** `fc-cache -f` 被执行
- **AND** 新字体可被 `fc-list` 列出

#### Scenario: fc-cache 缺失时不失败

- **WHEN** 在 Linux 上安装字体但系统无 `fc-cache`
- **THEN** 系统输出提示说明需手动刷新缓存
- **AND** 字体模块以成功状态结束

### Requirement: 字体安装幂等

系统 SHALL 在字体已安装时跳过下载与复制。判定 MUST 基于目标字体文件是否已存在于平台字体目录。

#### Scenario: 重复执行不重新下载

- **WHEN** 字体已安装且再次执行字体模块
- **THEN** 不发起任何下载请求
- **AND** 输出提示说明字体已就位

### Requirement: 无图形环境跳过

系统 SHALL 在 `DOT_HEADLESS` 为 `1` 或 `DOT_WSL` 为 `1` 时跳过字体安装，并输出跳过原因。WSL 场景的提示 MUST 说明字体应在 Windows 宿主机安装。

#### Scenario: SSH 会话跳过

- **WHEN** 通过 SSH 执行引导（`DOT_HEADLESS` 为 `1`）
- **THEN** 字体模块被跳过
- **AND** 输出跳过原因

#### Scenario: WSL 内跳过并给出指引

- **WHEN** 在 WSL 中执行引导
- **THEN** 字体模块被跳过
- **AND** 输出提示说明字体需在 Windows 宿主机安装

### Requirement: 下载失败处理

系统 SHALL 在字体下载失败时报告具体失败的字体与原因，并继续处理清单中的其余字体；全部字体均失败时字体模块 MUST 以失败状态结束。下载得到的压缩包 MUST 在解压前校验为有效归档文件。

#### Scenario: 单个字体下载失败不阻断其余

- **WHEN** 清单中某个字体的下载请求失败而其他成功
- **THEN** 成功的字体被正常安装
- **AND** 输出指明失败的字体名称与原因

#### Scenario: 损坏的压缩包被拒绝

- **WHEN** 下载得到的文件不是有效的压缩包
- **THEN** 系统报告该字体安装失败
- **AND** 不向字体目录写入任何文件

#### Scenario: 全部失败则模块失败

- **WHEN** 清单中所有字体都下载失败
- **THEN** 字体模块以非零状态结束
- **AND** 汇总中该模块被标记为失败

### Requirement: 终端字体指向

系统 SHALL 在字体安装完成后，把受管理的终端配置指向已安装的 Nerd Font。对于无法以配置文件方式设置字体的终端，MUST 输出手动设置指引而非静默跳过。

#### Scenario: 受管终端自动指向

- **WHEN** 字体安装完成且存在受仓库管理的终端配置
- **THEN** 该配置的字体项被设置为已安装的 Nerd Font

#### Scenario: 不可自动配置时给出指引

- **WHEN** 当前终端的字体无法通过配置文件设置
- **THEN** 系统输出需要手动设置的字体名称与操作指引

### Requirement: 预演模式不下载

在 `--dry-run` 下，字体模块 MUST NOT 发起任何网络下载，只输出将要安装的字体清单与目标目录。

#### Scenario: dry-run 只打印计划

- **WHEN** 执行 `./bootstrap.sh --dry-run --only fonts`
- **THEN** 输出将安装的字体名称与目标目录
- **AND** 无网络下载发生
- **AND** 字体目录未发生变更

