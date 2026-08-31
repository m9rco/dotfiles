# 别名。
#
# 两条硬约束：
#   1. 只在对应工具存在时定义 —— 否则缺工具的机器上别名会直接报错
#   2. 只在交互式 shell 中生效 —— 脚本里的 ls/cat 必须是原命令，
#      否则依赖其输出格式的脚本会被静默改变行为
#
# zsh 的 alias 本身不会影响非交互式 shell 里的 `ls`（脚本用 sh/bash 跑，
# 或用 zsh -c 时不读 .zshrc），但显式加这道判断能防止 zsh -i 类调用出意外。

if [[ ! -o interactive ]]; then
  return 0
fi

# ---------------------------------------------------------------- 列目录

if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -l --group-directories-first --git'
  alias la='eza -la --group-directories-first --git'
  alias lt='eza --tree --level=2'
  alias tree='eza --tree'
else
  # 回退到系统 ls。BSD 与 GNU 的颜色开关不同名
  if ls --color=auto / >/dev/null 2>&1; then
    alias ls='ls --color=auto --group-directories-first'
  else
    alias ls='ls -G'
  fi
  alias ll='ls -lh'
  alias la='ls -lah'
fi

# ---------------------------------------------------------------- 查看文件
#
# 不覆盖 cat —— cat 会被脚本和管道大量使用，换成 bat 会带来分页与颜色，
# 破坏 `cat file | grep x` 这类用法。用单独的名字。

if (( $+commands[bat] )); then
  alias bcat='bat'
  alias catp='bat --plain'
elif (( $+commands[batcat] )); then
  # Debian/Ubuntu 把可执行文件装成 batcat
  alias bat='batcat'
  alias bcat='batcat'
  alias catp='batcat --plain'
fi

# ---------------------------------------------------------------- 搜索

if (( $+commands[rg] )); then
  alias rgh='rg --hidden --no-ignore'
fi

if (( $+commands[fdfind] )) && ! (( $+commands[fd] )); then
  # Debian/Ubuntu 的 fd-find 装成 fdfind
  alias fd='fdfind'
fi

# ---------------------------------------------------------------- git
#
# 只定义几个最高频的。其余交给 omz 的 git 插件，避免与它冲突。

if (( $+commands[git] )); then
  alias gs='git status --short --branch'
  alias gd='git diff'
  alias gds='git diff --staged'
  alias gl='git log --oneline --graph --decorate -20'
fi

if (( $+commands[lazygit] )); then
  alias lg='lazygit'
fi

# ---------------------------------------------------------------- 杂项

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# 危险操作加确认
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# 快速编辑与重载配置
alias zshrc='${EDITOR} ${DOTFILES}/config/zsh/zshrc'
alias zshreload='exec zsh'
alias dotfiles='cd ${DOTFILES}'

if (( $+commands[jq] )); then
  alias jqc='jq -C'
fi
