# 高开销工具的惰性加载。
#
# nvm 的 nvm.sh 本身就要 100-500ms —— 它是 zsh 启动最大的单项开销，
# 而多数 shell 会话根本不碰 node。这里用占位函数替代：首次调用
# node/npm/npx/nvm 时才真正加载 nvm，之后占位函数被真实命令取代。
#
# 代价是首次调用 node 会慢一下。换来的是每个 shell 少几百毫秒启动时间。

# ---------------------------------------------------------------- nvm

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# 找到 nvm.sh 的实际位置（brew 装的与官方脚本装的位置不同）
typeset -g _dot_nvm_sh=''
if [[ -n "$HOMEBREW_PREFIX" && -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]]; then
  _dot_nvm_sh="$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
elif [[ -s "$NVM_DIR/nvm.sh" ]]; then
  _dot_nvm_sh="$NVM_DIR/nvm.sh"
fi

if [[ -n "$_dot_nvm_sh" ]]; then
  # 真正加载 nvm，并撤掉全部占位函数
  _dot_load_nvm() {
    unfunction node npm npx nvm yarn pnpm _dot_load_nvm 2>/dev/null
    source "$_dot_nvm_sh"
    # 补全也一并加载（同样是惰性的一部分）
    if [[ -n "$HOMEBREW_PREFIX" && -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ]]; then
      source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
    elif [[ -s "$NVM_DIR/bash_completion" ]]; then
      source "$NVM_DIR/bash_completion"
    fi
  }

  # 为每个入口命令生成占位函数：加载 nvm 后把原命令重新执行一次
  for _dot_nvm_cmd in node npm npx nvm yarn pnpm; do
    eval "
      ${_dot_nvm_cmd}() {
        _dot_load_nvm
        command ${_dot_nvm_cmd} \"\$@\"
      }
    "
  done
  unset _dot_nvm_cmd
fi

# ---------------------------------------------------------------- conda
#
# conda 的 shell hook 也在百毫秒量级，同样惰性化。

typeset -g _dot_conda_base=''
for _dot_c in "$HOME/miniforge3" "$HOME/miniconda3" "$HOME/anaconda3" \
  "${HOMEBREW_PREFIX:-/opt/homebrew}/Caskroom/miniforge/base"; do
  if [[ -x "$_dot_c/bin/conda" ]]; then
    _dot_conda_base="$_dot_c"
    break
  fi
done
unset _dot_c

if [[ -n "$_dot_conda_base" ]]; then
  conda() {
    unfunction conda
    eval "$("$_dot_conda_base/bin/conda" shell.zsh hook 2>/dev/null)"
    conda "$@"
  }
fi

# ---------------------------------------------------------------- pyenv

if [[ -d "$HOME/.pyenv" ]]; then
  export PYENV_ROOT="$HOME/.pyenv"
  # shims 目录直接加进 PATH（廉价），但 pyenv init 的重活留到首次调用
  [[ -d "$PYENV_ROOT/bin" ]] && path=("$PYENV_ROOT/bin" $path)

  if (( $+commands[pyenv] )); then
    pyenv() {
      unfunction pyenv
      eval "$(command pyenv init - zsh)"
      pyenv "$@"
    }
  fi
fi
