# oh-my-zsh 与插件。
#
# 插件按对应命令是否存在决定加载 —— 缺失的工具不产生错误输出。
# 判断集中在本文件，不散落到入口。
#
# 注意：prompt 由 starship 负责（见 30-tools.zsh），这里把 omz 主题留空，
# 只在 starship 不可用时才回退到 omz 主题。

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"

# oh-my-zsh 未安装则整个片段跳过，shell 仍可正常使用
if [[ ! -f "$ZSH/oh-my-zsh.sh" ]]; then
  return 0
fi

# ---------------------------------------------------------------- 插件选择

# 无条件启用的核心插件
plugins=(
  colored-man-pages
  extract           # 一个命令解压任意格式
  sudo              # ESC ESC 给上一条命令加 sudo
)

# 按命令存在性追加。$commands 是 zsh 内建的命令哈希表，
# 查它比调用 command -v 快得多（每次启动省下十几次子进程）。
(( $+commands[git] ))     && plugins+=(git)
(( $+commands[docker] ))  && plugins+=(docker)
(( $+commands[kubectl] )) && plugins+=(kubectl)
(( $+commands[tmux] ))    && plugins+=(tmux)
(( $+commands[rustup] ))  && plugins+=(rust)
(( $+commands[gh] ))      && plugins+=(gh)

# 自定义插件（需要单独安装到 $ZSH/custom/plugins/）
_dot_omz_custom_plugin() {
  [[ -f "$ZSH/custom/plugins/$1/$1.plugin.zsh" ]]
}

# zsh-autosuggestions 在 emacs 内嵌终端里渲染不出灰色提示，反而干扰阅读
if [[ -z "$INSIDE_EMACS" ]] && _dot_omz_custom_plugin zsh-autosuggestions; then
  plugins+=(zsh-autosuggestions)
fi

# 语法高亮必须在 history-substring-search 之前加载
_dot_omz_custom_plugin zsh-syntax-highlighting && plugins+=(zsh-syntax-highlighting)
_dot_omz_custom_plugin zsh-history-substring-search && plugins+=(zsh-history-substring-search)

unfunction _dot_omz_custom_plugin

# ---------------------------------------------------------------- omz 设置

# starship 接管 prompt 时把主题置空，避免两者抢渲染
if (( $+commands[starship] )); then
  ZSH_THEME=""
else
  ZSH_THEME="${ZSH_THEME:-robbyrussell}"
fi

# 自动更新交给包管理器/手动，避免 shell 启动时卡在网络请求上
zstyle ':omz:update' mode disabled

# 大仓库里检查未跟踪文件很慢，且对 prompt 的价值有限
DISABLE_UNTRACKED_FILES_DIRTY="true"

# 补全等待时的点状提示
COMPLETION_WAITING_DOTS="true"

# 补全 dump 的位置。omz 默认按主机名+zsh 版本命名，这里统一到一个固定
# 名字，避免同一台机器上出现多份缓存；omz 会尊重这个预设值，并在 fpath
# 或自身版本变化时自动重建（见 25-completion.zsh 的说明）。
ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"

# compinit 由 omz 负责（它的实现已带失效判断与 zrecompile），
# 25-completion.zsh 只在没有 omz 时才自己跑。跳过 omz 的权限检查 ——
# 它在共享机器上会因目录属主而中断启动，而收益有限。
ZSH_DISABLE_COMPFIX="true"

source "$ZSH/oh-my-zsh.sh"
