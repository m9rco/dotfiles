#!/usr/bin/env sh
#
# macOS 平台适配。把"在 macOS 上怎么做"收敛在这里，模块层不出现平台判断。
#
# shellcheck shell=sh

[ -n "${DOT_PLATFORM_MACOS_LOADED:-}" ] && return 0
DOT_PLATFORM_MACOS_LOADED=1

# shellcheck source=lib/log.sh
. "${DOT_LIB_DIR:-$(dirname -- "$0")/lib}/log.sh"

# ---------------------------------------------------------------- 包名映射

# 逻辑名 -> Homebrew 包名。
# 绝大多数工具在 brew 里同名，只在这里列出不一致的，其余走默认（原名返回）。
# 返回空表示该工具在本平台不通过包管理器安装（由 pkg.sh 走回退链）。
dot_platform_pkg_name() {
    case $1 in
        fd) printf 'fd' ;;
        bat) printf 'bat' ;;
        eza) printf 'eza' ;;
        rg | ripgrep) printf 'ripgrep' ;;
        delta) printf 'git-delta' ;;
        yq) printf 'yq' ;;
        gh) printf 'gh' ;;
        # brew 里没有 tldr 这个 formula。tlrc 是 tldr 客户端的官方 Rust
        # 实现，装出来的命令就叫 tldr。
        tldr) printf 'tlrc' ;;
        # 其余逻辑名与 brew 包名一致
        *) printf '%s' "$1" ;;
    esac
}

# 安装单个包。cask 类应用通过 --cask 安装。
dot_platform_pkg_install() {
    _dot_pkg=$1

    if [ -z "$DOT_BREW_PREFIX" ] && ! command -v brew >/dev/null 2>&1; then
        dot_error "Homebrew is not available; cannot install $_dot_pkg"
        return 1
    fi

    if brew list --formula "$_dot_pkg" >/dev/null 2>&1; then
        dot_skip "$_dot_pkg already installed (brew)"
        return 0
    fi

    brew install "$_dot_pkg"
}

# ---------------------------------------------------------------- 字体

# 用户级字体目录，无需管理员权限。
# DOT_FONT_DIR 可覆盖 —— 测试必须能把字体装到沙箱而不是真实的 ~/Library/Fonts。
dot_platform_font_dir() {
    printf '%s' "${DOT_FONT_DIR:-$HOME/Library/Fonts}"
}

# macOS 会自动感知 ~/Library/Fonts 的变化，无需手动刷新缓存。
dot_platform_font_refresh() {
    return 0
}
