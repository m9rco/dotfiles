#!/usr/bin/env sh
#
# Linux 平台适配（含 WSL）。apt / dnf / yum / pacman / apk / zypper 的差异全部收敛在这里。
#
# 关于 dnf 与 yum：包名在 RHEL 族里是同一套，所以两者在下面的映射表里
# 总是并列出现（`dnf | yum`）。刻意不把 yum 折叠成 dnf 的别名 —— 那样
# --info 会报 dnf 而实际跑的是 yum，排障时误导人。
# test/lint.sh 有一条交叉断言保证这张表里不出现「只有 dnf 没有 yum」的分支。
#
# shellcheck shell=sh

[ -n "${DOT_PLATFORM_LINUX_LOADED:-}" ] && return 0
DOT_PLATFORM_LINUX_LOADED=1

# shellcheck source=lib/log.sh
. "${DOT_LIB_DIR:-$(dirname -- "$0")/lib}/log.sh"
# fs.sh 提供 dot_is_dry_run。实际运行时 pkg.sh 已先 source 了它，
# 但显式声明依赖 —— 否则单独 source 本文件（测试就是这么做的）时
# dry-run 分支会撞上 command not found。
# shellcheck source=lib/fs.sh
. "${DOT_LIB_DIR:-$(dirname -- "$0")/lib}/fs.sh"

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
                dnf | yum) printf 'fd-find' ;;
                pacman | apk) printf 'fd' ;;
                *) printf 'fd' ;;
            esac
            ;;
        bat)
            case $DOT_PKG in
                # Debian 的包是 bat，但旧版里可执行文件叫 batcat
                apt | dnf | yum | pacman | apk) printf 'bat' ;;
                *) printf 'bat' ;;
            esac
            ;;
        rg | ripgrep) printf 'ripgrep' ;;
        delta)
            case $DOT_PKG in
                # apt 仓库里没有 git-delta（Debian 13 起才有），走回退链
                apt) printf '' ;;
                dnf | yum) printf 'git-delta' ;;
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
                apt | dnf | yum | pacman | apk) printf 'zoxide' ;;
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
                # yum-differs: github-cli 在 Fedora 官方仓库里有，但 RHEL/CentOS
                # 的 base 与 EPEL 都没有 —— 那里要加 GitHub 自己的 yum 仓库。
                # 所以 dnf（多为 Fedora）给包名，yum（RHEL/CentOS 7）返回空走回退。
                # 「RHEL 族与 Fedora 包名一致」对包名成立，对可用性不成立。
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
                apt | dnf | yum | pacman | apk) printf 'duf' ;;
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

# EPEL 同理只启用一次
DOT_EPEL_READY=${DOT_EPEL_READY:-0}

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

# 确保 EPEL 可用。
#
# 为什么必须做：RHEL/CentOS 的 base 仓库里没有 ripgrep、fd-find、bat、
# zoxide、git-delta、direnv、duf。它们都在 EPEL 里。不启用 EPEL 的话，
# 默认集 14 个工具有 7 个从仓库装不到，全部退化成 cargo 现场编译 ——
# 而那在 CentOS 7 上意味着几十分钟且很可能编不过。
#
# EPEL 是 Fedora 项目官方维护的、RHEL 生态的事实标准附加仓库，
# 不是随便的第三方源。Fedora 自带这些包，所以只对 rhel 族做。
#
# DOT_NO_EPEL=1 可关掉（离线环境、或公司镜像已自带这些包时）。
_dot_ensure_epel() {
    [ "$DOT_EPEL_READY" = 0 ] || return 0
    [ "${DOT_NO_EPEL:-0}" != 1 ] || {
        DOT_EPEL_READY=1
        return 0
    }
    # Fedora 本身收录了这些包，不需要 EPEL
    [ "${DOT_DISTRO:-}" = rhel ] || {
        DOT_EPEL_READY=1
        return 0
    }

    # dry-run 必须在任何包管理器调用之前返回。
    # repolist 虽然是只读的，但它会读元数据缓存、可能触发网络访问，
    # 而 dry-run 的契约是零调用 —— 实测过：把这段放在 repolist 之后，
    # dry-run 下包管理器仍被调用了一次。
    if dot_is_dry_run; then
        dot_info "[dry-run] would enable EPEL (needed for ripgrep/fd/bat/zoxide/delta/direnv)"
        DOT_EPEL_READY=1
        return 0
    fi

    # 已启用就别重复装。repolist 在两代 yum/dnf 上都可用。
    if $DOT_PKG repolist enabled 2>/dev/null | grep -qi '^[!*]*epel'; then
        DOT_EPEL_READY=1
        return 0
    fi

    dot_step 'enabling EPEL — RHEL/CentOS base repos lack most modern CLI tools'
    if _dot_sudo "$DOT_PKG" install -y epel-release >/dev/null 2>&1; then
        dot_success 'EPEL enabled'
    else
        # 不致命：没有 EPEL 只是让更多工具走回退链，而不是让引导失败。
        dot_tip 'could not enable EPEL; more tools will fall back to source builds'
        dot_tip "  enable it manually: sudo $DOT_PKG install -y epel-release"
    fi
    DOT_EPEL_READY=1
}

# 安装循环开始前的仓库准备。由 dot_pkg_prepare_repos 调用 ——
# 那个入口在 dry-run 下也会执行，所以这里的预告是可达的。
dot_platform_prepare_repos() {
    _dot_ensure_epel
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
        dnf)
            _dot_ensure_epel
            _dot_sudo dnf install -y "$_dot_pkg"
            ;;
        # yum 的 install -y 与 dnf 同义。分开写而不合并成一条 ——
        # 命令名必须与探测到的 DOT_PKG 一致，否则在只有 yum 的机器上
        # （RHEL/CentOS 7、Amazon Linux 2）会去调不存在的 dnf。
        yum)
            _dot_ensure_epel
            _dot_sudo yum install -y "$_dot_pkg"
            ;;
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
