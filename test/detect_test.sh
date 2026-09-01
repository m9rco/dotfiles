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
