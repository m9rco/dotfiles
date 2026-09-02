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
  # 注意 --group-directories-first 与 --group 是两回事：前者是排序（目录排在
  # 前面），后者才是「显示组名那一列」。eza 默认不显示组，而 ls -l 一直显示 ——
  # 只看名字很容易以为前者已经覆盖了后者，于是长格式里静静少了一列。
  #
  # -h 让大小带单位，与旧配置的 ls -lh 对齐。
  #
  # 配色：eza 默认给权限位逐位上色（r 黄 w 红 x 绿）、大小与日期也各自上色，
  # 一行里七八种颜色，扫一眼找文件名反而更慢。这里把元数据列压成素色，只让
  # 文件名保留类型色（目录/可执行/软链接），接近 ls 的观感。
  #
  # 键名取自 eza 自己的 man eza_colors：
  #   ur/uw/ux gr/gw/gx tr/tw/tx = 权限位的九个格子
  #   sn/sb = 大小的数字与单位   da = 日期
  #   uu/un/uR = 用户名列（你自己 / 别人 / root）
  #   gu/gn/gR = 组名列（你所属的组 / 你不属于的组 / root 相关）
  # 用户名与组名要把三种情形都列上：只设 uu/gu 的话，像 wheel 这种你不属于
  # 的组会漏掉，一行里就剩它一个亮色，比全亮更扎眼。
  # 值是 ANSI SGR 码，2 是 dim。
  #
  # 用 ${EZA_COLORS:-...} 而不是直接赋值：已经设过的（比如在 ~/.zshenv 或
  # 上游 profile 里）保持原样。想整体换配色就在 ~/.zshrc.local 里重设，
  # 那个文件由 90-local.zsh 最后加载，覆盖这里。
  export EZA_COLORS="${EZA_COLORS:-ur=2:uw=2:ux=2:ue=2:gr=2:gw=2:gx=2:tr=2:tw=2:tx=2:sn=2:sb=2:da=2:uu=2:un=2:uR=2:gu=2:gn=2:gR=2}"

  alias ls='eza --group-directories-first'
  alias ll='eza -lh --group --group-directories-first --git'
  alias la='eza -lah --group --group-directories-first --git'
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
