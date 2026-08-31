# lib/

新引导程序的共享函数库。全部为 POSIX sh，可在 `dash` 下执行。

| 文件 | 职责 |
|---|---|
| `log.sh` | 统一日志输出（`dot_step` / `dot_info` / `dot_success` / `dot_error` / `dot_tip`），非 TTY 时自动禁用颜色 |
| `detect.sh` | 平台探测，导出 `DOT_OS` / `DOT_ARCH` / `DOT_DISTRO` / `DOT_PKG` / `DOT_WSL` / `DOT_HEADLESS` / `DOT_BREW_PREFIX` |
| `fs.sh` | 幂等的文件系统原语（`dot_link` 链接前备份、`dot_mkdir`），全部尊重 dry-run |
| `pkg.sh` | `dot_pkg_install` 抽象，按 `DOT_PKG` 转发到 `platform/` 层，含回退安装链 |
| `runner.sh` | 模块发现、校验、依赖拓扑排序、执行与汇总 |

## 约定

- **只用 POSIX sh**：不用 `[[ ]]`、数组、`echo -e`、`function` 关键字。
- `local` 是唯一的例外：它不在 POSIX 中，但所有真实使用的 sh（dash / ash / busybox / bash / zsh / ksh）都支持。相关文件顶部用 `# shellcheck disable=SC3043` 说明。
- 所有函数与全局变量以 `dot_` / `DOT_` 前缀命名，避免被 source 时污染调用者。
- 每个文件都有重复 source 保护。
- **任何写操作都必须经过 `fs.sh` 的原语**，不要在模块里直接 `rm` / `ln` / `mv`，否则会绕过备份与 dry-run。

`utils.sh` 是旧安装脚本的遗留副本，将在迁移收尾时删除（见 tasks 10.6）。
