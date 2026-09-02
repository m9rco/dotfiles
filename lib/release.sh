#!/usr/bin/env sh
#
# 从项目自己的 GitHub release 取预编译二进制。
#
# 存在理由：包源贫乏的发行版上，好几个默认工具在任何仓库里都没有 ——
# EPEL 7 没有 fzf；apt 没有 lazygit/gh/yq；dnf/yum 没有 direnv。而它们
# 都是 Go 写的，cargo 装不了。官方 release 的预编译二进制是唯一的路，
# 也是 spec 要求的那条（modern-cli-toolchain：预编译二进制优先于源码编译）。
#
# 与 lib/download.sh 的分工：那边是「取下来、验、解开」的通用原语，
# 这边只管 GitHub 的那套约定 —— 资产怎么命名、tag 怎么解析、二进制在
# 归档里的哪个位置。
#
# 本文件永不碰 PATH、永不设 DOT_PKG_PATH_NOTICE —— 那是 lib/pkg.sh 的
# 契约。保持单向依赖：pkg.sh -> release.sh -> download.sh。
#
# shellcheck shell=sh

[ -n "${DOT_RELEASE_SH_LOADED:-}" ] && return 0
DOT_RELEASE_SH_LOADED=1

_dot_rel_lib=${DOT_LIB_DIR:-$(dirname -- "$0")}
# shellcheck source=lib/log.sh
. "$_dot_rel_lib/log.sh"
# shellcheck source=lib/download.sh
. "$_dot_rel_lib/download.sh"

# 供测试把下载指向本地 fixture server。
#
# 刻意不写进 README 当用户开关：它决定二进制从哪来，暴露成配置项等于给
# 供应链开个口子。定位同 DOT_OSRELEASE_FILE（lib/detect.sh）与 DOT_FONT_DIR。
DOT_GITHUB_BASE=${DOT_GITHUB_BASE:-https://github.com}

# 一次引导内只判定一次 github 是否可达。
#
# 为什么需要：本次改动之前这些工具是「立刻失败」（0 个回退方式）。加了
# 回退之后，网络被黑洞的机器上 6 个工具各自超时重试，最坏要几分钟 ——
# 那是对离线机器的真实退化。首次连接失败就置位，后续全部短路。
# 同 DOT_RUSTUP_TRIED 的思路。
DOT_GITHUB_UNREACHABLE=${DOT_GITHUB_UNREACHABLE:-0}

# release 下载用更短的超时：见上面 DOT_GITHUB_UNREACHABLE 的说明。
# 字体那边 20s/2 次的值不动 —— 那是单个大文件，久经验证。
_DOT_REL_TIMEOUT=10
_DOT_REL_RETRY=1

# ---------------------------------------------------------------- 配方表

# _dot_release_recipe <逻辑名>
#
# 设置三个全局量（不用回显+切分：没有子 shell，且空的资产名能干净地
# 表示「这个 OS/架构没有资产」）：
#
#   _dot_rr_asset  资产文件名，{v} 是版本占位符。空 = 本平台没有
#   _dot_rr_kind   targz | zip | binary
#   _dot_rr_name   归档里那个可执行文件的**文件名**（不是路径）
#
# 三件事必须说清：
#
# 1. 刻意不做「架构词汇映射表」。三种词汇互不兼容：amd64/arm64（fzf gh
#    jq yq direnv）、x86_64/arm64（lazygit）、x86_64/aarch64（btop，若
#    将来加）。映射表只会把「哪个工具用哪套」的知识搬个地方再加一层
#    间接。资产名直接写出来，每行都能对着 release 页面用眼睛核 ——
#    与 platform/linux.sh 对包名的理由一致。
#
# 2. _dot_rr_name 是文件名而不是路径，因为路径不可预测：gh 的包是
#    gh_<版本>_linux_amd64/bin/gh（目录名带版本）。由 dot_dl_find_file
#    按名字定位。
#
# 3. {v} 就是模式开关：含 {v} 要先解析 tag；不含就直接用
#    releases/latest/download/<asset>，零额外请求。不需要单独的字段。
_dot_release_recipe() {
    _dot_rr_asset=''
    _dot_rr_kind=''
    _dot_rr_name=''

    case $1 in
        fzf)
            _dot_rr_kind=targz
            _dot_rr_name=fzf
            case "$DOT_OS/$DOT_ARCH" in
                linux/x86_64) _dot_rr_asset='fzf-{v}-linux_amd64.tar.gz' ;;
                linux/arm64) _dot_rr_asset='fzf-{v}-linux_arm64.tar.gz' ;;
                macos/x86_64) _dot_rr_asset='fzf-{v}-darwin_amd64.tar.gz' ;;
                macos/arm64) _dot_rr_asset='fzf-{v}-darwin_arm64.tar.gz' ;;
            esac
            ;;
        # lazygit 的资产名首字母大写（Linux/Darwin），且用 x86_64 而不是
        # amd64 —— 与 fzf 恰好相反。这就是不做映射表的原因。
        lazygit)
            _dot_rr_kind=targz
            _dot_rr_name=lazygit
            case "$DOT_OS/$DOT_ARCH" in
                linux/x86_64) _dot_rr_asset='lazygit_{v}_Linux_x86_64.tar.gz' ;;
                linux/arm64) _dot_rr_asset='lazygit_{v}_Linux_arm64.tar.gz' ;;
                macos/x86_64) _dot_rr_asset='lazygit_{v}_Darwin_x86_64.tar.gz' ;;
                macos/arm64) _dot_rr_asset='lazygit_{v}_Darwin_arm64.tar.gz' ;;
            esac
            ;;
        # gh 是唯一一个 macOS 侧换成 zip 的（而且是大写 O 的 macOS），
        # 二进制还嵌在 gh_<版本>_<平台>/bin/ 里。
        gh)
            _dot_rr_name=gh
            case "$DOT_OS/$DOT_ARCH" in
                linux/x86_64)
                    _dot_rr_kind=targz
                    _dot_rr_asset='gh_{v}_linux_amd64.tar.gz'
                    ;;
                linux/arm64)
                    _dot_rr_kind=targz
                    _dot_rr_asset='gh_{v}_linux_arm64.tar.gz'
                    ;;
                macos/x86_64)
                    _dot_rr_kind=zip
                    _dot_rr_asset='gh_{v}_macOS_amd64.zip'
                    ;;
                macos/arm64)
                    _dot_rr_kind=zip
                    _dot_rr_asset='gh_{v}_macOS_arm64.zip'
                    ;;
            esac
            ;;
        # jq/yq/direnv 都是裸二进制、且资产名不含版本 —— 可以直接走
        # releases/latest/download，连 tag 都不用解析。
        jq)
            _dot_rr_kind=binary
            _dot_rr_name=jq
            case "$DOT_OS/$DOT_ARCH" in
                linux/x86_64) _dot_rr_asset='jq-linux-amd64' ;;
                linux/arm64) _dot_rr_asset='jq-linux-arm64' ;;
                macos/x86_64) _dot_rr_asset='jq-macos-amd64' ;;
                macos/arm64) _dot_rr_asset='jq-macos-arm64' ;;
            esac
            ;;
        yq)
            _dot_rr_kind=binary
            _dot_rr_name=yq
            case "$DOT_OS/$DOT_ARCH" in
                linux/x86_64) _dot_rr_asset='yq_linux_amd64' ;;
                linux/arm64) _dot_rr_asset='yq_linux_arm64' ;;
                macos/x86_64) _dot_rr_asset='yq_darwin_amd64' ;;
                macos/arm64) _dot_rr_asset='yq_darwin_arm64' ;;
            esac
            ;;
        # direnv 的资产名是 direnv.<os>-<arch> —— 点号加连字符。
        #
        # 为什么不用它官方的 install.sh 走现成的 script: 回退：那个脚本是
        # #!/usr/bin/env bash 且用了 [[ ]]，而 _dot_pkg_try_script 是往
        # `sh -s --` 里灌，dash 上直接语法错误；它还把安装目录读作环境变量
        # bin_path，不认 --bin-dir。取 release 资产更直接也更可控。
        direnv)
            _dot_rr_kind=binary
            _dot_rr_name=direnv
            case "$DOT_OS/$DOT_ARCH" in
                linux/x86_64) _dot_rr_asset='direnv.linux-amd64' ;;
                linux/arm64) _dot_rr_asset='direnv.linux-arm64' ;;
                macos/x86_64) _dot_rr_asset='direnv.darwin-amd64' ;;
                macos/arm64) _dot_rr_asset='direnv.darwin-arm64' ;;
            esac
            ;;
    esac

    [ -n "$_dot_rr_asset" ]
}

# ---------------------------------------------------------------- tag 解析

# _dot_release_tag <owner/repo>
#
# 回显最新 release 的 tag。
#
# 刻意不用 api.github.com：未认证的 API 在共享出口 IP 上两三次调用内就
# 403 限流（实测），而引导是无人值守的 —— 一台 NAT 后的公司机器或 CI
# runner 会直接撞上。releases/latest 是 HTML 端点，它的 302 不吃 API
# 配额（实测一次 burst 解析 8 个仓库没被限）。
#
# 用 %{url_effective} 而不是 grep Location：免受 CRLF、header 大小写与
# 多跳重定向的影响。
_dot_release_tag() {
    command -v curl >/dev/null 2>&1 || return 1

    curl -fsSI -o /dev/null -w '%{url_effective}\n' -L \
        --retry "$_DOT_REL_RETRY" --connect-timeout "$_DOT_REL_TIMEOUT" \
        "$DOT_GITHUB_BASE/$1/releases/latest" 2>/dev/null |
        sed -n 's|.*/releases/tag/||p'
}

# tag -> 资产名里用的版本号。
#
# jq 的 tag 是 jq-1.8.2 —— 没有 v 前缀（实测）。所以只在 v 后面紧跟数字
# 时才剥，其余原样返回。天真的 ${tag#v} 对 jq 恰好也没事，真正会坏的是
# 反过来假设「所有 tag 都有 v」的那种写法。
_dot_release_version() {
    case $1 in
        v[0-9]*) printf '%s' "${1#v}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# 版本号形状校验 —— 代理守卫。
#
# 返回 200 而不重定向的代理会让 url_effective 等于请求 URL，sed 得到空串；
# 会改写 URL 的代理可能让我们拿到字面量 latest。不校验的话那个 latest 会
# 被代进 {v}，产生一个莫名的 404，而真正的原因是代理。
_dot_release_version_ok() {
    case $1 in
        '' | latest) return 1 ;;
        *[!0-9A-Za-z._-]*) return 1 ;;
        *[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------- 安装

# dot_release_install <逻辑名> <owner/repo>
#
# 成功时二进制已落在 ~/.local/bin 且可执行。返回非零表示这条路没走通 ——
# 调用方负责继续尝试别的回退方式。
#
# 单一临时目录清理点：字体模块在 4 个出口各写一次 rm -rf，加第五个出口
# 就会漏。这里把真正的逻辑放在 _dot_release_do 里，清理只写一次。
dot_release_install() {
    if [ "${DOT_NO_GITHUB_RELEASE:-0}" = 1 ]; then
        dot_info "  DOT_NO_GITHUB_RELEASE=1; not fetching $1 from GitHub releases"
        return 1
    fi

    if [ "$DOT_GITHUB_UNREACHABLE" = 1 ]; then
        dot_info "  github.com was unreachable earlier; not retrying for $1"
        return 1
    fi

    if ! _dot_release_recipe "$1"; then
        # 「没有配方」与「配方说本平台没有资产」是两件事，但对调用方是
        # 同一个结果。区分开说，否则 btop 在 macOS 上会看起来像配置漏了。
        if [ -n "$_dot_rr_kind" ]; then
            dot_info "  no prebuilt binary for $DOT_OS/$DOT_ARCH; not attempted"
        else
            dot_error "  no release-asset recipe for $1; not attempted"
            dot_tip "  add one to _dot_release_recipe in lib/release.sh"
        fi
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        dot_info "  neither curl nor wget is available; cannot fetch a release binary"
        return 1
    fi

    _dot_ri_tmp=$(mktemp -d) || {
        dot_error "cannot create temp dir"
        return 1
    }

    _dot_release_do "$1" "$2" "$_dot_ri_tmp"
    _dot_ri_rc=$?

    rm -rf "$_dot_ri_tmp"
    return "$_dot_ri_rc"
}

# 真正的下载-校验-解包-落地。调用方保证临时目录会被清掉。
_dot_release_do() {
    _dot_rd_tool=$1
    _dot_rd_repo=$2
    _dot_rd_tmp=$3

    # 资产名含 {v} 才需要解析 tag。不含的直接走 latest/download，
    # 省掉一次往返 —— jq/yq/direnv 都是这种。
    case $_dot_rr_asset in
        *'{v}'*)
            _dot_rd_tag=$(_dot_release_tag "$_dot_rd_repo")
            if [ -z "$_dot_rd_tag" ]; then
                if command -v curl >/dev/null 2>&1; then
                    dot_error "  cannot resolve the latest release of $_dot_rd_repo"
                    dot_tip '  a proxy that answers 200 without redirecting looks like this'
                    # 连不上 github 就别再为后面的工具逐个超时
                    DOT_GITHUB_UNREACHABLE=1
                    export DOT_GITHUB_UNREACHABLE
                else
                    # wget 没有干净的办法报告最终 URL，所以只有 wget 的机器
                    # 装不了这一类。说清缺的是什么，而不是含糊地失败。
                    dot_info '  resolving the latest release needs curl; not attempted'
                fi
                return 1
            fi

            _dot_rd_ver=$(_dot_release_version "$_dot_rd_tag")
            if ! _dot_release_version_ok "$_dot_rd_ver"; then
                dot_error "  implausible version from $_dot_rd_repo: '$_dot_rd_ver'"
                dot_tip '  something between here and github.com is rewriting redirects'
                return 1
            fi

            _dot_rd_file=$(printf '%s' "$_dot_rr_asset" | sed "s|{v}|$_dot_rd_ver|g")
            _dot_rd_url="$DOT_GITHUB_BASE/$_dot_rd_repo/releases/download/$_dot_rd_tag/$_dot_rd_file"
            dot_info "installing $_dot_rd_tool from $_dot_rd_repo $_dot_rd_tag (prebuilt binary)"
            ;;
        *)
            _dot_rd_file=$_dot_rr_asset
            _dot_rd_url="$DOT_GITHUB_BASE/$_dot_rd_repo/releases/latest/download/$_dot_rd_file"
            dot_info "installing $_dot_rd_tool from $_dot_rd_repo latest (prebuilt binary)"
            ;;
    esac

    _dot_rd_dl="$_dot_rd_tmp/$_dot_rd_file"
    if ! dot_dl_fetch "$_dot_rd_url" "$_dot_rd_dl" "$_DOT_REL_TIMEOUT" "$_DOT_REL_RETRY"; then
        dot_error "  download failed: $_dot_rd_url"
        return 1
    fi

    # 配方的 kind（targz/zip/binary，说的是「怎么解」）与 dot_dl_verify 的
    # kind（gzip/zip/binary，说的是「魔数是什么」）是两套词汇，targz 对应的
    # 魔数是 gzip。这里显式转换 —— 直接把 targz 传过去会撞上 verify 的
    # "unknown verify kind" 并被当成下载损坏（实测过：报的是「拿到的不是
    # targz」，而其实文件完全正常）。
    case $_dot_rr_kind in
        targz) _dot_rd_magic=gzip ;;
        *) _dot_rd_magic=$_dot_rr_kind ;;
    esac

    if ! dot_dl_verify "$_dot_rd_dl" "$_dot_rd_magic"; then
        dot_error "  what came back is not a $_dot_rd_magic archive"
        dot_error "  (got $(dot_dl_describe "$_dot_rd_dl"))"
        return 1
    fi

    # 解包（裸二进制无需解包），然后按文件名定位那个可执行文件
    case $_dot_rr_kind in
        binary)
            _dot_rd_bin=$_dot_rd_dl
            ;;
        targz | zip)
            _dot_rd_out="$_dot_rd_tmp/x"
            if [ "$_dot_rr_kind" = targz ]; then
                dot_dl_untar "$_dot_rd_dl" "$_dot_rd_out" || {
                    dot_error "  extraction failed: $_dot_rd_file"
                    return 1
                }
            else
                dot_dl_unzip "$_dot_rd_dl" "$_dot_rd_out" || {
                    dot_error "  extraction failed: $_dot_rd_file"
                    return 1
                }
            fi

            _dot_rd_bin=$(dot_dl_find_file "$_dot_rd_out" "$_dot_rr_name")
            if [ -z "$_dot_rd_bin" ]; then
                dot_error "  no '$_dot_rr_name' inside $_dot_rd_file"
                dot_tip '  the upstream archive layout probably changed'
                return 1
            fi
            ;;
    esac

    _dot_release_place "$_dot_rd_bin" "$_dot_rr_name"
}

# 把二进制放进 ~/.local/bin。
#
# 装到 ~/.local/bin 而不是 /usr/local/bin：免提权，且与本仓库「不碰系统
# 目录」的前提一致。zsh 配置里已经有这个目录（10-path.zsh）。
#
# 先写临时名再 mv，不直接 cp 到目标：覆盖一个**正在运行**的二进制在 Linux
# 上是 ETXTBSY（重跑引导时 tmux 里开着的进程就是这情形）。mv 是
# rename(2)，同一个文件系统上永远成功，老进程继续用它那个 inode。
# 顺带也避免了「拷到一半被另一个 shell 解析到」的半截文件。
#
# 刻意不用 dot_write：它读 stdin、把旧文件备份进 ~/.dotfiles-backup/、
# 并 chmod 644。每次升级把一个十几 MB 的二进制备份进配置备份目录是 bug
# 不是特性，而 644 的二进制根本没法执行。lib/README.md 说所有写入走
# fs.sh，_dot_pkg_try_script 已经是既有的例外 —— 别来「修好」这里。
_dot_release_place() {
    _dot_rp_src=$1
    _dot_rp_name=$2
    _dot_rp_dir="$HOME/.local/bin"

    mkdir -p "$_dot_rp_dir" 2>/dev/null || {
        dot_error "cannot create $_dot_rp_dir"
        return 1
    }

    _dot_rp_tmp="$_dot_rp_dir/.$_dot_rp_name.new"
    cp "$_dot_rp_src" "$_dot_rp_tmp" 2>/dev/null || {
        dot_error "cannot write to $_dot_rp_dir"
        rm -f "$_dot_rp_tmp"
        return 1
    }

    # tar/zip 会保留可执行位，但裸 curl 下载的是 0644 —— 显式设一次，
    # 两条路径就都对了
    chmod 0755 "$_dot_rp_tmp" 2>/dev/null || {
        dot_error "cannot chmod $_dot_rp_tmp"
        rm -f "$_dot_rp_tmp"
        return 1
    }

    mv -f "$_dot_rp_tmp" "$_dot_rp_dir/$_dot_rp_name" || {
        dot_error "cannot install into $_dot_rp_dir"
        rm -f "$_dot_rp_tmp"
        return 1
    }
}
