#!/usr/bin/env sh
#
# 平台探测。导出一组 DOT_* 变量作为上层的唯一平台事实来源。
#
# 契约（modules/ 只允许读这些，不得自己调 uname 或读 /etc/os-release）：
#
#   DOT_OS           macos | linux | windows
#   DOT_ARCH         arm64 | x86_64
#   DOT_DISTRO       debian|ubuntu|fedora|rhel|arch|alpine|suse|unknown（仅 linux，其余为空）
#   DOT_PKG          brew | apt | dnf | pacman | apk | winget | scoop
#   DOT_WSL          1 | 0
#   DOT_HEADLESS     1 | 0
#   DOT_BREW_PREFIX  Homebrew 前缀，未安装时为空
#   DOT_PKG_MISSING  1 表示 DOT_PKG 指定的管理器尚未安装，需要 ensure 步骤
#
# 探测本身零副作用 —— 不装任何东西、不写任何文件，这样 `--info` 可以安全调用。
# 缺失的包管理器由 dot_detect_ensure_pkg 在真实执行阶段安装。
#
# shellcheck shell=sh

[ -n "${DOT_DETECT_SH_LOADED:-}" ] && return 0
DOT_DETECT_SH_LOADED=1

# DOT_LIB_DIR 由 bootstrap.sh 设置。直接 source 本文件时（测试）回退到 $0 所在目录。
# log.sh 有 source 保护，重复 source 无副作用。
# shellcheck source=lib/log.sh
. "${DOT_LIB_DIR:-$(dirname -- "$0")}/log.sh"

# ---------------------------------------------------------------- OS 与架构

_dot_detect_os() {
    # DOT_OS 允许被预设，供 Windows 侧（bootstrap.ps1 转 WSL）与测试注入
    if [ -n "${DOT_OS:-}" ]; then
        return 0
    fi

    case $(uname -s 2>/dev/null) in
        Darwin) DOT_OS=macos ;;
        Linux) DOT_OS=linux ;;
        # MSYS/Cygwin/Git-Bash 下的 uname；原生 Windows 走 bootstrap.ps1 而非这里
        MINGW* | MSYS* | CYGWIN*) DOT_OS=windows ;;
        *)
            dot_error "unsupported OS: $(uname -s 2>/dev/null || echo unknown)"
            dot_error "supported: macOS (Darwin), Linux, Windows"
            exit 1
            ;;
    esac
}

_dot_detect_arch() {
    [ -n "${DOT_ARCH:-}" ] && return 0

    case $(uname -m 2>/dev/null) in
        arm64 | aarch64) DOT_ARCH=arm64 ;;
        x86_64 | amd64) DOT_ARCH=x86_64 ;;
        *)
            dot_error "unsupported architecture: $(uname -m 2>/dev/null || echo unknown)"
            dot_error "supported: arm64 (arm64/aarch64), x86_64 (x86_64/amd64)"
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------- Linux 发行版

# 把 os-release 的 ID / ID_LIKE 值映射到我们关心的发行版族。
# ID_LIKE 可能是空格分隔的多个值（如 "ubuntu debian"），按顺序取第一个能识别的。
_dot_distro_from_ids() {
    for _dot_id in $1; do
        case $_dot_id in
            debian) echo debian && return 0 ;;
            ubuntu) echo ubuntu && return 0 ;;
            fedora) echo fedora && return 0 ;;
            rhel | centos | rocky | almalinux) echo rhel && return 0 ;;
            arch | archlinux) echo arch && return 0 ;;
            alpine) echo alpine && return 0 ;;
            suse | opensuse | opensuse-leap | opensuse-tumbleweed | sles) echo suse && return 0 ;;
        esac
    done
    return 1
}

# 只从 os-release 读，不用 lsb_release —— 后者不保证存在。
# 用 sed 提取而非 source 整个文件，避免把 os-release 里的任意变量灌进当前 shell。
# 路径可用 DOT_OSRELEASE_FILE 覆盖，供测试注入伪造文件。
_dot_osrelease_get() {
    sed -n "s/^$1=//p" "${DOT_OSRELEASE_FILE:-/etc/os-release}" 2>/dev/null |
        head -n 1 |
        sed 's/^"//; s/"$//; s/^'\''//; s/'\''$//'
}

_dot_detect_distro() {
    DOT_DISTRO=''
    [ "$DOT_OS" = linux ] || return 0
    [ -n "${DOT_DISTRO_OVERRIDE:-}" ] && DOT_DISTRO=$DOT_DISTRO_OVERRIDE && return 0

    if [ ! -r "${DOT_OSRELEASE_FILE:-/etc/os-release}" ]; then
        DOT_DISTRO=unknown
        dot_tip "os-release not readable; distro unknown, package selection may be limited"
        return 0
    fi

    # ID 优先；ID 未知时回退 ID_LIKE（覆盖 linuxmint / pop 这类衍生发行版）
    if DOT_DISTRO=$(_dot_distro_from_ids "$(_dot_osrelease_get ID)"); then
        return 0
    fi
    if DOT_DISTRO=$(_dot_distro_from_ids "$(_dot_osrelease_get ID_LIKE)"); then
        return 0
    fi

    DOT_DISTRO=unknown
    dot_tip "unrecognized distro (ID=$(_dot_osrelease_get ID)); falling back to generic handling"
}

# ---------------------------------------------------------------- Homebrew 前缀

# 必须探测而非硬编码 —— 旧脚本写死 /usr/local/bin/brew，在 Apple Silicon 上直接失效。
_dot_detect_brew_prefix() {
    DOT_BREW_PREFIX=''

    if command -v brew >/dev/null 2>&1; then
        DOT_BREW_PREFIX=$(brew --prefix 2>/dev/null) && [ -n "$DOT_BREW_PREFIX" ] && return 0
    fi

    # brew 不在 PATH 中（常见于全新 shell 尚未加载 shellenv），按已知位置探测
    for _dot_prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
        if [ -x "$_dot_prefix/bin/brew" ]; then
            DOT_BREW_PREFIX=$_dot_prefix
            return 0
        fi
    done

    DOT_BREW_PREFIX=''
}

# ---------------------------------------------------------------- 包管理器

_dot_detect_pkg() {
    DOT_PKG=''
    DOT_PKG_MISSING=0
    [ -n "${DOT_PKG_OVERRIDE:-}" ] && DOT_PKG=$DOT_PKG_OVERRIDE && return 0

    case $DOT_OS in
        macos)
            # macOS 上 brew 是唯一选择。未安装时仍设为 brew 并标记 missing，
            # 由 ensure 步骤在真实执行阶段安装（保持探测本身零副作用）。
            DOT_PKG=brew
            [ -n "$DOT_BREW_PREFIX" ] || DOT_PKG_MISSING=1
            ;;
        windows)
            if command -v scoop >/dev/null 2>&1; then
                DOT_PKG=scoop
            elif command -v winget >/dev/null 2>&1; then
                DOT_PKG=winget
            else
                DOT_PKG=scoop
                DOT_PKG_MISSING=1
            fi
            ;;
        linux)
            # 优先用发行版原生管理器：系统包与系统库版本匹配，且不需要额外引导。
            case $DOT_DISTRO in
                debian | ubuntu) command -v apt-get >/dev/null 2>&1 && DOT_PKG=apt ;;
                fedora | rhel) command -v dnf >/dev/null 2>&1 && DOT_PKG=dnf ;;
                arch) command -v pacman >/dev/null 2>&1 && DOT_PKG=pacman ;;
                alpine) command -v apk >/dev/null 2>&1 && DOT_PKG=apk ;;
                suse) command -v zypper >/dev/null 2>&1 && DOT_PKG=zypper ;;
            esac

            # 发行版未知或原生管理器缺失时，按实际存在的命令兜底探测
            if [ -z "$DOT_PKG" ]; then
                for _dot_try in apt-get:apt dnf:dnf pacman:pacman apk:apk zypper:zypper; do
                    _dot_cmd=${_dot_try%%:*}
                    _dot_name=${_dot_try##*:}
                    if command -v "$_dot_cmd" >/dev/null 2>&1; then
                        DOT_PKG=$_dot_name
                        break
                    fi
                done
            fi

            # Linuxbrew 作为最后手段（无原生管理器的环境，如无 root 的定制系统）
            if [ -z "$DOT_PKG" ] && [ -n "$DOT_BREW_PREFIX" ]; then
                DOT_PKG=brew
            fi

            if [ -z "$DOT_PKG" ]; then
                dot_error "no supported package manager found"
                dot_error "expected one of: apt, dnf, pacman, apk, zypper, brew"
                exit 1
            fi
            ;;
    esac
}

# 在真实执行阶段确保包管理器可用。与探测分离，因此 --info / --dry-run 不会触发安装。
# 返回非零表示无法就绪，调用方应中止安装类操作。
dot_detect_ensure_pkg() {
    [ "${DOT_PKG_MISSING:-0}" = 1 ] || return 0

    if [ "${DOT_DRY_RUN:-0}" = 1 ]; then
        dot_info "[dry-run] would install package manager: $DOT_PKG"
        return 0
    fi

    case $DOT_OS in
        macos)
            dot_step "Installing Homebrew"
            dot_info "Homebrew not found; installing from brew.sh"
            if ! /bin/bash -c \
                "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
                dot_error "Homebrew installation failed"
                return 1
            fi
            # 重新探测以拿到实际前缀（Apple Silicon 与 Intel 落点不同）
            _dot_detect_brew_prefix
            if [ -z "$DOT_BREW_PREFIX" ]; then
                dot_error "Homebrew installed but prefix not found"
                return 1
            fi
            eval "$("$DOT_BREW_PREFIX/bin/brew" shellenv)"
            DOT_PKG_MISSING=0
            dot_success "Homebrew ready at $DOT_BREW_PREFIX"
            ;;
        *)
            dot_error "package manager '$DOT_PKG' is not available and cannot be auto-installed"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------- 运行环境

_dot_detect_wsl() {
    DOT_WSL=0
    [ "$DOT_OS" = linux ] || return 0

    # WSL1 与 WSL2 都在内核版本串里带 microsoft；osrelease 优先，个别镜像只有 /proc/version。
    # 探测路径可用 DOT_WSL_PROBE_FILES 覆盖，供测试注入。
    for _dot_src in ${DOT_WSL_PROBE_FILES:-/proc/sys/kernel/osrelease /proc/version}; do
        if [ -r "$_dot_src" ] && grep -qi microsoft "$_dot_src" 2>/dev/null; then
            DOT_WSL=1
            return 0
        fi
    done
}

# 无图形/非交互环境：跳过 GUI 应用与字体，并且不改默认 shell。
_dot_detect_headless() {
    DOT_HEADLESS=0

    if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ] || [ -n "${SSH_CLIENT:-}" ]; then
        DOT_HEADLESS=1
    elif [ -n "${CI:-}" ]; then
        DOT_HEADLESS=1
    else
        # 容器标记文件。路径可用 DOT_CONTAINER_PROBE_FILES 覆盖 ——
        # 否则在容器里跑测试时 /.dockerenv 恒存在，「无标记则非 headless」
        # 那条断言永远无法通过（CI 的容器 job 实测如此）。
        for _dot_ch in ${DOT_CONTAINER_PROBE_FILES:-/.dockerenv /run/.containerenv}; do
            if [ -f "$_dot_ch" ]; then
                DOT_HEADLESS=1
                break
            fi
        done
    fi
}

# ---------------------------------------------------------------- 入口

# 执行全部探测。幂等，可重复调用。
dot_detect() {
    _dot_detect_os
    _dot_detect_arch
    _dot_detect_distro
    _dot_detect_brew_prefix
    _dot_detect_pkg
    _dot_detect_wsl
    _dot_detect_headless

    export DOT_OS DOT_ARCH DOT_DISTRO DOT_PKG DOT_WSL DOT_HEADLESS \
        DOT_BREW_PREFIX DOT_PKG_MISSING
}

# 打印探测结果。零副作用，供 --info 与 CI 验证使用。
dot_detect_info() {
    printf 'DOT_OS           %s\n' "$DOT_OS"
    printf 'DOT_ARCH         %s\n' "$DOT_ARCH"
    printf 'DOT_DISTRO       %s\n' "${DOT_DISTRO:-(n/a)}"
    printf 'DOT_PKG          %s%s\n' "$DOT_PKG" \
        "$([ "${DOT_PKG_MISSING:-0}" = 1 ] && echo ' (not installed yet)')"
    printf 'DOT_WSL          %s\n' "$DOT_WSL"
    printf 'DOT_HEADLESS     %s\n' "$DOT_HEADLESS"
    printf 'DOT_BREW_PREFIX  %s\n' "${DOT_BREW_PREFIX:-(none)}"
}
