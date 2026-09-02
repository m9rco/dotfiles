#!/usr/bin/env sh
#
# 包安装抽象。模块只调 dot_pkg_install ripgrep，不关心背后是 brew、apt 还是回退二进制。
#
# 安装链（按序尝试，任一成功即止）：
#   1. 平台包管理器（brew / apt / dnf / yum / pacman / apk / zypper）
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
        # tldr 有多个实现（tlrc / tealdeer / 老的 Node 客户端），装出来的
        # 命令都叫 tldr；tealdeer 早期版本还会留一个 tldrl。
        tldr) printf 'tldr tealdeer' ;;
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

# cargo 工具链是否已尝试安装过（一次引导内只试一次）
DOT_RUSTUP_TRIED=${DOT_RUSTUP_TRIED:-0}

# 确保 cargo 可用，缺失时装 rustup。
#
# 为什么需要：包源贫乏的发行版（RHEL/CentOS 7 最典型）上，eza / starship /
# dust 这类较新的 Rust 工具在任何仓库里都没有，唯一出路就是 cargo。
# 而那些机器默认也没有 cargo，于是回退链形同虚设 —— 报告「tried 1 fallback
# method」却从未真正尝试。
#
# 代价必须说清：rustup 工具链约 600MB，之后每个工具都是现场编译。
# 默认集里有 15 个工具声明了 cargo 回退，在 2 核机器上全部编译实测
# 需要 40–90 分钟。所以：
#   - 安装前明确告知体积与耗时，不静默下载几百 MB
#   - DOT_NO_RUSTUP=1 可完全关掉，只报告缺 cargo
#   - 一次引导内只尝试一次，失败后不再重试
_dot_pkg_ensure_cargo() {
    command -v cargo >/dev/null 2>&1 && return 0
    [ "$DOT_RUSTUP_TRIED" = 0 ] || return 1

    DOT_RUSTUP_TRIED=1

    if [ "${DOT_NO_RUSTUP:-0}" = 1 ]; then
        dot_tip 'cargo not available and DOT_NO_RUSTUP=1; skipping source builds'
        return 1
    fi

    command -v curl >/dev/null 2>&1 || {
        dot_tip 'cargo not available and curl is missing; cannot bootstrap rustup'
        return 1
    }

    dot_step 'installing the Rust toolchain — needed to build tools absent from your package repos'
    dot_info '  this downloads ~600MB and later compiles each tool from source'
    dot_info '  expect tens of minutes on a small machine; set DOT_NO_RUSTUP=1 to skip'

    if curl -fsSL https://sh.rustup.rs |
        sh -s -- -y --no-modify-path --profile minimal >/dev/null 2>&1; then
        # rustup 装到 ~/.cargo/bin，当前 shell 的 PATH 还没有它
        [ -d "$HOME/.cargo/bin" ] && PATH="$HOME/.cargo/bin:$PATH" && export PATH
        if command -v cargo >/dev/null 2>&1; then
            dot_success 'Rust toolchain installed'
            return 0
        fi
    fi

    dot_error 'could not install the Rust toolchain; source builds unavailable'
    return 1
}

# cargo 安装。crate 名默认与逻辑名一致。
_dot_pkg_try_cargo() {
    if ! _dot_pkg_ensure_cargo; then
        # 明确说清为什么这条回退没走 —— 之前这里静默 return 1，
        # 而上层照样报告「tried 1 fallback method(s)」，等于骗人。
        dot_info "  cargo unavailable; cannot build $1 from source"
        return 1
    fi
    dot_info "installing $1 via cargo (compiling from source, this is slow)"
    cargo install --locked "$1" >/dev/null 2>&1
}

# npm 全局安装。绝不使用 sudo —— 需要 sudo 说明 npm 前缀配置有问题，
# 那应该修配置而不是提权。
_dot_pkg_try_npm() {
    command -v npm >/dev/null 2>&1 || {
        dot_info "  npm not available; cannot install $1 that way"
        return 1
    }
    dot_info "installing $1 via npm"
    npm install --global "$1" >/dev/null 2>&1
}

# 官方安装脚本。仅用于明确声明了该方式的工具，脚本 URL 由调用方给出。
#
# 参数经 `sh -s --` 传给脚本本身。--yes 是必须的：多数官方安装脚本
# （starship、rustup 都是）默认会交互式确认，而引导是无人值守的 ——
# 不给它就会挂在等输入，或因 stdin 不是 tty 而以看不懂的方式失败。
#
# 装到 ~/.local/bin 而不是 /usr/local/bin：免提权，且与本仓库
# 「不碰系统目录」的前提一致。
_dot_pkg_try_script() {
    _dot_script_url=$1
    command -v curl >/dev/null 2>&1 || {
        dot_info '  curl not available; cannot run the install script'
        return 1
    }
    dot_info "installing via official script: $_dot_script_url"

    _dot_script_bin="$HOME/.local/bin"
    mkdir -p "$_dot_script_bin" 2>/dev/null || true

    if curl -fsSL "$_dot_script_url" |
        sh -s -- --yes --bin-dir "$_dot_script_bin" >/dev/null 2>&1; then
        # 脚本装到 ~/.local/bin，当前 shell 的 PATH 可能还没有它。
        # 不导出的话紧随其后的 dot_pkg_installed 判定会失败。
        case ":$PATH:" in
            *":$_dot_script_bin:"*) ;;
            *)
                PATH="$_dot_script_bin:$PATH"
                export PATH
                # 记下来，引导结束时统一提示 —— 导出只影响引导进程自身，
                # 用户当前的 shell 仍然找不到这个工具，直到重开终端。
                # zsh 配置里有 ~/.local/bin，所以新 shell 没问题；
                # 但不说清楚的话，用户会以为「装了却没装上」。
                DOT_PKG_PATH_NOTICE=$_dot_script_bin
                export DOT_PKG_PATH_NOTICE
                ;;
        esac
        return 0
    fi

    # 不接受 --bin-dir 的脚本用不带参数的方式再试一次 —— 各家脚本
    # 的参数约定不统一，硬要求某个 flag 会把本来能用的路堵死。
    curl -fsSL "$_dot_script_url" | sh -s -- --yes >/dev/null 2>&1
}

# ---------------------------------------------------------------- 入口

# 在安装循环之前准备包仓库（目前只有 RHEL 族的 EPEL）。
#
# 单独暴露一个入口，而不是只在 dot_platform_pkg_install 里顺带做，
# 是因为 dry-run 在本文件里就短路返回了，永远走不到平台层 ——
# 而启用 EPEL 会改系统仓库配置，恰恰是 dry-run 最该预告的那类副作用。
# 之前把 dry-run 分支写在平台层里，那段代码实际是不可达的死代码。
#
# 平台没有这个概念时静默跳过（macOS/Windows 都不需要）。
dot_pkg_prepare_repos() {
    command -v dot_platform_prepare_repos >/dev/null 2>&1 || return 0
    dot_platform_prepare_repos
}

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
