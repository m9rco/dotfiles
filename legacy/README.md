# legacy/

历史资产归档。**这里的内容不参与安装，不会被模块发现。**

保留在库内是为了可查阅 —— 需要对照旧配置确认某项设置的原始意图时能找到。

## legacy/private/

整个旧 `private/` 目录原样归档（`git mv`，43 个文件，内容与迁移前逐字节一致）。

| 内容 | 说明 | 新结构里的对应物 |
|---|---|---|
| `install.sh` | 旧的单体安装脚本，1200+ 行、~50 个 `install_*` 函数 | `bootstrap.sh` + `modules/*/` |
| `zsh/` | oh-my-zsh 与 zim 两套并行配置 | `config/zsh/`（只保留 omz 一套） |
| `zshrc/` | 更早的一份 zshrc，含硬编码他人主目录路径 | 同上 |
| `zshrc/robbyrussell.zsh-theme` | 名字沿用 omz 主题但内容已被改过的自定义 prompt（🤥 用户名 🍭 时间 ➜） | 观感已用 starship 重建到 `config/starship.toml`（主题文件本身没搬 —— 那只能给 zsh 用，PowerShell 侧就拿不到一致 prompt） |
| `git/` | 旧 gitconfig | `config/git/` |
| `tmux/` | tmux 配置 | 配置未纳入新结构（按需另开 change）；tmux 这个**工具**已进 `config/cli/tools.txt` 默认集 |
| `vim/` | vimrc 与插件清单（插件本身是 gitlink，已移除） | 未纳入新结构 |
| `vscode/`、`VScode.settings.json` | VS Code 设置 | 未纳入新结构 |
| `sublime2/`、`sublime3/` | Sublime Text 2/3 设置 | 已弃用 |
| `workflow/` | Alfred workflow 与 appearance | 已弃用 |
| `CLion2018.3-settings.zip`、`PyCharm2019.1-settings.zip`、`go-landsettings.jar`、`php-stormsettings.jar` | JetBrains 系列的导出设置（2018/2019 年） | 已弃用 |
| `astyle/`、`editorconfig/` | 代码格式化配置 | 未纳入新结构 |
| `terminfo/` | italic 支持的 terminfo 定义 | 未纳入新结构 |
| `bin/` | emacs 的几个小脚本 | 未纳入新结构 |

「未纳入新结构」表示这次重构没有迁移它，但内容仍在这里 ——
需要时可以按新的模块格式重新引入（见 `modules/README.md`）。

## 为什么整体归档而不是逐文件搬迁

旧 `private/` 里的内容质量参差：`private/zshrc/.zshrc` 有硬编码的他人主目录
路径、source 一个不存在的目录、还有早已过期的语言版本 PATH 条目。逐文件判断
「搬哪些、改哪些」比照着重写更费事，也会让 `config/` 继承一批需要逐行审查的
陈旧内容，且迁移过程中难以分辨某文件是「已迁移待改」还是「已定稿」。

整体归档让旧内容作为参考留下，新 `config/` 从干净状态建立，两者不产生
半迁移的混淆状态。

## 不在这里的东西：git 子模块

原仓库索引里有 **24 个 gitlink**（mode 160000），全部**彻底移除**而非归档：

- **8 个已声明的**（`docker/*`）：`.gitmodules` 里有 URL，内容在
  `m9rco/*` 的独立远端仓库。移除前逐个验证了远端可达 ——
  见 `openspec/changes/archive/2026-09-02-modernize-dotfiles/notes/submodule-removal.md`。
- **16 个孤立 gitlink**：索引里是子模块但 `.gitmodules` 里没有条目，
  即仓库从未记录它们来自哪里。包括 11 个 vim 插件、`lib/dotfiles`、
  以及几个 `.cache` 目录。

实测这 24 个 gitlink **全都从未被初始化**（`.git/modules/` 为空，
对应目录在磁盘上都是空的），所以移除它们没有丢失任何本仓库曾提供过的内容。
vim 插件改为由插件管理器按需拉取。

## 归档内容不受新规范约束

`legacy/` 被排除在 lint 检查与 gitleaks 扫描之外（见 `test/lint.sh` 与
`.gitleaks.toml`）—— 按新规范去改归档内容会破坏「归档即原样」这个前提。
