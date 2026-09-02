## ADDED Requirements

### Requirement: 彻底移除全部 git 子模块

系统 SHALL 移除仓库内全部 git 子模块（`docker/` 下 8 个、`private/vim/plugins/` 下 11 个），并删除 `.gitmodules` 文件。移除 MUST 完整执行三步：`git submodule deinit` 解除初始化、`git rm` 从索引与工作区移除、清理 `.git/modules/<path>` 下的残留元数据，MUST NOT 留下半移除状态。移除后仓库 MUST NOT 再使用 git submodule 机制。

#### Scenario: 全部子模块被移除

- **WHEN** 迁移完成后执行 `git submodule status`
- **THEN** 输出为空，没有任何子模块被列出

#### Scenario: .gitmodules 被删除

- **WHEN** 迁移完成后检查仓库根目录
- **THEN** `.gitmodules` 文件不存在

#### Scenario: git 内部元数据被清理

- **WHEN** 迁移完成后检查 `.git/modules/`
- **THEN** 不存在任何已移除子模块的残留目录

#### Scenario: 全新克隆不拉取子模块

- **WHEN** 对迁移后的仓库执行 `git clone --recurse-submodules`
- **THEN** 没有子模块被拉取
- **AND** 克隆正常完成

#### Scenario: 移除前确认远端留存

- **WHEN** 移除某个 docker 子模块之前
- **THEN** 已确认其内容存在于对应的独立远端仓库
- **AND** 该确认结果被记录在迁移说明中

### Requirement: vim 插件改由插件管理器管理

原先以子模块形式携带的 vim 插件 SHALL 改为由 vim 插件管理器在运行时按需拉取。插件清单 MUST 以声明式形式存在于配置中，仓库 MUST NOT 携带任何插件源码。

#### Scenario: 仓库不含插件源码

- **WHEN** 检查仓库中的 vim 相关目录
- **THEN** 不存在任何第三方插件的源码副本

#### Scenario: 插件清单声明式存在

- **WHEN** 检查 vim 配置
- **THEN** 原有插件以声明式清单形式列出，可由插件管理器拉取

### Requirement: private 目录整体归档

系统 SHALL 把整个 `private/` 目录原样归档为 `legacy/private/`，MUST 使用 `git mv` 以保留 git 的重命名追溯。归档 MUST 是整体搬迁而非逐文件挑选，归档后的内容 MUST 与迁移前逐字节一致（含旧 `install.sh`、Sublime Text 2/3 配置、Alfred workflow、JetBrains 设置、astyle 配置、emacs 脚本、terminfo 定义、旧版 zshrc）。`legacy/` 下的内容 MUST NOT 被任何模块发现或安装，且 MUST 附带说明文件解释归档原因与状态。

#### Scenario: private 整体搬入 legacy

- **WHEN** 迁移完成后检查 `legacy/private/`
- **THEN** 原 `private/` 下的全部内容存在于其中
- **AND** 内容与迁移前逐字节一致

#### Scenario: 旧 install.sh 随之归档

- **WHEN** 迁移完成后查找旧的安装脚本
- **THEN** 它位于 `legacy/private/install.sh`
- **AND** 仓库根与 `modules/` 下不存在该脚本的副本

#### Scenario: 使用 git mv 保留历史

- **WHEN** 执行归档搬迁
- **THEN** 使用 `git mv` 以便 git 能追溯目录重命名历史

#### Scenario: legacy 不参与安装

- **WHEN** 执行 `./bootstrap.sh --list`
- **THEN** 输出中不包含任何来自 `legacy/` 的模块

#### Scenario: legacy 附带说明

- **WHEN** 检查 `legacy/` 目录
- **THEN** 存在说明文件解释归档原因、内容清单与各资产的状态

### Requirement: 新配置为重写而非搬迁

`config/` 下的配置文件 SHALL 参照 `legacy/private/` 的内容重写，MUST NOT 从 `private/` 直接移动而来。重写 MUST 清除旧内容中的机器专属残留：硬编码的他人主目录绝对路径、指向不存在位置的 source 语句、以及已过期的版本化 PATH 条目。

#### Scenario: 无硬编码他人主目录

- **WHEN** 检索 `config/` 下所有文件
- **THEN** 不存在硬编码的他人主目录绝对路径

#### Scenario: 无指向不存在位置的 source

- **WHEN** 在全新环境中启动 shell
- **THEN** 没有因 source 不存在的文件而产生的错误输出

#### Scenario: 无过期版本化 PATH

- **WHEN** 检查 `config/` 下的 PATH 相关配置
- **THEN** 不存在指向已过期语言版本的硬编码路径条目

#### Scenario: 旧内容仍可查阅

- **WHEN** 需要对照旧配置确认某项设置的原始意图
- **THEN** 对应文件可在 `legacy/private/` 下找到

### Requirement: 旧安装脚本退出使用

系统 SHALL 在所有模块迁移完成并验证后，让旧安装逻辑退出使用：`private/install.sh` 随 `private/` 整体归档到 `legacy/private/install.sh`（保留可查阅），`lib/utils.sh` 的旧副本 MUST 被删除（其所需函数已在新 `lib/` 中重写）。退出使用 MUST 发生在新引导程序能覆盖等价功能之后，MUST NOT 在迁移中途留下两套都不可用的状态。

#### Scenario: 旧脚本不再位于原路径

- **WHEN** 迁移完成后检查仓库
- **THEN** `private/install.sh` 不存在于原路径
- **AND** 其内容可在 `legacy/private/install.sh` 找到

#### Scenario: 旧 utils 副本被删除

- **WHEN** 迁移完成后检查仓库根的 `lib/`
- **THEN** 不存在旧的 `utils.sh` 副本
- **AND** 新 `lib/` 下的函数由本次重写提供

#### Scenario: 退出时机在功能覆盖之后

- **WHEN** 旧脚本退出使用的那次提交之前
- **THEN** 新引导程序已能完成等价的安装功能
- **AND** 已通过 dry-run 与实机验证

### Requirement: 目录结构重排

系统 SHALL 建立按职责划分的顶层结构：`config/`（被链接的配置文件）、`modules/`（安装逻辑）、`platform/`（平台适配）、`lib/`（共享函数）、`legacy/`（归档）。迁移完成后顶层 `private/` 目录 MUST 不再存在（其内容位于 `legacy/private/`）。配置内容与安装逻辑 MUST NOT 混在同一目录。

#### Scenario: 顶层 private 消失

- **WHEN** 迁移完成后检查仓库根目录
- **THEN** 顶层 `private/` 目录不存在
- **AND** `legacy/private/` 存在

#### Scenario: 配置与逻辑分离

- **WHEN** 检查 `config/` 目录
- **THEN** 其中只有被链接的配置文件，不包含安装脚本

#### Scenario: 模块目录只含逻辑

- **WHEN** 检查 `modules/` 目录
- **THEN** 其中只有安装逻辑，配置内容通过引用 `config/` 获得

### Requirement: 分阶段可用性

迁移 SHALL 分阶段进行，每个阶段结束后仓库 MUST 处于可用状态：新骨架先与旧脚本并存，模块逐个迁移并验证，最后才移除旧脚本与归档资产。任何单次提交后 MUST NOT 出现"新旧都不可用"的状态。

#### Scenario: 骨架阶段旧脚本仍可用

- **WHEN** 新的 `lib/`、`platform/`、`bootstrap.sh` 骨架已加入但模块尚未迁移
- **THEN** 旧的安装方式仍然可用

#### Scenario: 每阶段后仓库可用

- **WHEN** 检出迁移过程中任意一次提交
- **THEN** 至少有一套安装方式可正常工作

### Requirement: CI 从 Travis 迁移到 GitHub Actions

系统 SHALL 删除 `.travis.yml` 并新增 GitHub Actions 工作流，在 macOS、Ubuntu 与 Windows runner 上执行静态检查与预演冒烟测试：shell 脚本经 shellcheck（以 POSIX sh 模式）与 shfmt 检查，PowerShell 脚本经 PSScriptAnalyzer 检查，并在各平台执行 `--dry-run` 与 `--list`。此外 SHALL 有一个最小 Linux 容器 job 执行真实安装，以验证不隐式依赖 GNU 扩展或预装工具。

#### Scenario: Travis 配置被删除

- **WHEN** 迁移完成后检查仓库
- **THEN** `.travis.yml` 不存在

#### Scenario: 三平台矩阵运行

- **WHEN** CI 被触发
- **THEN** macOS、Ubuntu 与 Windows 三个 job 都被执行

#### Scenario: POSIX 兼容性被强制

- **WHEN** 某个 shell 脚本使用了 bash 专有语法
- **THEN** shellcheck 检查失败
- **AND** CI 报告失败

#### Scenario: 容器内真实安装验证

- **WHEN** 最小 Linux 容器 job 运行
- **THEN** 引导程序在 `/bin/sh` 为 dash 的环境中完成真实安装
- **AND** 未因缺少预装工具而失败

#### Scenario: 预演冒烟通过

- **WHEN** 各平台 job 执行 `--dry-run` 与 `--list`
- **THEN** 命令以退出码 `0` 结束

### Requirement: 既有用户升级路径

系统 SHALL 提供从旧结构升级到新结构的说明，明确列出：需要重新执行的引导命令、会被替换的 `$HOME` 下配置文件、以及备份文件的位置。升级过程 MUST 保留用户原有配置的备份。

#### Scenario: 升级说明可获得

- **WHEN** 用户查看仓库文档
- **THEN** 存在从旧结构升级的步骤说明

#### Scenario: 升级时原配置被备份

- **WHEN** 在使用旧版 dotfiles 的机器上执行新引导
- **THEN** 原有的 `$HOME` 配置文件被移动到备份目录
- **AND** 输出指明备份的具体位置

### Requirement: 文档更新

系统 SHALL 重写 `README.md` 以反映新结构：三平台安装方式、模块清单的获取方式、目录结构说明、以及 `legacy/` 的定位。README MUST NOT 保留已失效的旧用法说明（含基于 git submodule 的使用步骤）。

#### Scenario: README 反映新用法

- **WHEN** 阅读迁移后的 `README.md`
- **THEN** 其中描述的是 `bootstrap.sh` / `bootstrap.ps1` 的安装方式

#### Scenario: 旧用法被移除

- **WHEN** 检索 `README.md`
- **THEN** 不存在 `git submodule add` 等基于子模块的使用步骤

#### Scenario: 模块清单不在文档中硬编码

- **WHEN** 阅读 README 中关于可用模块的部分
- **THEN** 它指向 `--list` 命令而非硬编码的模块名列表
