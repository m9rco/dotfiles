# vim 插件的处理说明

## 结论

原仓库索引里有 11 个 vim 插件的 gitlink（`private/vim/plugins/*`），
本次重构中**全部移除**，不需要在新结构里替换成别的形式 ——
因为旧配置本来就已经用 vim-plug 声明式管理插件了。

## 证据

`legacy/private/vim/vimrc.plugins` 里是一份完整的 vim-plug 清单：

```vim
Plug 'tomasr/molokai'
Plug 'altercation/vim-colors-solarized'
Plug 'morhetz/gruvbox'
Plug 'junegunn/seoul256.vim'
Plug 'vim-airline/vim-airline'
Plug 'Yggdroot/indentLine'
...
```

也就是说：插件的真实来源一直是这份清单，vim-plug 在运行时按它拉取。
`private/vim/plugins/` 下的 11 个 gitlink 是**冗余的历史残留**：

- 它们从未被初始化（`.git/modules/` 为空，目录在磁盘上都是空的）
- `.gitmodules` 里没有它们的条目，所以连 URL 都没记录
- `git clone --recurse-submodules` 拉不出任何内容

移除它们不改变任何实际行为。

## vim 本身不在新结构里

`config/` 下没有 vim 配置 —— 这次重构的范围是 zsh / 字体 / 现代 CLI /
AI 工具链 / 密钥（见 proposal 的 Capabilities）。vim 配置留在
`legacy/private/vim/` 可查阅，需要时按 `modules/README.md` 的格式
新增一个 vim 模块即可，届时：

- 配置文件放 `config/vim/`
- `vimrc.plugins` 那份 vim-plug 清单可以直接复用
- 模块负责装 vim、link 配置、并首次运行 `:PlugInstall`

不在本次 change 里做，是因为把它做好需要先决定用 vim 还是 neovim、
用 vim-plug 还是 lazy.nvim —— 那是独立的决策，不该塞进这次重构。
