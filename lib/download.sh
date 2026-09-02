#!/usr/bin/env sh
#
# 下载与归档原语。零 GitHub 知识、零字体知识 —— 只负责「把 URL 取下来、
# 确认拿到的确实是那种文件、解开它」。
#
# 这些函数原先是 modules/fonts/module.sh 里的 _dot_font_* 私有 helper。
# 提升到 lib/ 是因为 release 二进制回退（lib/release.sh）要用同一套 ——
# 尤其是「代理返回 HTML 登录页」的识别：那是字体模块踩出来的经验，
# 在两处各写一遍就是 test/lint.sh 存在要防的那种漂移。
#
# shellcheck shell=sh

[ -n "${DOT_DOWNLOAD_SH_LOADED:-}" ] && return 0
DOT_DOWNLOAD_SH_LOADED=1

_dot_dl_lib=${DOT_LIB_DIR:-$(dirname -- "$0")}
# shellcheck source=lib/log.sh
. "$_dot_dl_lib/log.sh"

# ---------------------------------------------------------------- 下载

# dot_dl_fetch <url> <输出路径> [连接超时秒数] [重试次数]
#
# 超时与重试可调：字体是一次性的大文件，慢一点无所谓，所以沿用久经验证的
# 20s/2 次；release 二进制要连着取好几个，网络被黑洞时逐个超时会让引导
# 看起来挂死，那边用 10s/1 次。默认值保持字体原有行为。
dot_dl_fetch() {
    _dot_dl_url=$1
    _dot_dl_out=$2
    _dot_dl_ct=${3:-20}
    _dot_dl_retry=${4:-2}

    if command -v curl >/dev/null 2>&1; then
        # -L 跟随重定向（latest/download 一定会重定向）
        # -f 让 HTTP 错误码变成非零退出，否则错误页会被当成正常内容保存
        curl -fsSL --retry "$_dot_dl_retry" --connect-timeout "$_dot_dl_ct" \
            -o "$_dot_dl_out" "$_dot_dl_url" </dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=$((_dot_dl_retry + 1)) --timeout="$_dot_dl_ct" \
            -O "$_dot_dl_out" "$_dot_dl_url"
    else
        dot_error 'neither curl nor wget is available'
        return 1
    fi
}

# ---------------------------------------------------------------- 校验

# 文件头若干字节的十六进制。
#
# 用十六进制而不是 od -An -c 的字符形式：zip 的魔数 PK 恰好可打印，
# 所以字体那边用字符形式能用，但 gzip 的 1f8b 与 ELF 的 7f454c46 不行。
# 统一走十六进制才能覆盖三种。
#
# `od -A n -t x1` 用分开的形式而不是 -An -tx1：busybox 的 od 对合并写法
# 的支持不一致，而 Alpine 在支持列表里（lib/detect.sh 的 apk 分支）。
_dot_dl_magic() {
    dd if="$1" bs=1 count="${2:-4}" 2>/dev/null |
        od -A n -t x1 | tr -d ' \n'
}

# dot_dl_verify <文件> <kind>
#
# kind: zip | gzip | binary
#
# 为什么必须验：curl -f 只能拦住 HTTP 错误码，而代理/CDN 常常用 200 返回
# 一个 HTML 登录页或错误页。那种内容会被当成正常下载存下来，然后在解包时
# 报一句莫名的错。魔数是唯一能在解包前识破它的手段。
#
# 刻意不做 sha256 校验：checksum 文件与资产同源、同一个 TLS 连接，能替换
# 资产的人也能替换 checksum。它防的是传输损坏（TLS 已经覆盖）与截断
# （gzip 解压失败已经覆盖），防不住被投毒的 release —— 那需要
# sigstore/cosign 或 `gh attestation verify`，而用 gh 去装 gh 是循环依赖。
# 明示接受的残余风险：CDN 返回一个陈旧但结构完好的对象会通过校验，
# 后果是版本不对，不是代码执行。
dot_dl_verify() {
    _dot_vf=$1
    _dot_vk=$2

    [ -s "$_dot_vf" ] || return 1

    case $_dot_vk in
        zip)
            case $(_dot_dl_magic "$_dot_vf" 2) in
                504b) ;;
                *) return 1 ;;
            esac
            # 魔数只证明前两字节像 zip；有 unzip 时再做一次完整性测试。
            # unzip 不一定装了（rockylinux:9 最小镜像里就没有），
            # 所以它是加分项而不是前提。
            if command -v unzip >/dev/null 2>&1; then
                unzip -tqq "$_dot_vf" >/dev/null 2>&1 || return 1
            fi
            ;;
        gzip)
            case $(_dot_dl_magic "$_dot_vf" 2) in
                1f8b) ;;
                *) return 1 ;;
            esac
            ;;
        binary)
            # 裸二进制（jq/yq/direnv 就是这么发的）。用白名单而不是
            # 「不像 HTML 就放过」—— 后者会诱人加个体积阈值，而
            # 「小于 100KB 就算坏」是那种五年后静默失效的魔数。
            # 这三个项目发的东西恰好就是 {ELF, Mach-O} 这个闭集合。
            case $(_dot_dl_magic "$_dot_vf" 4) in
                7f454c46) ;;                                  # ELF
                feedface | cefaedfe | feedfacf | cffaedfe) ;; # Mach-O 32/64
                cafebabe | bebafeca) ;;                       # Mach-O universal
                *) return 1 ;;
            esac
            ;;
        *)
            dot_error "unknown verify kind: $_dot_vk"
            return 1
            ;;
    esac
}

# 出错时说明拿到的是什么，便于诊断（常见情形：代理返回 HTML 登录页）
dot_dl_describe() {
    if command -v file >/dev/null 2>&1; then
        file -b "$1" 2>/dev/null | head -c 80
    else
        printf '%s bytes' "$(wc -c <"$1" | tr -d ' ')"
    fi
}

# ---------------------------------------------------------------- 解包

dot_dl_unzip() {
    _dot_uz_zip=$1
    _dot_uz_dst=$2

    mkdir -p "$_dot_uz_dst" || return 1

    if command -v unzip >/dev/null 2>&1; then
        unzip -qo "$_dot_uz_zip" -d "$_dot_uz_dst" >/dev/null 2>&1
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$_dot_uz_zip" -C "$_dot_uz_dst" >/dev/null 2>&1
    elif command -v python3 >/dev/null 2>&1; then
        # 兜底：最小容器里可能既没 unzip 也没 bsdtar，但通常有 python3
        python3 -c "
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
" "$_dot_uz_zip" "$_dot_uz_dst" >/dev/null 2>&1
    else
        dot_error 'no extraction tool available (need unzip, bsdtar or python3)'
        return 1
    fi
}

# dot_dl_untar <tar.gz> <目标目录>
#
# 平铺解包，刻意不用 --strip-components：busybox 的 tar 没有这个选项，
# 而 Alpine/apk 在支持列表里且没有 CI job 覆盖 —— 依赖它会在那里静默失败
# （解不出东西，但 tar 自己不报错）。归档里那个可执行文件由
# dot_dl_find_file 按文件名定位，本来就不需要 strip 掉前缀。
#
# `gzip -dc | tar -xf -` 而不是 `tar -xzf`：-z 不是所有 tar 都有。
# 管道形式零成本，没必要赌。
#
# 不加 python3 的 tarfile 兜底 —— 与 dot_dl_unzip 刻意不对称：unzip 确实
# 常常缺（所以那边有），而一台没有 tar 的 Linux/macOS 机器不存在；
# 且 python3 的 tarfile 在 3.12+ 改过 filter= 的默认行为。
dot_dl_untar() {
    _dot_ut_src=$1
    _dot_ut_dst=$2

    mkdir -p "$_dot_ut_dst" || return 1

    if command -v gzip >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
        gzip -dc "$_dot_ut_src" | tar -xf - -C "$_dot_ut_dst" 2>/dev/null && return 0
    fi
    if command -v tar >/dev/null 2>&1; then
        tar -xzf "$_dot_ut_src" -C "$_dot_ut_dst" 2>/dev/null && return 0
    fi
    if command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$_dot_ut_src" -C "$_dot_ut_dst" 2>/dev/null && return 0
    fi

    dot_error 'no extraction tool available (need tar+gzip or bsdtar)'
    return 1
}

# dot_dl_find_file <目录> <文件名>
#
# 在解开的目录树里按**文件名**找，回显第一个命中的路径。
#
# 按名字找而不是按路径拼，是因为路径不可预测：gh 的包是
# gh_<版本>_linux_amd64/bin/gh（目录名带版本），btop 的是 ./btop/bin/btop
# （带 ./ 前缀）。按名字找同时也就不需要 --strip-components 了。
#
# -type f 很关键：btop 的包里 ./btop/ 是目录、./btop/bin/btop 才是文件，
# 不加这个限定会先命中那个目录。
#
# 刻意不加 -perm：各 find 实现的 -perm 语法有差异，而这里没有收益 ——
# 精确的 -name 已经足够（实测过：duf 包里有 duf.1，gh 包里约 200 个
# manpage 都叫 gh-*.1，都不会被精确名字命中）。
dot_dl_find_file() {
    find "$1" -type f -name "$2" -print 2>/dev/null | head -n 1
}
