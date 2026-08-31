# 补全初始化与缓存。
#
# compinit 全量扫描补全定义要几十毫秒，是 zsh 启动最大的可优化项。
#
# 注意加载顺序：本片段在 20-omz.zsh **之后**，而 oh-my-zsh 自己就会跑
# compinit。omz 的实现已经做对了该做的事 —— 尊重预设的 $ZSH_COMPDUMP、
# 在 fpath 或 omz 版本变化时删掉 dump 重建、并用 zrecompile 生成 .zwc。
# 所以这里不再自己跑一遍 compinit（那样会产生两份互不相干的缓存，
# 我们的失效判断还会作用在实际没被使用的那份上）。
#
# 分工：
#   - omz 存在  -> 由 omz 负责 compinit，本片段只做补全样式
#   - omz 不存在 -> 本片段自己带缓存地跑 compinit
#
# dump 文件名由 20-omz.zsh 在 source omz 之前设定（见那里的 ZSH_COMPDUMP）。

if ! typeset -f compdef >/dev/null 2>&1; then
  # compdef 由 compinit 定义；不存在说明 omz 没跑过 compinit
  autoload -Uz compinit

  typeset -g _dot_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"

  # 一天内已初始化过就走快路径：-C 跳过安全检查与重新扫描。
  # glob 限定符 mh-24 = 修改时间在 24 小时内。
  if [[ -n ${_dot_zcompdump}(#qN.mh-24) ]]; then
    compinit -C -d "$_dot_zcompdump"
  else
    compinit -d "$_dot_zcompdump"
    # 重新 dump 后编译成字节码，下次启动直接读 .zwc
    if [[ -s "$_dot_zcompdump" ]]; then
      zcompile -R -- "${_dot_zcompdump}.zwc" "$_dot_zcompdump" 2>/dev/null
    fi
  fi

  unset _dot_zcompdump
fi

# ---------------------------------------------------------------- 补全样式

# 菜单式选择，方向键可移动
zstyle ':completion:*' menu select

# 大小写不敏感 + 下划线/连字符互换
zstyle ':completion:*' matcher-list 'm:{a-zA-Z-_}={A-Za-z_-}' 'r:|=*' 'l:|=* r:|=*'

# 补全结果按组显示并带描述
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'

# 用 LS_COLORS 给文件名补全上色
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# 补全缓存（对 apt/brew 这类需要查询包列表的补全提速明显）
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# kill 的补全直接列进程
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

# ---------------------------------------------------------------- 编辑器行为

# 允许在补全菜单里用 TAB 循环
setopt AUTO_MENU
# 词中间也能补全
setopt COMPLETE_IN_WORD
# 光标移到词尾再补全
setopt ALWAYS_TO_END
# 目录名后自动加 /
setopt AUTO_PARAM_SLASH
# glob 无匹配时保留原样而不是报错（粘贴含 * 的命令时少踩坑）
setopt NO_NOMATCH
