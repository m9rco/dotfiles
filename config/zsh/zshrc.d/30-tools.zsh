# 现代 CLI 工具的 shell 集成。
#
# 每个工具都先查 $commands 再初始化 —— 缺失的工具既不报错也不拖慢启动。
# $commands 是 zsh 内建的命令哈希表，比 command -v 快（不 fork 子进程）。

# ---------------------------------------------------------------- starship
#
# prompt 的真源是仓库里的 config/starship.toml，zsh 与 PowerShell 共用同一份。
# starship 缺失时不做任何事，prompt 回退到 20-omz.zsh 里设置的 omz 主题。

if (( $+commands[starship] )); then
  export STARSHIP_CONFIG="${DOTFILES}/config/starship.toml"
  eval "$(starship init zsh)"
fi

# ---------------------------------------------------------------- zoxide
#
# 智能目录跳转。用 z 作为命令名，与旧 omz z 插件的肌肉记忆一致。

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh --cmd z)"
fi

# ---------------------------------------------------------------- fzf
#
# 键位绑定（Ctrl-R 历史、Ctrl-T 文件、Alt-C 目录）与补全。
# fzf 0.48+ 提供 `fzf --zsh` 一次性加载；旧版回退到查找 shell 脚本。

if (( $+commands[fzf] )); then
  # fzf 0.48+ 提供 `fzf --zsh` 一次性输出补全与键位绑定。
  # 旧版本（如系统里遗留的 0.41）没有这个开关，需要去找它自带的 shell 脚本。
  if fzf --zsh >/dev/null 2>&1; then
    eval "$(fzf --zsh)"
  else
    # 候选目录里加上「fzf 可执行文件所在位置的邻居」——
    # 手工安装或从旧 dotfiles 继承来的 fzf 不在包管理器的标准路径下，
    # 只查固定目录会漏掉，表现为键位绑定静默失效。
    _dot_fzf_bin="${commands[fzf]}"
    for _dot_fzf_dir in \
      "${HOMEBREW_PREFIX:-/usr/local}/opt/fzf/shell" \
      "${_dot_fzf_bin:h:h}/shell" \
      "${_dot_fzf_bin:h:h}" \
      /usr/share/fzf \
      /usr/share/doc/fzf/examples \
      "$HOME/.fzf/shell"; do
      if [[ -f "$_dot_fzf_dir/key-bindings.zsh" ]]; then
        source "$_dot_fzf_dir/key-bindings.zsh"
        [[ -f "$_dot_fzf_dir/completion.zsh" ]] && source "$_dot_fzf_dir/completion.zsh"
        break
      fi
    done
    unset _dot_fzf_dir _dot_fzf_bin
  fi

  # 用 fd 作为 fzf 的文件来源：尊重 .gitignore，且比 find 快
  if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi

  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

  # 预览：文件用 bat，目录用 eza
  if (( $+commands[bat] )); then
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
  fi
  if (( $+commands[eza] )); then
    export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"
  fi
fi

# ---------------------------------------------------------------- atuin
#
# 可选（默认不安装）—— 它会接管 Ctrl-R 并改变历史行为，因此只在
# 用户确实装了它时才初始化。
#
# 必须在 fzf 之后加载，否则 fzf 的 Ctrl-R 绑定会覆盖 atuin 的。

if (( $+commands[atuin] )); then
  eval "$(atuin init zsh)"
fi

# ---------------------------------------------------------------- bat

if (( $+commands[bat] )); then
  export BAT_THEME="${BAT_THEME:-ansi}"
  # 作为 man 的 pager，让 man 页也有语法高亮
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export MANROFFOPT='-c'
fi

# ---------------------------------------------------------------- direnv

if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi
