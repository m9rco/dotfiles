## ADDED Requirements

### Requirement: 操作系统识别

系统 SHALL 在引导开始时自动识别当前操作系统，并将结果导出为 `DOT_OS`，取值限定为 `macos`、`linux`、`windows` 之一。识别失败时 MUST 以非零退出码终止并输出可读的错误信息，不得继续执行任何安装动作。

#### Scenario: macOS 上识别

- **WHEN** 在 macOS 上执行 `bootstrap.sh`
- **THEN** `DOT_OS` 等于 `macos`

#### Scenario: Linux 上识别

- **WHEN** 在 Linux 上执行 `bootstrap.sh`
- **THEN** `DOT_OS` 等于 `linux`

#### Scenario: Windows 原生识别

- **WHEN** 在 Windows PowerShell 中执行 `bootstrap.ps1`
- **THEN** `DOT_OS` 等于 `windows`

#### Scenario: 无法识别的系统

- **WHEN** `uname` 返回既非 `Darwin` 也非 `Linux` 的值（如 `FreeBSD`）
- **THEN** 引导程序输出 `unsupported OS: <value>` 并以退出码 `1` 终止
- **AND** 不执行任何模块

### Requirement: CPU 架构识别

系统 SHALL 识别 CPU 架构并导出 `DOT_ARCH`，取值限定为 `arm64` 或 `x86_64`。`aarch64`、`arm64` MUST 归一化为 `arm64`；`x86_64`、`amd64` MUST 归一化为 `x86_64`。

#### Scenario: Apple Silicon

- **WHEN** 在 Apple Silicon Mac 上运行（`uname -m` 返回 `arm64`）
- **THEN** `DOT_ARCH` 等于 `arm64`

#### Scenario: ARM Linux 归一化

- **WHEN** 在 ARM Linux 上运行（`uname -m` 返回 `aarch64`）
- **THEN** `DOT_ARCH` 等于 `arm64`

#### Scenario: x86 归一化

- **WHEN** `uname -m` 返回 `amd64` 或 `x86_64`
- **THEN** `DOT_ARCH` 等于 `x86_64`

### Requirement: Linux 发行版识别

在 `DOT_OS` 为 `linux` 时，系统 SHALL 从 `/etc/os-release` 读取 `ID` 与 `ID_LIKE` 来识别发行版，导出 `DOT_DISTRO`。识别 MUST NOT 依赖 `lsb_release` 命令（该命令不保证存在）。当 `ID` 未知但 `ID_LIKE` 可匹配时，MUST 回退到 `ID_LIKE` 的匹配结果；两者都无法匹配时 `DOT_DISTRO` 为 `unknown`。

#### Scenario: Ubuntu 识别

- **WHEN** `/etc/os-release` 中 `ID=ubuntu`
- **THEN** `DOT_DISTRO` 等于 `ubuntu`

#### Scenario: 衍生发行版回退到 ID_LIKE

- **WHEN** `/etc/os-release` 中 `ID=linuxmint` 且 `ID_LIKE="ubuntu debian"`
- **THEN** `DOT_DISTRO` 等于 `ubuntu`

#### Scenario: os-release 缺失

- **WHEN** `/etc/os-release` 不存在
- **THEN** `DOT_DISTRO` 等于 `unknown`
- **AND** 系统输出一条警告但继续执行

### Requirement: 包管理器识别

系统 SHALL 识别可用的包管理器并导出 `DOT_PKG`，取值限定为 `brew`、`apt`、`dnf`、`pacman`、`apk`、`winget`、`scoop` 之一。macOS 上 MUST 优先选 `brew`；Linux 上 MUST 按发行版选择对应管理器，若 Homebrew/Linuxbrew 存在则 MAY 优先用于无系统包的工具；Windows 上 CLI 工具 MUST 优先 `scoop`、系统级应用 MUST 用 `winget`。当目标平台上找不到任何受支持的包管理器时，系统 MUST 报错终止。

#### Scenario: macOS 选择 brew

- **WHEN** 在 macOS 上运行且 `brew` 已安装
- **THEN** `DOT_PKG` 等于 `brew`

#### Scenario: macOS 缺少 brew 时自动安装

- **WHEN** 在 macOS 上运行且 `brew` 未安装
- **THEN** 系统提示并安装 Homebrew
- **AND** 安装后 `DOT_PKG` 等于 `brew`

#### Scenario: Debian 系选择 apt

- **WHEN** `DOT_DISTRO` 为 `debian` 或 `ubuntu`
- **THEN** `DOT_PKG` 等于 `apt`

#### Scenario: Arch 选择 pacman

- **WHEN** `DOT_DISTRO` 为 `arch`
- **THEN** `DOT_PKG` 等于 `pacman`

#### Scenario: 无受支持的包管理器

- **WHEN** `DOT_OS` 为 `linux` 且 `apt`、`dnf`、`pacman`、`apk`、`brew` 均不可用
- **THEN** 系统输出 `no supported package manager found` 并以退出码 `1` 终止

### Requirement: Homebrew 前缀探测

系统 SHALL 探测 Homebrew 的实际安装前缀并导出 `DOT_BREW_PREFIX`，MUST NOT 硬编码任何路径。探测顺序为：`brew --prefix` 的输出优先；不可用时按 `/opt/homebrew`、`/usr/local`、`/home/linuxbrew/.linuxbrew` 依次探测。

#### Scenario: Apple Silicon 前缀

- **WHEN** 在 Apple Silicon Mac 上 Homebrew 安装于 `/opt/homebrew`
- **THEN** `DOT_BREW_PREFIX` 等于 `/opt/homebrew`

#### Scenario: Intel Mac 前缀

- **WHEN** 在 Intel Mac 上 Homebrew 安装于 `/usr/local`
- **THEN** `DOT_BREW_PREFIX` 等于 `/usr/local`

#### Scenario: Linuxbrew 前缀

- **WHEN** 在 Linux 上 Linuxbrew 安装于 `/home/linuxbrew/.linuxbrew`
- **THEN** `DOT_BREW_PREFIX` 等于 `/home/linuxbrew/.linuxbrew`

#### Scenario: Homebrew 未安装

- **WHEN** 系统上不存在 Homebrew
- **THEN** `DOT_BREW_PREFIX` 为空字符串
- **AND** 依赖 brew 的模块被跳过并记录原因

### Requirement: WSL 环境识别

系统 SHALL 通过 `/proc/sys/kernel/osrelease` 或 `/proc/version` 中是否含 `microsoft`（大小写不敏感）判断是否运行在 WSL 中，并导出 `DOT_WSL` 为 `1` 或 `0`。`DOT_WSL` 为 `1` 时，字体类模块 MUST 被跳过（字体由 Windows 宿主机提供）。

#### Scenario: WSL2 内运行

- **WHEN** 在 WSL2 的 Ubuntu 中执行 `bootstrap.sh`
- **THEN** `DOT_OS` 等于 `linux` 且 `DOT_WSL` 等于 `1`

#### Scenario: WSL 内跳过字体安装

- **WHEN** `DOT_WSL` 等于 `1` 且字体模块被列入执行计划
- **THEN** 字体模块被跳过
- **AND** 输出提示说明字体应在 Windows 宿主机安装

#### Scenario: 原生 Linux

- **WHEN** 在物理 Linux 机器上运行
- **THEN** `DOT_WSL` 等于 `0`

### Requirement: 无图形环境识别

系统 SHALL 识别当前是否处于无图形/非交互环境并导出 `DOT_HEADLESS`。当 `$SSH_CONNECTION` 非空、`$CI` 非空、或 `/.dockerenv` 存在时，`DOT_HEADLESS` MUST 为 `1`。`DOT_HEADLESS` 为 `1` 时，GUI 应用与字体类模块 MUST 被跳过。

#### Scenario: SSH 会话中

- **WHEN** 通过 SSH 登录后执行 `bootstrap.sh`
- **THEN** `DOT_HEADLESS` 等于 `1`
- **AND** GUI 应用与字体模块被跳过

#### Scenario: CI 环境中

- **WHEN** 环境变量 `CI` 被设置为任意非空值
- **THEN** `DOT_HEADLESS` 等于 `1`

#### Scenario: 容器内

- **WHEN** `/.dockerenv` 文件存在
- **THEN** `DOT_HEADLESS` 等于 `1`

#### Scenario: 本地图形环境

- **WHEN** 在本地终端直接运行且无 SSH/CI/容器标志
- **THEN** `DOT_HEADLESS` 等于 `0`

### Requirement: 探测结果可查询

系统 SHALL 提供 `bootstrap.sh --info`（及 `bootstrap.ps1 -Info`）打印全部探测结果，供用户与 CI 验证平台识别是否正确。该命令 MUST NOT 修改任何文件。

#### Scenario: 打印探测结果

- **WHEN** 用户执行 `./bootstrap.sh --info`
- **THEN** 输出包含 `DOT_OS`、`DOT_ARCH`、`DOT_DISTRO`、`DOT_PKG`、`DOT_WSL`、`DOT_HEADLESS`、`DOT_BREW_PREFIX` 的当前取值
- **AND** 文件系统与 `$HOME` 未发生任何变更

### Requirement: 模块代码不直接探测平台

模块实现（`modules/*/module.sh`）MUST NOT 直接调用 `uname`、读取 `/etc/os-release`、或以其他方式自行判断平台；MUST 只使用 `lib/detect.sh` 导出的 `DOT_*` 变量与 `platform/` 层提供的函数。

#### Scenario: 静态检查禁止直接探测

- **WHEN** CI 对 `modules/` 目录执行平台探测调用的静态检查
- **THEN** 任何 `modules/*/module.sh` 中出现 `uname` 或 `/etc/os-release` 的引用都使检查失败
