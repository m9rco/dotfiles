#!/usr/bin/env sh
#
# Linux 平台适配（含 WSL）。apt / dnf / pacman / apk / zypper 的差异全部收敛在这里。
#
# shellcheck shell=sh

[ -n "${DOT_PLATFORM_LINUX_LOADED:-}" ] && return 0
DOT_PLATFORM_LINUX_LOADED=1

# shellcheck source=lib/log.sh
. "${DOT_LIB_DIR:-$(dirname -- "$0")/lib}/log.sh"

# ---------------------------------------------------------------- 包名映射

# 逻辑名 -> 各发行版包名。同一个工具在不同发行版下叫法差别很大，
# 这张表是把这类知识留在平台层而不是散进模块的原因。
# 返回空表示该发行版的仓库里没有这个包，由 pkg.sh 走回退链（发布二进制 / cargo / npm）。
dot_platform_pkg_name() {
    _dot_logical=$1

    case $_dot_logical in
        fd)
            case $DOT_PKG in
                # Debian/Ubuntu 的包叫 fd-find，可执行文件是 fdfind
                apt) printf 'fd-find' ;;
                dnf) printf 'fd-find' ;;
                pacman | apk) printf 'fd' ;;
                *) printf 'fd' ;;
            esac
            ;;
        bat)
            case $DOT_PKG in
                # Debian 的包是 bat，但旧版里可执行文件叫 batcat
                apt | dnf | pacman | apk) printf 'bat' ;;
                *) printf 'bat' ;;
            esac
            ;;
        rg | ripgrep) printf 'ripgrep' ;;
        delta)
            case $DOT_PKG in
                # apt 仓库里没有 git-delta（Debian 13 起才有），走回退链
                apt) printf '' ;;
                dnf) printf 'git-delta' ;;
                pacman) printf 'git-delta' ;;
                apk) printf 'delta' ;;
                *) printf '' ;;
            esac
            ;;
        eza)
            case $DOT_PKG in
                # eza 较新，多数发行版仓库尚未收录
                pacman) printf 'eza' ;;
                apk) printf 'eza' ;;
                *) printf '' ;;
            esac
            ;;
        lazygit)
            case $DOT_PKG in
                pacman) printf 'lazygit' ;;
                apk) printf 'lazygit' ;;
                *) printf '' ;;
            esac
            ;;
        starship)
            case $DOT_PKG in
                pacman) printf 'starship' ;;
                apk) printf 'starship' ;;
                *) printf '' ;;
            esac
            ;;
        zoxide)
            case $DOT_PKG in
                apt | dnf | pacman | apk) printf 'zoxide' ;;
                *) printf '' ;;
            esac
            ;;
        atuin)
            case $DOT_PKG in
                pacman) printf 'atuin' ;;
                *) printf '' ;;
            esac
            ;;
        gh)
            case $DOT_PKG in
                # apt 需要先加 GitHub 的仓库，这里返回空走回退链更可靠
                apt) printf '' ;;
                dnf | pacman | apk) printf 'github-cli' ;;
                *) printf '' ;;
            esac
            ;;
        yq)
            case $DOT_PKG in
                pacman) printf 'go-yq' ;;
                apk) printf 'yq' ;;
                *) printf '' ;;
            esac
            ;;
        # dust / procs / xh / sd / tldr 都是较新的 Rust 工具，主流发行版
        # 仓库多半没收录。返回空串走 cargo 回退比赌包名更可靠 ——
        # 赌错的后果是 apt 报 "no installable candidate"，而回退链本来就能装成。
        dust | procs | xh | sd)
            case $DOT_PKG in
                pacman | apk) printf '%s' "$_dot_logical" ;;
                *) printf '' ;;
            esac
            ;;
        tldr)
            case $DOT_PKG in
                # Arch/Alpine 收了 Rust 实现 tealdeer，装出来的命令是 tldr
                pacman | apk) printf 'tealdeer' ;;
                *) printf '' ;;
            esac
            ;;
        duf)
            case $DOT_PKG in
                apt | dnf | pacman | apk) printf 'duf' ;;
                *) printf '' ;;
            esac
            ;;
        hyperfine)
            case $DOT_PKG in
                pacman | apk) printf 'hyperfine' ;;
                *) printf '' ;;
            esac
            ;;
        # btop / htop / direnv / tmux 在各发行版仓库里都同名且都收录了
        btop | htop | direnv | tmux) printf '%s' "$_dot_logical" ;;
        fzf | jq | git | zsh | curl | unzip) printf '%s' "$_dot_logical" ;;
        *) printf '%s' "$_dot_logical" ;;
    esac
}

# ---------------------------------------------------------------- 包安装

# apt 的索引在一次引导内只更新一次，避免每装一个包就 update 一遍
DOT_APT_UPDATED=${DOT_APT_UPDATED:-0}

# 非 root 时需要 sudo；容器内通常已是 root。
_dot_sudo() {
    if [ "$(id -u)" = 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        dot_error "need root to install packages but sudo is not available"
        return 1
    fi
}

dot_platform_pkg_install() {
    _dot_pkg=$1

    case $DOT_PKG in
        apt)
            if [ "$DOT_APT_UPDATED" = 0 ]; then
                _dot_sudo apt-get update -qq || return 1
                DOT_APT_UPDATED=1
            fi
            DEBIAN_FRONTEND=noninteractive _dot_sudo apt-get install -y -qq "$_dot_pkg"
            ;;
        dnf) _dot_sudo dnf install -y "$_dot_pkg" ;;
        pacman) _dot_sudo pacman -S --needed --noconfirm "$_dot_pkg" ;;
        apk) _dot_sudo apk add --no-cache "$_dot_pkg" ;;
        zypper) _dot_sudo zypper install -y "$_dot_pkg" ;;
        brew)
            # Linuxbrew
            if brew list --formula "$_dot_pkg" >/dev/null 2>&1; then
                dot_skip "$_dot_pkg already installed (brew)"
                return 0
            fi
            brew install "$_dot_pkg"
            ;;
        *)
            dot_error "unsupported package manager: $DOT_PKG"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------- 字体

# 用户级字体目录，无需 root。
# DOT_FONT_DIR 可覆盖 —— 测试必须能把字体装到沙箱而不是真实的字体目录。
dot_platform_font_dir() {
    printf '%s' "${DOT_FONT_DIR:-$HOME/.local/share/fonts}"
}

# Linux 需要显式刷新字体缓存才能让应用枚举到新字体。
# fc-cache 缺失时只提示，不使模块失败（字体文件已经就位）。
dot_platform_font_refresh() {
    _dot_font_dir=$(dot_platform_font_dir)

    if ! command -v fc-cache >/dev/null 2>&1; then
        dot_tip "fc-cache not found; run it manually to refresh the font cache"
        return 0
    fi

    if [ "${DOT_DRY_RUN:-0}" = 1 ]; then
        dot_info "[dry-run] would run fc-cache -f $_dot_font_dir"
        return 0
    fi

    fc-cache -f "$_dot_font_dir" >/dev/null 2>&1
    dot_success "font cache refreshed"
}
