# 凭据的按需注入。
#
# 关键约束：**这个片段在 shell 启动时不读取任何凭据**。
# 同步调用 keychain 会拖慢启动，并可能弹出授权对话框 —— 每开一个终端
# 标签都弹一次是不可接受的。这里只定义函数，实际读取由用户显式触发。

# 惰性加载 lib/secrets.sh —— 首次调用相关函数时才 source。
# 直接在这里 source 会把它的解析开销加到每次 shell 启动上。
#
# source 之后 lib 里的同名函数会覆盖下面的占位定义，所以占位函数
# 用 `unfunction` 明确移交而不是依赖覆盖顺序 —— 后者能工作但太隐晦，
# 一旦 lib 里改了函数名就会变成无限递归。
_dot_secrets_lib() {
  [[ -n "$DOT_SECRETS_SH_LOADED" ]] && return 0

  local lib="${DOTFILES}/lib/secrets.sh"
  if [[ ! -r "$lib" ]]; then
    print -u2 "dotfiles: secrets lib not found: $lib"
    return 1
  fi

  # secrets.sh 需要 DOT_OS 来选密钥库
  if [[ -z "$DOT_OS" ]]; then
    export DOT_LIB_DIR="${DOTFILES}/lib"
    source "${DOTFILES}/lib/detect.sh" && dot_detect
  fi

  # 先撤掉占位函数，再 source —— 这样 lib 的定义是唯一的那份
  unfunction dot_secret_get dot_secret_set dot_secret_load 2>/dev/null
  source "$lib"
}

# 下面三个是占位：首次调用时加载 lib（lib 会替换掉它们），然后转发。
for _dot_sf in dot_secret_get dot_secret_set dot_secret_load; do
  eval "
    ${_dot_sf}() {
      _dot_secrets_lib || return 1
      # 此时 ${_dot_sf} 已是 lib 里的实现
      ${_dot_sf} \"\$@\"
    }
  "
done
unset _dot_sf

# ---------------------------------------------------------------- 便捷命令

# 把常用的 AI 服务凭据一次性注入当前 shell，
# 用于那些只认环境变量的工具。
ai-keys() {
  dot_secret_load ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY
}
