# lib/

新引导程序的共享函数库。全部为 POSIX sh，可在 `dash` 下执行。

| 文件 | 职责 |
|---|---|
| `log.sh` | 统一日志输出（`dot_step` / `dot_info` / `dot_success` / `dot_error` / `dot_tip`），非 TTY 时自动禁用颜色 |
| `detect.sh` | 平台探测，导出 `DOT_OS` / `DOT_ARCH` / `DOT_DISTRO` / `DOT_PKG` / `DOT_WSL` / `DOT_HEADLESS` / `DOT_BREW_PREFIX` |
| `fs.sh` | 幂等的文件系统原语（`dot_link` 链接前备份、`dot_mkdir`），全部尊重 dry-run |
| `download.sh` | 下载与归档原语（`dot_dl_fetch` / `dot_dl_verify` / `dot_dl_unzip` / `dot_dl_untar` / `dot_dl_find_file` / `dot_dl_describe`），curl 与 wget 二选一 |
| `release.sh` | 从项目自己的 GitHub release 取预编译二进制：解析最新 tag、按平台选资产、解包后装进 `~/.local/bin` |
| `pkg.sh` | `dot_pkg_install` 抽象，按 `DOT_PKG` 转发到 `platform/` 层，含回退安装链 |
| `runner.sh` | 模块发现、校验、依赖拓扑排序、执行与汇总 |

## 约定

- **只用 POSIX sh**：不用 `[[ ]]`、数组、`echo -e`、`function` 关键字。
- `local` 是唯一的例外：它不在 POSIX 中，但所有真实使用的 sh（dash / ash / busybox / bash / zsh / ksh）都支持。相关文件顶部用 `# shellcheck disable=SC3043` 说明。
- 所有函数与全局变量以 `dot_` / `DOT_` 前缀命名，避免被 source 时污染调用者。
- 每个文件都有重复 source 保护。
- **任何写操作都必须经过 `fs.sh` 的原语**，不要在模块里直接 `rm` / `ln` / `mv`，否则会绕过备份与 dry-run。
  - 唯一的例外是往 `~/.local/bin` 装可执行文件（`pkg.sh` 的 `script:` 与 `release.sh` 的 `github:` 两条回退）。`dot_write` 读 stdin、把旧文件备份进 `~/.dotfiles-backup/`、并 chmod 644 —— 每次升级把一个十几 MB 的二进制备份进配置备份目录是 bug 不是特性，而 644 的二进制根本没法执行。那两处用「先写临时名再 `mv`」保证原子性，理由写在代码注释里。

`utils.sh` 是旧安装脚本的遗留副本，将在迁移收尾时删除（见 tasks 10.6）。
