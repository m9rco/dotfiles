# platform/

平台适配层。把"某个平台上怎么做"收敛在这里，使 `modules/` 里的代码不出现任何平台判断。

| 文件 | 平台 |
|---|---|
| `macos.sh` | macOS —— Homebrew、`~/Library/Fonts` |
| `linux.sh` | Linux / WSL —— apt / dnf / pacman / apk、`~/.local/share/fonts` + `fc-cache` |
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
