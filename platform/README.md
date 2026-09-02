# platform/

平台适配层。把"某个平台上怎么做"收敛在这里，使 `modules/` 里的代码不出现任何平台判断。

| 文件 | 平台 |
|---|---|
| `macos.sh` | macOS —— Homebrew、`~/Library/Fonts` |
| `linux.sh` | Linux / WSL —— apt / dnf / yum / pacman / apk / zypper、`~/.local/share/fonts` + `fc-cache` |
| `windows.ps1` | Windows 原生 —— scoop 优先 / winget 兜底、用户字体注册表、PowerShell profile 路径 |

## 每个平台文件需要提供

- `dot_platform_pkg_install <logical-name>` —— 安装单个包
- `dot_platform_pkg_name <logical-name>` —— 逻辑名到本平台包名的映射
- `dot_platform_font_dir` —— 用户级字体目录
- `dot_platform_font_refresh` —— 字体缓存刷新（无需刷新的平台留空实现）

## 约定

- 模块只调 `dot_pkg_install ripgrep`，不关心背后是 brew 还是 apt。
- 逻辑名到包名的映射表放在这里，不放在模块或清单里 —— 清单只出现跨平台的逻辑名。
- 某工具在本平台不可用时，映射返回空，由 `lib/pkg.sh` 走回退安装链。
- RHEL 族的包名对 `dnf` 与 `yum` 是同一套，映射表里两者总是并列（`dnf | yum`）。
  漏写 `yum` 不会报错 —— 映射返回空串，回退链当作「仓库里没这个包」转去 cargo
  现场编译。`test/lint.sh` 有一条交叉断言拦这个。
- 「包名一致」不等于「可用性一致」：`github-cli` 在 Fedora 仓库里有，
  RHEL/CentOS 的 base 与 EPEL 都没有。这类刻意的例外用 `# yum-differs:`
  注释标注 —— 要求写注释而不是默许，是为了区分「想清楚了」和「忘了加」。
- RHEL 族安装前会自动启用 EPEL：base 仓库里没有 ripgrep/fd/bat/zoxide/
  delta/direnv/duf，不启用的话默认集 14 个有 7 个装不到。
  `DOT_NO_EPEL=1` 可关掉（离线环境、或内部镜像已自带这些包）。
