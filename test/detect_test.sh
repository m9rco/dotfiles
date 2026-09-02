#!/usr/bin/env sh
#
# lib/detect.sh 的断言测试。可在任意 POSIX sh 下运行，无需容器：
# 通过 DOT_OSRELEASE_FILE / DOT_WSL_PROBE_FILES 注入伪造文件来覆盖各发行版与 WSL 分支。
#
#   sh test/detect_test.sh          # 用默认 sh
#   dash test/detect_test.sh        # 用 dash 验证 POSIX 兼容性
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
DOT_LIB_DIR="$DOT_REPO/lib"
export DOT_LIB_DIR

DOT_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$DOT_TEST_TMP"' EXIT INT TERM

_pass=0
_fail=0

# 在子 shell 中带指定环境跑一次探测，回显某个变量的值。
# 子 shell 隔离保证前一个用例的 DOT_* 不会渗透到下一个。
probe() {
    _var=$1
    shift
    env "$@" \
        DOT_LIB_DIR="$DOT_LIB_DIR" \
        sh -c ". \"\$DOT_LIB_DIR/detect.sh\"; dot_detect; eval \"printf '%s' \\\"\\\$$_var\\\"\"" \
        2>/dev/null
}

expect() {
    _desc=$1
    _want=$2
    _got=$3
    if [ "$_want" = "$_got" ]; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$_desc"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$_desc" "$_want" "$_got"
    fi
}

# 生成一份伪造的 os-release
mkosrelease() {
    _f="$DOT_TEST_TMP/os-release-$1"
    shift
    : >"$_f"
    for _line in "$@"; do
        printf '%s\n' "$_line" >>"$_f"
    done
    printf '%s' "$_f"
}

printf '== architecture normalization ==\n'
expect 'aarch64 -> arm64' arm64 "$(probe DOT_ARCH DOT_ARCH=arm64)"
expect 'amd64 -> x86_64' x86_64 "$(probe DOT_ARCH DOT_ARCH=x86_64)"

printf '\n== distro from ID ==\n'
f=$(mkosrelease ubuntu 'ID=ubuntu' 'ID_LIKE=debian')
expect 'ID=ubuntu -> ubuntu' ubuntu \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apt)"

f=$(mkosrelease debian 'ID=debian')
expect 'ID=debian -> debian' debian \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apt)"

f=$(mkosrelease fedora 'ID=fedora')
expect 'ID=fedora -> fedora' fedora \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=dnf)"

f=$(mkosrelease arch 'ID=arch')
expect 'ID=arch -> arch' arch \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=pacman)"

f=$(mkosrelease alpine 'ID=alpine')
expect 'ID=alpine -> alpine' alpine \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apk)"

f=$(mkosrelease rocky 'ID=rocky' 'ID_LIKE="rhel centos fedora"')
expect 'ID=rocky -> rhel' rhel \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=dnf)"

# Amazon Linux 2 只有 yum。归入 rhel 族因为包名与 RHEL 一致，
# 差别只在包管理器命令 —— 那个差别由包管理器探测按命令是否存在解决。
f=$(mkosrelease amzn 'ID=amzn' 'ID_LIKE="centos rhel fedora"')
expect 'ID=amzn -> rhel' rhel \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=yum)"

f=$(mkosrelease amzn2023 'ID="amzn"' 'VERSION_ID="2023"')
expect 'ID=amzn (quoted, no ID_LIKE) -> rhel' rhel \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=yum)"

printf '\n== distro falls back to ID_LIKE ==\n'
f=$(mkosrelease mint 'ID=linuxmint' 'ID_LIKE="ubuntu debian"')
expect 'ID=linuxmint -> ubuntu (via ID_LIKE)' ubuntu \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apt)"

f=$(mkosrelease pop 'ID=pop' 'ID_LIKE="ubuntu debian"')
expect 'ID=pop -> ubuntu (via ID_LIKE)' ubuntu \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apt)"

printf '\n== quoted values are unquoted ==\n'
f=$(mkosrelease quoted 'ID="ubuntu"')
expect 'ID="ubuntu" (double-quoted) -> ubuntu' ubuntu \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apt)"

f=$(mkosrelease squoted "ID='arch'")
expect "ID='arch' (single-quoted) -> arch" arch \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=pacman)"

printf '\n== unknown distro ==\n'
f=$(mkosrelease weird 'ID=plan9' 'ID_LIKE=beos')
expect 'unrecognized ID and ID_LIKE -> unknown' unknown \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apt)"

expect 'missing os-release -> unknown' unknown \
    "$(probe DOT_DISTRO DOT_OS=linux DOT_OSRELEASE_FILE="$DOT_TEST_TMP/nonexistent" \
        DOT_PKG_OVERRIDE=apt)"

printf '\n== os-release must not leak variables ==\n'
# os-release 里的任意变量不应被灌进当前 shell（我们用 sed 提取而非 source）
f=$(mkosrelease evil 'ID=debian' 'PRETTY_NAME="pwned"')
leaked=$(env DOT_OS=linux DOT_OSRELEASE_FILE="$f" DOT_PKG_OVERRIDE=apt \
    DOT_LIB_DIR="$DOT_LIB_DIR" \
    sh -c '. "$DOT_LIB_DIR/detect.sh"; dot_detect; printf "%s" "${PRETTY_NAME:-clean}"' 2>/dev/null)
expect 'PRETTY_NAME not sourced into shell' clean "$leaked"

printf '\n== WSL detection ==\n'
wsl_file="$DOT_TEST_TMP/osrelease-wsl"
printf '5.15.90.1-microsoft-standard-WSL2\n' >"$wsl_file"
expect 'kernel with microsoft -> WSL=1' 1 \
    "$(probe DOT_WSL DOT_OS=linux DOT_WSL_PROBE_FILES="$wsl_file" DOT_PKG_OVERRIDE=apt)"

wsl_upper="$DOT_TEST_TMP/osrelease-wsl-upper"
printf '4.4.0-19041-Microsoft\n' >"$wsl_upper"
expect 'case-insensitive Microsoft -> WSL=1' 1 \
    "$(probe DOT_WSL DOT_OS=linux DOT_WSL_PROBE_FILES="$wsl_upper" DOT_PKG_OVERRIDE=apt)"

native_file="$DOT_TEST_TMP/osrelease-native"
printf '6.1.0-18-amd64\n' >"$native_file"
expect 'native linux kernel -> WSL=0' 0 \
    "$(probe DOT_WSL DOT_OS=linux DOT_WSL_PROBE_FILES="$native_file" DOT_PKG_OVERRIDE=apt)"

expect 'missing probe files -> WSL=0' 0 \
    "$(probe DOT_WSL DOT_OS=linux DOT_WSL_PROBE_FILES="$DOT_TEST_TMP/nope" DOT_PKG_OVERRIDE=apt)"

expect 'macOS is never WSL' 0 "$(probe DOT_WSL DOT_OS=macos)"

printf '\n== headless detection ==\n'
expect 'CI set -> headless' 1 "$(probe DOT_HEADLESS CI=true)"
expect 'SSH_CONNECTION set -> headless' 1 "$(probe DOT_HEADLESS SSH_CONNECTION='1.2.3.4 22 5.6.7.8 22')"
expect 'SSH_TTY set -> headless' 1 "$(probe DOT_HEADLESS SSH_TTY=/dev/pts/0)"
expect 'SSH_CLIENT set -> headless' 1 "$(probe DOT_HEADLESS SSH_CLIENT='1.2.3.4 22 22')"
# 显式清空这些变量，避免测试本身跑在 SSH/CI 里时干扰结果。
# 容器标记也要指向不存在的路径 —— 在容器里跑测试时 /.dockerenv 恒存在，
# 否则这条断言永远失败（CI 的容器 job 实测如此）。
expect 'no markers -> not headless' 0 \
    "$(probe DOT_HEADLESS CI= SSH_CONNECTION= SSH_TTY= SSH_CLIENT= \
        DOT_CONTAINER_PROBE_FILES="$DOT_TEST_TMP/no-such-container-marker")"

# 反面：容器标记存在时必须是 headless
printf 'marker\n' >"$DOT_TEST_TMP/fake-dockerenv"
expect 'container marker -> headless' 1 \
    "$(probe DOT_HEADLESS CI= SSH_CONNECTION= SSH_TTY= SSH_CLIENT= \
        DOT_CONTAINER_PROBE_FILES="$DOT_TEST_TMP/fake-dockerenv")"

printf '\n== distro is empty on non-linux ==\n'
expect 'macOS has no distro' '' "$(probe DOT_DISTRO DOT_OS=macos)"

printf '\n== package manager selection ==\n'
expect 'macOS -> brew' brew "$(probe DOT_PKG DOT_OS=macos)"

# RHEL 族的 dnf / yum 选择。用 PATH 里的替身可执行文件控制「哪个命令存在」——
# 比遮蔽 command -v 更接近真实，探测代码原样跑。
#
# 替身目录必须是包管理器的唯一来源，所以下面把 PATH 收窄到只有它。
# 但探测本身要用 uname/sed/head/grep，于是给这些命令建软链进替身目录。
#
# 收窄 PATH 是必须的：兜底探测会找 apt-get，而 Debian/Ubuntu 上它真实存在，
# 于是「未知发行版应选到 yum」会选到 apt。开发机是 macOS、没有任何 Linux
# 包管理器，这个缺陷在本机测不出来 —— CI 的 ubuntu 与 debian 容器
# 三个 job 一起红了才暴露。
mkstubdir() {
    _sd="$DOT_TEST_TMP/stub-$1"
    mkdir -p "$_sd"
    shift

    # 探测代码与 probe 本身依赖的真实工具，按实际位置软链进来。
    # sh 也要 —— probe 用 `env ... sh -c` 启动子 shell，PATH 收窄后
    # 连解释器都找不到，结果是所有用例回显空串。
    for _real in sh uname sed head grep; do
        _p=$(command -v "$_real" 2>/dev/null) || continue
        ln -sf "$_p" "$_sd/$_real" 2>/dev/null || true
    done

    for _cmd in "$@"; do
        printf '#!/bin/sh\nexit 0\n' >"$_sd/$_cmd"
        chmod +x "$_sd/$_cmd"
    done
    printf '%s' "$_sd"
}

rhel_os=$(mkosrelease rhel8 'ID=rhel' 'ID_LIKE=fedora')

# 下面这组关掉兜底探测（DOT_PKG_NO_FALLBACK=1）。必须关 ——
# 兜底列表里也有 yum，不关的话撤掉 rhel 分支后兜底会接住，
# 断言照样通过，等于什么都没测。这是变异测试实际暴露出来的。
probe_nofb() {
    _v=$1
    shift
    probe "$_v" DOT_PKG_NO_FALLBACK=1 "$@"
}

# RHEL 8+：dnf 与 yum 都存在，必须选 dnf —— yum 只是指向 dnf 的兼容 shim
d=$(mkstubdir both dnf yum)
expect 'rhel with both dnf and yum -> dnf' dnf \
    "$(probe_nofb DOT_PKG DOT_OS=linux DOT_OSRELEASE_FILE="$rhel_os" PATH="$d")"

# RHEL/CentOS 7、Amazon Linux 2：只有 yum。此前这里会硬退出。
d=$(mkstubdir yumonly yum)
expect 'rhel with only yum -> yum' yum \
    "$(probe_nofb DOT_PKG DOT_OS=linux DOT_OSRELEASE_FILE="$rhel_os" PATH="$d")"

d=$(mkstubdir dnfonly dnf)
expect 'rhel with only dnf -> dnf' dnf \
    "$(probe_nofb DOT_PKG DOT_OS=linux DOT_OSRELEASE_FILE="$rhel_os" PATH="$d")"

# Amazon Linux 走同一条路径（ID=amzn 归入 rhel 族）
amzn_os=$(mkosrelease amznpkg 'ID=amzn' 'ID_LIKE="centos rhel fedora"')
d=$(mkstubdir amznyum yum)
expect 'Amazon Linux with only yum -> yum' yum \
    "$(probe_nofb DOT_PKG DOT_OS=linux DOT_OSRELEASE_FILE="$amzn_os" PATH="$d")"

# 兜底探测是独立的第二条路径，单独测（这里当然要开着兜底）
unknown_os=$(mkosrelease unknownyum 'ID=plan9')
d=$(mkstubdir fallbackyum yum)
expect 'unknown distro falls back to yum' yum \
    "$(probe DOT_PKG DOT_OS=linux DOT_OSRELEASE_FILE="$unknown_os" PATH="$d")"

# 兜底探测里 dnf 优先于 yum（两者都在时不该选 yum）
d=$(mkstubdir fallbackboth dnf yum)
expect 'unknown distro prefers dnf over yum' dnf \
    "$(probe DOT_PKG DOT_OS=linux DOT_OSRELEASE_FILE="$unknown_os" PATH="$d")"

printf '\n== unsupported OS exits non-zero ==\n'
# uname 无法在 env 里覆盖，用 shell 函数遮蔽
if env DOT_LIB_DIR="$DOT_LIB_DIR" sh -c '
    uname() { if [ "$1" = "-s" ]; then echo FreeBSD; else echo x86_64; fi; }
    . "$DOT_LIB_DIR/detect.sh"
    dot_detect
' >/dev/null 2>&1; then
    _fail=$((_fail + 1))
    printf 'FAIL unsupported OS should exit non-zero\n'
else
    _pass=$((_pass + 1))
    printf 'ok   unsupported OS exits non-zero\n'
fi

printf '\n== detection is side-effect free ==\n'
# --info 必须能安全调用：探测本身不得安装或写入任何东西
before=$(ls -A "$HOME" | sort | md5 2>/dev/null || ls -A "$HOME" | sort | md5sum)
probe DOT_OS >/dev/null
after=$(ls -A "$HOME" | sort | md5 2>/dev/null || ls -A "$HOME" | sort | md5sum)
expect 'detection does not touch $HOME' "$before" "$after"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
