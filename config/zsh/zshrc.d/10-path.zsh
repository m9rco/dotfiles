# PATH 与 Homebrew 环境。
#
# Homebrew 前缀必须探测 —— 旧配置写死 /usr/local/bin/brew，
# 在 Apple Silicon（/opt/homebrew）上直接失效。

# ---------------------------------------------------------------- Homebrew

# 按平台的已知落点探测，先命中先用：
#   /opt/homebrew              Apple Silicon
#   /usr/local                 Intel Mac
#   /home/linuxbrew/.linuxbrew Linuxbrew
if [[ -z "$HOMEBREW_PREFIX" ]]; then
  for _dot_brew in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
    if [[ -x "$_dot_brew/bin/brew" ]]; then
      eval "$("$_dot_brew/bin/brew" shellenv)"
      break
    fi
  done
  unset _dot_brew
fi

# ---------------------------------------------------------------- PATH
#
# 用 zsh 的 path 数组操作，配合 typeset -U 自动去重 ——
# 这样重复 source 本文件不会让 PATH 无限膨胀。

typeset -U path PATH

# 靠前的优先级更高
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  $path
)

# Rust
[[ -d "$HOME/.cargo/bin" ]] && path=("$HOME/.cargo/bin" $path)

# Go
[[ -d "$HOME/go/bin" ]] && path=("$HOME/go/bin" $path)

# npm 全局安装的可执行文件（AI CLI 多数走这条路径）
if [[ -d "$HOME/.npm-global/bin" ]]; then
  path=("$HOME/.npm-global/bin" $path)
fi

# 只保留真实存在的目录，避免 PATH 里堆积无效条目拖慢命令查找
path=($^path(N-/))

export PATH
