# 子模块移除前的远端存在性确认

生成时间：2026-08-31 19:20:21 +0800
生成命令：`sh test/verify_submodule_remotes.sh`

## 索引中的全部 gitlink（mode 160000）

共 24 个。其中只有部分在 `.gitmodules` 里有声明 ——
其余是「孤立 gitlink」：索引里是子模块，但没有 URL 记录，
`git submodule status` 会直接报错。这类条目无法通过 deinit 处理，
只能用 `git rm --cached` 从索引里移除。

- 索引中的 gitlink：24
- `.gitmodules` 中声明的：8
- 孤立 gitlink：16

## 已声明的子模块（有远端 URL，逐个验证）

| 路径 | 远端 | 远端可达 |
|---|---|---|
| `docker/etcd` | `git@github.com:m9rco/etcd.git` | 是 |
| `docker/alpine` | `git@github.com:m9rco/alpine.git` | 是 |
| `docker/php` | `git@github.com:m9rco/php.git` | 是 |
| `docker/mongodb` | `git@github.com:m9rco/mongodb.git` | 是 |
| `docker/go` | `git@github.com:m9rco/go.git` | 是 |
| `docker/c-cpp` | `git@github.com:m9rco/c-cpp.git` | 是 |
| `docker/metron` | `git@github.com:m9rco/metron.git` | 是 |
| `docker/alpine-nginx-php` | `git@github.com:m9rco/alpine-nginx-php.git` | 是 |

## 孤立 gitlink（无远端记录）

这些路径在索引里是子模块，但 `.gitmodules` 里没有对应条目 ——
意味着仓库从未记录它们来自哪里。它们本就无法被 clone 出内容
（`git clone --recurse-submodules` 会跳过或报错），因此移除它们
不会丢失任何本仓库曾经提供过的东西。

- `lib/dotfiles`
- `private/.cache/source-code-pro`
- `private/sublime3/.cache/markdown-extended`
- `private/sublime3/.cache/monokai-extended`
- `private/vim/autoload`
- `private/vim/plugins/MatchTagAlways`
- `private/vim/plugins/YouCompleteMe`
- `private/vim/plugins/gruvbox`
- `private/vim/plugins/indentLine`
- `private/vim/plugins/molokai`
- `private/vim/plugins/seoul256.vim`
- `private/vim/plugins/ultisnips`
- `private/vim/plugins/vim-airline`
- `private/vim/plugins/vim-colors-solarized`
- `private/vim/plugins/vim-kolor`
- `private/vim/plugins/vim-snippets`

## 上游来源（供需要时自行恢复）

vim 插件均为第三方上游仓库，新结构改为由插件管理器按需拉取，
不再由本仓库携带：

- `MatchTagAlways`
- `YouCompleteMe`
- `gruvbox`
- `indentLine`
- `molokai`
- `seoul256.vim`
- `ultisnips`
- `vim-airline`
- `vim-colors-solarized`
- `vim-kolor`
- `vim-snippets`

结论：已声明的子模块内容均存在于各自远端，可安全移除。
