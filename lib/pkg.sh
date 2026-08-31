#!/usr/bin/env sh
#
# 包安装抽象。模块只调 dot_pkg_install ripgrep，不关心背后是 brew、apt 还是回退二进制。
#
# 安装链（按序尝试，任一成功即止）：
#   1. 平台包管理器（brew / apt / dnf / pacman / apk / zypper）
#   2. 声明的回退方式（cargo / npm / 官方安装脚本）
# 全部失败只记录，由调用方决定是否致命 —— 单个工具装不上不应中断整个引导。
#
# shellcheck shell=sh

[ -n "${DOT_PKG_SH_LOADED:-}" ] && return 0
DOT_PKG_SH_LOADED=1

_dot_pkg_lib=${DOT_LIB_DIR:-$(dirname -- "$0")}
# shellcheck source=lib/log.sh
. "$_dot_pkg_lib/log.sh"
# shellcheck source=lib/fs.sh
. "$_dot_pkg_lib/fs.sh"
# detect.sh 提供 dot_detect_ensure_pkg 与 DOT_* 契约变量
# shellcheck source=lib/detect.sh
. "$_dot_pkg_lib/detect.sh"

# 加载当前平台的适配层。DOT_PLATFORM_DIR 由 bootstrap.sh 设置。
dot_pkg_load_platform() {
    _dot_plat_dir=${DOT_PLATFORM_DIR:-$_dot_pkg_lib/../platform}

    case $DOT_OS in
        macos)
            # shellcheck source=platform/macos.sh
            . "$_dot_plat_dir/macos.sh"
            ;;
        linux)
            # shellcheck source=platform/linux.sh
            . "$_dot_plat_dir/linux.sh"
            ;;
        windows)
            # bootstrap.sh 是 Unix 入口；Windows 原生环境的适配层是
            # platform/windows.ps1，由 bootstrap.ps1 加载。
            # 走到这里通常意味着在 Git-Bash / MSYS 里跑了 bootstrap.sh ——
            # 明确告诉用户该用哪个入口，而不是抛一句看不懂的错误。
            dot_error 'bootstrap.sh does not support native Windows'
            dot_error 'run bootstrap.ps1 in PowerShell instead (or use WSL)'
            return 1
            ;;
        *)
            dot_error "no platform adapter for DOT_OS=$DOT_OS"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------- 存在性判断

# 逻辑名 -> 该工具实际的可执行文件名。多数一致，少数不同（如 ripgrep 的命令是 rg）。
# Debian 系的 fd/bat 装出来叫 fdfind/batcat，所以这里给出多个候选，任一存在即视为已安装。
dot_pkg_commands_for() {
    case $1 in
        ripgrep) printf 'rg' ;;
        fd) printf 'fd fdfind' ;;
        bat) printf 'bat batcat' ;;
        delta) printf 'delta' ;;
        yq) printf 'yq' ;;
        github-cli) printf 'gh' ;;
        *) printf '%s' "$1" ;;
    esac
}

# 工具是否已可用。幂等判定的依据 —— PATH 中可执行即视为已安装。
dot_pkg_installed() {
    for _dot_cmd in $(dot_pkg_commands_for "$1"); do
        if command -v "$_dot_cmd" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------- 回退安装方式

# cargo 安装。crate 名默认与逻辑名一致。
_dot_pkg_try_cargo() {
    command -v cargo >/dev/null 2>&1 || return 1
    dot_info "installing $1 via cargo"
    cargo install --locked "$1" >/dev/null 2>&1
}

# npm 全局安装。绝不使用 sudo —— 需要 sudo 说明 npm 前缀配置有问题，
# 那应该修配置而不是提权。
_dot_pkg_try_npm() {
    command -v npm >/dev/null 2>&1 || return 1
    dot_info "installing $1 via npm"
    npm install --global "$1" >/dev/null 2>&1
}

# 官方安装脚本。仅用于明确声明了该方式的工具，脚本 URL 由调用方给出。
_dot_pkg_try_script() {
    _dot_script_url=$1
    command -v curl >/dev/null 2>&1 || return 1
    dot_info "installing via official script: $_dot_script_url"
    curl -fsSL "$_dot_script_url" | sh >/dev/null 2>&1
}

# ---------------------------------------------------------------- 入口

# dot_pkg_install <logical-name> [fallback-spec...]
#
# fallback-spec 形如 cargo:crate-name / npm:package-name / script:https://...
# 未给出时只尝试平台包管理器。
#
# 返回 0 表示已就位（含"本来就装了"），非零表示所有方式都失败。
dot_pkg_install() {
    _dot_want=$1
    shift

    if dot_pkg_installed "$_dot_want"; then
        dot_skip "$_dot_want already available"
        return 0
    fi

    _dot_pkgname=$(dot_platform_pkg_name "$_dot_want")

    if dot_is_dry_run; then
        if [ -n "$_dot_pkgname" ]; then
            dot_info "[dry-run] would install $_dot_want via $DOT_PKG ($_dot_pkgname)"
        elif [ $# -gt 0 ]; then
            dot_info "[dry-run] would install $_dot_want via fallback: $1"
        else
            dot_info "[dry-run] would install $_dot_want (no method available)"
        fi
        return 0
    fi

    # 安装类操作才需要包管理器就绪，因此 ensure 放在 dry-run 判断之后
    dot_detect_ensure_pkg || return 1

    # 1. 平台包管理器
    if [ -n "$_dot_pkgname" ]; then
        if dot_platform_pkg_install "$_dot_pkgname"; then
            dot_success "installed $_dot_want via $DOT_PKG"
            return 0
        fi
        dot_info "$DOT_PKG could not install $_dot_want; trying fallbacks"
    else
        dot_info "$_dot_want not in $DOT_PKG repos; trying fallbacks"
    fi

    # 2. 声明的回退方式，按给出的顺序尝试
    for _dot_fb in "$@"; do
        _dot_fb_kind=${_dot_fb%%:*}
        _dot_fb_arg=${_dot_fb#*:}

        case $_dot_fb_kind in
            cargo) _dot_pkg_try_cargo "$_dot_fb_arg" && {
                dot_success "installed $_dot_want via cargo"
                return 0
            } ;;
            npm) _dot_pkg_try_npm "$_dot_fb_arg" && {
                dot_success "installed $_dot_want via npm"
                return 0
            } ;;
            script) _dot_pkg_try_script "$_dot_fb_arg" && {
                dot_success "installed $_dot_want via install script"
                return 0
            } ;;
            *) dot_error "unknown fallback spec: $_dot_fb" ;;
        esac
    done

    dot_error "could not install $_dot_want (tried $DOT_PKG and $# fallback method(s))"
    return 1
}
