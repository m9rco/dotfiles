#!/usr/bin/env sh
#
# AI 时代的 dotfiles —— Unix 侧引导入口（macOS / Linux / WSL）。
# Windows 原生环境请用 bootstrap.ps1。
#
# 只用 POSIX sh，可在 dash 下执行 —— 引导阶段不能依赖任何尚未安装的东西。
#
#   ./bootstrap.sh                    安装全部适用的 core 模块
#   ./bootstrap.sh --dry-run          预演，不做任何改动
#   ./bootstrap.sh --info             打印平台探测结果
#   ./bootstrap.sh --list             列出全部模块
#   ./bootstrap.sh --only zsh,fonts   只装指定模块（连同其依赖）
#   ./bootstrap.sh --tag ai           只装带某标签的模块
#
# shellcheck shell=sh

set -u

# 仓库根目录。用 $0 解析，支持从任意 cwd 调用。
DOT_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
DOT_LIB_DIR="$DOT_ROOT/lib"
# 以下三项允许预设，供测试与 CI 用替身目录验证行为。
# 注意必须用 ${X:-default} 而不是直接赋值 —— 直接赋值会让环境里预设的值
# 被静默丢弃，测试就会在「以为用了替身、实际用了真目录」的前提下假通过。
DOT_PLATFORM_DIR=${DOT_PLATFORM_DIR:-$DOT_ROOT/platform}
DOT_MODULES_DIR=${DOT_MODULES_DIR:-$DOT_ROOT/modules}
DOT_CONFIG_DIR=${DOT_CONFIG_DIR:-$DOT_ROOT/config}
export DOT_ROOT DOT_LIB_DIR DOT_PLATFORM_DIR DOT_MODULES_DIR DOT_CONFIG_DIR

# shellcheck source=lib/log.sh
. "$DOT_LIB_DIR/log.sh"
# shellcheck source=lib/detect.sh
. "$DOT_LIB_DIR/detect.sh"
# shellcheck source=lib/runner.sh
. "$DOT_LIB_DIR/runner.sh"

DOT_DRY_RUN=0
DOT_ACTION=install
DOT_ONLY=''
DOT_SKIP=''
DOT_TAG=''

usage() {
    cat <<EOF
Usage: ./bootstrap.sh [options]

Sets up this machine from the dotfiles in $DOT_ROOT.
Platform (macOS / Linux / WSL) is detected automatically.

Options:
  --dry-run           Show what would happen without changing anything
  --only <a,b>        Install only these modules (their dependencies come along)
  --skip <a,b>        Install everything except these modules
  --tag <tag>         Install only modules carrying this tag
  --list              List all modules and whether they apply here
  --info              Print platform detection results
  -h, --help          Show this help

Available tags: $(dot_runner_tags)

Run './bootstrap.sh --list' for the module list — it is generated from
modules/ on disk, so it is always current.
EOF
}

# 逗号或空格分隔都接受
_dot_split() {
    printf '%s' "$1" | tr ',' ' '
}

while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) DOT_DRY_RUN=1 ;;
        --list) DOT_ACTION=list ;;
        --info) DOT_ACTION=info ;;
        --only)
            [ $# -ge 2 ] || {
                dot_error '--only requires a value'
                exit 1
            }
            DOT_ONLY=$(_dot_split "$2")
            shift
            ;;
        --only=*) DOT_ONLY=$(_dot_split "${1#*=}") ;;
        --skip)
            [ $# -ge 2 ] || {
                dot_error '--skip requires a value'
                exit 1
            }
            DOT_SKIP=$(_dot_split "$2")
            shift
            ;;
        --skip=*) DOT_SKIP=$(_dot_split "${1#*=}") ;;
        --tag)
            [ $# -ge 2 ] || {
                dot_error '--tag requires a value'
                exit 1
            }
            DOT_TAG=$2
            shift
            ;;
        --tag=*) DOT_TAG=${1#*=} ;;
        -h | --help) DOT_ACTION=help ;;
        *)
            dot_error "unknown option: $1"
            dot_error "run './bootstrap.sh --help' for usage"
            exit 1
            ;;
    esac
    shift
done

export DOT_DRY_RUN

# 探测与发现对所有动作都需要（--help 要动态生成标签清单）。两者都零副作用。
dot_detect

# 加载当前平台的适配层，使模块能直接用 dot_platform_* 函数。
# 必须在任何模块执行前完成 —— 否则模块调 dot_platform_font_dir 会
# "command not found" 而只在 stderr 留一行，模块本身仍报成功。
dot_pkg_load_platform || exit 1

dot_runner_discover || exit 1

case $DOT_ACTION in
    help)
        usage
        exit 0
        ;;
    info)
        dot_detect_info
        exit 0
        ;;
    list)
        dot_runner_list
        exit 0
        ;;
esac

# ---------------------------------------------------------------- 选择模块

# 未知模块名必须报错而非静默忽略 —— 静默忽略会让打错名字的用户
# 以为装好了，实际什么都没发生。
for _dot_chk in $DOT_ONLY $DOT_SKIP; do
    if ! dot_module_exists "$_dot_chk"; then
        dot_error "unknown module: $_dot_chk"
        dot_error "run './bootstrap.sh --list' to see available modules"
        exit 1
    fi
done

_dot_selected=''

if [ -n "$DOT_ONLY" ]; then
    _dot_selected=$DOT_ONLY
else
    for _dot_m in $DOT_ALL_MODULES; do
        # 无 --tag 时默认只装 core；--tag 指定时按标签筛选
        _dot_want=0
        for _dot_t in $(dot_module_get "$_dot_m" TAGS); do
            if [ -n "$DOT_TAG" ]; then
                [ "$_dot_t" = "$DOT_TAG" ] && _dot_want=1
            else
                [ "$_dot_t" = core ] && _dot_want=1
            fi
        done
        [ "$_dot_want" = 1 ] && _dot_selected="$_dot_selected $_dot_m"
    done
fi

# --skip 在选择之后应用，且不影响作为依赖被拉入的模块
for _dot_s in $DOT_SKIP; do
    _dot_selected=$(printf '%s' "$_dot_selected" | tr ' ' '\n' | grep -v "^${_dot_s}\$" | tr '\n' ' ')
done

if [ -z "$(printf '%s' "$_dot_selected" | tr -d ' ')" ]; then
    dot_error 'no modules selected'
    [ -n "$DOT_TAG" ] && dot_error "no module carries tag '$DOT_TAG' (available: $(dot_runner_tags))"
    exit 1
fi

# ---------------------------------------------------------------- 执行

# shellcheck disable=SC2086
_dot_ordered=$(dot_runner_sort $_dot_selected) || exit 1

if [ "$DOT_DRY_RUN" = 1 ]; then
    dot_tip 'dry run — nothing will be modified'
fi

dot_info "platform: $DOT_OS/$DOT_ARCH${DOT_DISTRO:+ ($DOT_DISTRO)} · pkg: $DOT_PKG$([ "$DOT_WSL" = 1 ] && printf ' · WSL')$([ "$DOT_HEADLESS" = 1 ] && printf ' · headless')"

# shellcheck disable=SC2086
dot_runner_run $_dot_ordered

dot_runner_summary
