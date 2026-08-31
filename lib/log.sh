#!/usr/bin/env sh
#
# 统一日志输出。所有模块的输出都应经过这里，不要直接 printf。
#
# 颜色在非 TTY 时自动禁用（管道、重定向、CI），使日志文件与 CI 输出干净可读。
# 可用 DOT_NO_COLOR=1 强制禁用，NO_COLOR=1（社区约定）同样生效。
#
# shellcheck shell=sh

[ -n "${DOT_LOG_SH_LOADED:-}" ] && return 0
DOT_LOG_SH_LOADED=1

# stderr 是否为终端。日志走 stderr，所以判断 fd 2 而非 fd 1 ——
# 这样 `./bootstrap.sh --list > file` 仍保留日志颜色，只有日志本身被重定向时才去色。
if [ -t 2 ] && [ -z "${DOT_NO_COLOR:-}" ] && [ -z "${NO_COLOR:-}" ]; then
    DOT_C_RESET=$(printf '\033[0m')
    DOT_C_RED=$(printf '\033[1;31m')
    DOT_C_GREEN=$(printf '\033[0;32m')
    DOT_C_YELLOW=$(printf '\033[0;33m')
    DOT_C_CYAN=$(printf '\033[0;36m')
    DOT_C_PURPLE=$(printf '\033[0;35m')
    DOT_C_GRAY=$(printf '\033[1;30m')
else
    DOT_C_RESET=''
    DOT_C_RED=''
    DOT_C_GREEN=''
    DOT_C_YELLOW=''
    DOT_C_CYAN=''
    DOT_C_PURPLE=''
    DOT_C_GRAY=''
fi

# 内部：带颜色前缀输出一行到 stderr。
# 用 printf '%s' 而非 %b —— 参数里的反斜杠不应被解释（路径中可能出现）。
_dot_log() {
    _dot_log_color=$1
    _dot_log_prefix=$2
    shift 2
    printf '%s%s %s%s\n' "$_dot_log_color" "$_dot_log_prefix" "$*" "$DOT_C_RESET" >&2
}

# 阶段开始，前面空一行以分隔视觉块
dot_step() {
    printf '\n' >&2
    _dot_log "$DOT_C_YELLOW" '==>' "$@"
}

dot_info() {
    _dot_log "$DOT_C_CYAN" '  ->' "$@"
}

dot_success() {
    _dot_log "$DOT_C_GREEN" '  ok' "$@"
}

dot_error() {
    _dot_log "$DOT_C_RED" '  !!' "$@"
}

# 提示性信息：可选操作、后续步骤、非致命的注意事项
dot_tip() {
    _dot_log "$DOT_C_PURPLE" '  ..' "$@"
}

# 跳过某项，附带原因 —— 每次跳过都必须说明为什么，否则用户无法判断是预期行为还是故障
dot_skip() {
    _dot_log "$DOT_C_GRAY" '  --' "$@"
}

# 需要用户输入时的提示（不换行，供 read 紧随其后）
dot_prompt() {
    printf '%s[?] %s%s ' "$DOT_C_PURPLE" "$*" "$DOT_C_RESET" >&2
}
