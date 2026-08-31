# 从旧版 dotfiles 升级

针对已经在用旧 `private/install.sh` 的机器。

## 一句话

```sh
cd ~/lab/dotfiles && git pull
./bootstrap.sh --dry-run    # 看清将替换哪些文件
./bootstrap.sh
```

原有配置**不会被销毁** —— 全部先移到 `~/.dotfiles-backup/<时间戳>/`。

## 变了什么

| 旧 | 新 |
|---|---|
| `private/install.sh <task>` | `./bootstrap.sh [--only <module>]` |
| 任务名如 `zsh_omz`、`fonts_source_code_pro` | 模块名，用 `--list` 查看 |
| `usage()` 里手写的任务清单 | 由 `modules/` 目录自动发现 |
| 直接 `rm -rf` 目标再建链接 | 先备份到 `~/.dotfiles-backup/` |
| 无预演 | `--dry-run` |
| Source Code Pro | JetBrainsMono Nerd Font + Maple Mono NF |
| omz 与 zim 两套并行 | 只保留 omz，prompt 换 starship |
| 24 个 git submodule/gitlink | 全部移除，`git clone` 不再需要 `--recurse-submodules` |
| Travis CI | GitHub Actions |

旧脚本本身归档在 `legacy/private/install.sh`，需要对照时可查。

## 会被替换的 $HOME 文件

`--dry-run` 会逐条列出。典型的有：

- `~/.zshrc` → 链接到 `config/zsh/zshrc`
- `~/.zshrc.d` → 链接到 `config/zsh/zshrc.d`
- `~/.zshenv` → 写入 `DOTFILES` 路径
- `~/.gitconfig` → 链接到 `config/git/gitconfig`
- `~/.gitignore_global` → 链接到 `config/git/gitignore_global`
- `~/.claude/{agents,skills,commands,hooks}` → 链接到 `config/ai/*`
- `~/.claude/settings.json`、`~/.claude/.mcp.json` → 渲染生成

每个被替换的**真实文件**（不是符号链接）都会先进备份目录，保留原本的
相对路径 —— 例如 `~/.config/starship/config.toml` 会出现在
`~/.dotfiles-backup/<时间戳>/.config/starship/config.toml`。

## git 身份需要注意

旧配置把 `user.name` / `user.email` 直接写在 `~/.gitconfig` 里。
新结构的 `~/.gitconfig` 是指向仓库的符号链接（公开仓库不能放邮箱），
身份改放在**不入库的** `~/.gitconfig.local`。

升级时：

- 已有身份会被识别为「已设置」，引导不会重复询问；
- 但如果身份只存在于被替换的那个 `~/.gitconfig` 里，你需要从备份里取回：

```sh
grep -A2 '\[user\]' ~/.dotfiles-backup/*/.gitconfig
git config --file ~/.gitconfig.local user.name 'Your Name'
git config --file ~/.gitconfig.local user.email you@example.com
```

## 恢复

要退回旧状态：

```sh
# 找到最近一次备份
ls -t ~/.dotfiles-backup/ | head -1

# 逐个取回需要的文件（先删掉新建的符号链接）
rm ~/.zshrc
cp ~/.dotfiles-backup/<时间戳>/.zshrc ~/.zshrc
```

旧的安装脚本仍可从归档里运行（但它已不再维护）：

```sh
sh legacy/private/install.sh
```

## 已知的行为变化

- **prompt 变了**：从 omz 主题换成 starship。配置在 `config/starship.toml`，
  starship 未安装时会回退到 omz 主题。
- **`ls` 变成 `eza`**（仅交互式 shell）。脚本里的 `ls` 不受影响。
- **`cat` 没有被替换** —— bat 的别名是 `bcat`，避免破坏管道用法。
- **历史文件位置**：`HISTFILE` 现在明确指向 `~/.zsh_history`。旧配置里
  有一份用 `~/.zhistory` 的，那份历史不会自动合并。
- **fzf 键位绑定**需要 fzf ≥ 0.48（旧版没有 `--zsh`）。引导会检测并提示
  PATH 里的陈旧副本。

## 遇到问题

```sh
./bootstrap.sh --info      # 平台探测结果是否正确
./bootstrap.sh --list      # 模块是否都被发现、是否适用于本机
bin/dot-bench              # zsh 启动是否超预算
sh test/run_all.sh         # 断言测试是否通过
```
