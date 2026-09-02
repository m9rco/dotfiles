#!/usr/bin/env sh
#
# lib/release.sh 的断言测试 —— 从 GitHub release 取预编译二进制那条路。
#
# 不依赖网络：本地 HTTP server 提供替身归档，所以 CI 与离线环境都能跑，
# 也不会因为上游改资产名而随机失败。只有一个用例可选地打真实网络
# （DOT_TEST_NETWORK=1 才跑），用来发现上游真的改了资产名。
#
# 为什么不能只用 python3 -m http.server：版本嵌在资产名里的工具（fzf/
# lazygit/gh）要先解析 tag，而那依赖 /releases/latest 的 302 重定向。
# 所以这里起一个会重定向的小 handler。
#
#   sh test/release_test.sh
#   DOT_TEST_NETWORK=1 sh test/release_test.sh
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

FIX=$(mktemp -d)
SRV_PID=''
cleanup_all() {
    [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
    rm -rf "$FIX"
}
trap cleanup_all EXIT INT TERM

_pass=0
_fail=0

expect() {
    if [ "$2" = "$3" ]; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$1" "$2" "$3"
    fi
}

expect_has() {
    if printf '%s' "$3" | grep -q -- "$2"; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s\n       expected output to contain: %s\n' "$1" "$2"
    fi
}

expect_lacks() {
    if printf '%s' "$3" | grep -q -- "$2"; then
        _fail=$((_fail + 1))
        printf 'FAIL %s\n       expected output NOT to contain: %s\n' "$1" "$2"
    else
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    fi
}

ok_if() {
    if eval "$2"; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s  (condition: %s)\n' "$1" "$2"
    fi
}

# 文件权限的八进制。BSD 与 GNU 的 stat 参数不同名。
file_mode() {
    if stat -f '%Lp' "$1" 2>/dev/null; then
        return 0
    fi
    stat -c '%a' "$1" 2>/dev/null
}

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 not available; release tests need it to serve fixtures\n'
    exit 0
fi

# ------------------------------------------------------------------ 替身资产
#
# 每个 fixture 钉一个具体的隐患，见各自的注释。
# 二进制内容只要魔数对就行 —— dot_dl_verify 只看头几个字节。

WEB="$FIX/web"
mkdir -p "$WEB"
ELF=$(printf '\177ELF\002\001\001\000')

# fzf 形状：版本嵌在资产名里，二进制在归档根部
mkdir -p "$FIX/b/fzf" && printf '%s' "$ELF" >"$FIX/b/fzf/fzf"
(cd "$FIX/b/fzf" && tar -czf "$WEB/fzf-1.2.3-linux_amd64.tar.gz" fzf)

# gh 形状：二进制嵌在**目录名带版本**的子目录里。
# 这正是 --strip-components 会变脆的情形 —— 层数对了但名字每次发版都变。
mkdir -p "$FIX/b/gh/gh_1.2.3_linux_amd64/bin"
printf '%s' "$ELF" >"$FIX/b/gh/gh_1.2.3_linux_amd64/bin/gh"
printf 'manpage\n' >"$FIX/b/gh/gh_1.2.3_linux_amd64/gh-alias.1"
(cd "$FIX/b/gh" && tar -czf "$WEB/gh_1.2.3_linux_amd64.tar.gz" gh_1.2.3_linux_amd64)

# btop 形状：前导 ./，且归档里有一个与二进制**同名的目录**。
# 价值最高的一个 fixture：find 不加 -type f 会先命中那个目录。
mkdir -p "$FIX/b/btop/btop/bin" "$FIX/b/btop/btop/themes"
printf '%s' "$ELF" >"$FIX/b/btop/btop/bin/btop"
printf 'theme\n' >"$FIX/b/btop/btop/themes/x.theme"
(cd "$FIX/b/btop" && tar -czf "$WEB/btop-x86_64-unknown-linux-musl.tar.gz" ./btop)

# duf 形状：二进制旁边有个 manpage，精确 -name 不能抓错
mkdir -p "$FIX/b/duf" && printf '%s' "$ELF" >"$FIX/b/duf/duf"
printf '.TH DUF\n' >"$FIX/b/duf/duf.1"
(cd "$FIX/b/duf" && tar -czf "$WEB/duf_1.2.3_linux_x86_64.tar.gz" duf duf.1)

# 裸二进制（jq/yq/direnv 是这种），资产名不含版本
printf '%s' "$ELF" >"$WEB/jq-linux-amd64"

# 伪装成归档的 HTML 错误页 —— 代理/CDN 用 200 返回登录页的真实情形
printf '<html><body>403 Forbidden</body></html>' >"$WEB/broken.tar.gz"

# ------------------------------------------------------------------ 替身服务
#
# 路由：
#   /<owner>/<repo>/releases/latest                    -> 302 到 tag 页
#   /<owner>/<repo>/releases/download/<tag>/<asset>    -> 资产内容
#   /<owner>/<repo>/releases/latest/download/<asset>   -> 资产内容
#   /noredirect/<repo>/releases/latest                 -> 200 且不重定向
#                                                         （代理守卫用例）

cat >"$FIX/serve.py" <<'PY'
import os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

WEB = sys.argv[1]
PORT = int(sys.argv[2])
TAG = "v1.2.3"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _asset(self, name):
        path = os.path.join(WEB, name)
        if not os.path.isfile(path):
            self.send_error(404)
            return
        with open(path, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _route(self):
        p = self.path
        # 代理守卫：200 且不重定向，tag 解析应识破
        if p.startswith("/noredirect/"):
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(b"ok")
            return
        if p.endswith("/releases/latest"):
            self.send_response(302)
            self.send_header("Location", p[: -len("latest")] + "tag/" + TAG)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        marker = "/releases/latest/download/"
        if marker in p:
            self._asset(p.split(marker, 1)[1])
            return
        marker = "/releases/download/"
        if marker in p:
            rest = p.split(marker, 1)[1]
            parts = rest.split("/", 1)
            if len(parts) == 2:
                self._asset(parts[1])
                return
        self.send_error(404)

    def do_GET(self):
        self._route()

    def do_HEAD(self):
        self._route()


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY

PORT=18942
python3 "$FIX/serve.py" "$WEB" "$PORT" >/dev/null 2>&1 &
SRV_PID=$!
_tries=0
while [ "$_tries" -lt 40 ]; do
    if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/o/r/releases/latest/download/jq-linux-amd64" 2>/dev/null; then
        break
    fi
    _tries=$((_tries + 1))
    sleep 0.2
done
if [ "$_tries" -ge 40 ]; then
    printf 'could not start the local fixture server; skipping release tests\n'
    exit 0
fi

BASE="http://127.0.0.1:$PORT"

# 在沙箱 HOME 与隔离的 TMPDIR 下调 dot_release_install。
# TMPDIR 隔离让「临时目录不泄漏」这条真的可测 —— mktemp 认 TMPDIR。
run_release() {
    _rr_tool=$1
    _rr_repo=$2
    _rr_os=$3
    _rr_arch=$4
    # ${FIX:?} 而不是 $FIX：万一 FIX 没设，rm -rf "$FIX/home" 就是
    # rm -rf /home。这里用 :? 让它在展开时就报错退出。
    rm -rf "${FIX:?}/home" "${FIX:?}/tmp"
    mkdir -p "$FIX/home" "$FIX/tmp"
    env DOT_LIB_DIR="$DOT_REPO/lib" HOME="$FIX/home" TMPDIR="$FIX/tmp" \
        DOT_GITHUB_BASE="$BASE" DOT_OS="$_rr_os" DOT_ARCH="$_rr_arch" \
        sh -c ". \"\$DOT_LIB_DIR/release.sh\"; dot_release_install \"\$1\" \"\$2\"" \
        _ "$_rr_tool" "$_rr_repo" 2>&1
}

# ------------------------------------------------------------------ 归档形状

printf '== the binary is found in every archive layout ==\n'

out=$(run_release fzf o/fzf linux x86_64)
ok_if 'tar.gz with the binary at the root' '[ -f "$FIX/home/.local/bin/fzf" ]'
expect 'it is executable' '755' "$(file_mode "$FIX/home/.local/bin/fzf")"
expect_has 'the tag is named in the output' '1.2.3' "$out"

# 目录名带版本 —— 这一条是 --strip-components 方案会栽的地方
out=$(run_release gh o/gh linux x86_64)
ok_if 'tar.gz with the binary nested under a versioned dir' \
    '[ -f "$FIX/home/.local/bin/gh" ]'
# manpage 不能被当成二进制装进去
ok_if 'the manpage next to it is not installed' \
    '[ ! -e "$FIX/home/.local/bin/gh-alias.1" ]'

out=$(run_release jq o/jq linux x86_64)
ok_if 'a bare binary asset needs no extraction' '[ -f "$FIX/home/.local/bin/jq" ]'
# 裸下载是 0644，必须被显式 chmod 过
expect 'the bare binary was made executable' '755' \
    "$(file_mode "$FIX/home/.local/bin/jq")"
expect_has 'a version-free asset does not resolve a tag' 'latest' "$out"

# ------------------------------------------------------------------ 定位隐患
#
# btop 与 duf 现在还没接进清单（optional 层），但它们的归档结构恰好是
# dot_dl_find_file 最容易出错的两种，所以在这里直接测那个函数 ——
# 将来给它们加配方时这两条已经在防着了。

printf '\n== locating the binary inside awkward archives ==\n'

loc() {
    env DOT_LIB_DIR="$DOT_REPO/lib" sh -c '
        . "$DOT_LIB_DIR/download.sh"
        out=$(mktemp -d)
        dot_dl_untar "$1" "$out" || exit 1
        found=$(dot_dl_find_file "$out" "$2")
        printf "%s" "${found#"$out"/}"
        rm -rf "$out"
    ' _ "$1" "$2"
}

# 归档里有个与二进制同名的**目录**（./btop/ 与 ./btop/bin/btop）。
# 不加 -type f 会先命中那个目录，然后 cp 一个目录必然失败。
expect 'a same-named directory is not mistaken for the binary' \
    'btop/bin/btop' "$(loc "$WEB/btop-x86_64-unknown-linux-musl.tar.gz" btop)"

# 二进制旁边有 duf.1，精确 -name 不能抓错
expect 'a manpage beside the binary is not picked' \
    'duf' "$(loc "$WEB/duf_1.2.3_linux_x86_64.tar.gz" duf)"

# ------------------------------------------------------------------ 临时目录

printf '\n== temp dirs do not leak ==\n'
run_release jq o/jq linux x86_64 >/dev/null
expect 'nothing is left in TMPDIR' '' "$(ls -A "$FIX/tmp" 2>/dev/null)"

# ------------------------------------------------------------------ 坏内容

printf '\n== bad payloads are rejected before extraction ==\n'

# HTML 错误页伪装成 tar.gz。curl -f 拦不住（代理返回的是 200），
# 只有魔数能识破。
out=$(env DOT_LIB_DIR="$DOT_REPO/lib" HOME="$FIX/home2" TMPDIR="$FIX/tmp" \
    DOT_GITHUB_BASE="$BASE" DOT_OS=linux DOT_ARCH=x86_64 \
    sh -c '
. "$DOT_LIB_DIR/release.sh"
# 直接改配方指向那个坏文件
_dot_release_recipe() {
    _dot_rr_asset="broken.tar.gz"
    _dot_rr_kind=targz
    _dot_rr_name=whatever
    [ -n "$_dot_rr_asset" ]
}
dot_release_install broken o/broken' 2>&1)
expect_has 'an HTML error page is not treated as an archive' 'not a gzip' "$out"
expect_has 'the output says what actually arrived' 'got ' "$out"
ok_if 'nothing is installed from a bad payload' '[ ! -e "$FIX/home2/.local/bin/whatever" ]'

# 代理返回 200 而不重定向 —— 版本解析拿不到 tag，必须明确报出来，
# 而不是把字面量 latest 代进资产名产生一个莫名的 404
out=$(run_release fzf noredirect/fzf linux x86_64)
expect_has 'a non-redirecting proxy is diagnosed' 'cannot resolve the latest release' "$out"

# ------------------------------------------------------------------ 无资产

printf '\n== platforms without an asset say so ==\n'
out=$(run_release nosuchtool o/none linux x86_64)
expect_has 'a tool with no recipe is reported' 'no release-asset recipe' "$out"
expect_has 'and it says it was not attempted' 'not attempted' "$out"

# 「配方里没有这个工具」与「配方有、但本平台没资产」是两件事，对调用方却是
# 同一个结果。必须分开说，否则将来给 btop 加配方时（它零 darwin 资产），
# macOS 上会看起来像配置漏了一行。
#
# 这里用一个只给 linux 提供资产的替身配方来触发后一种情形 —— 目前接进
# 清单的 6 个工具四个平台组合都有资产，没有现成的例子。
out=$(env DOT_LIB_DIR="$DOT_REPO/lib" HOME="$FIX/home5" TMPDIR="$FIX/tmp" \
    DOT_GITHUB_BASE="$BASE" DOT_OS=macos DOT_ARCH=arm64 \
    sh -c '
. "$DOT_LIB_DIR/release.sh"
_dot_release_recipe() {
    _dot_rr_asset=""
    _dot_rr_kind=targz
    _dot_rr_name=linuxonly
    [ "$DOT_OS" = linux ] && _dot_rr_asset="linuxonly.tar.gz"
    [ -n "$_dot_rr_asset" ]
}
dot_release_install linuxonly o/linuxonly' 2>&1)
expect_has 'a platform with no asset is reported as such' 'no prebuilt binary for' "$out"
expect_has 'and that path also says not attempted' 'not attempted' "$out"
# 关键：这条不能和「配方缺失」混为一谈，否则诊断会把人带错方向
expect_lacks 'it is not reported as a missing recipe' 'no release-asset recipe' "$out"

# ------------------------------------------------------------------ 开关

printf '\n== the opt-outs work ==\n'
out=$(rm -rf "$FIX/home3" && mkdir -p "$FIX/home3" && env DOT_LIB_DIR="$DOT_REPO/lib" \
    HOME="$FIX/home3" TMPDIR="$FIX/tmp" DOT_GITHUB_BASE="$BASE" \
    DOT_OS=linux DOT_ARCH=x86_64 DOT_NO_GITHUB_RELEASE=1 \
    sh -c '. "$DOT_LIB_DIR/release.sh"; dot_release_install jq o/jq' 2>&1)
expect_has 'DOT_NO_GITHUB_RELEASE is honoured' 'DOT_NO_GITHUB_RELEASE=1' "$out"
ok_if 'and nothing is downloaded' '[ ! -e "$FIX/home3/.local/bin/jq" ]'

out=$(rm -rf "$FIX/home4" && mkdir -p "$FIX/home4" && env DOT_LIB_DIR="$DOT_REPO/lib" \
    HOME="$FIX/home4" TMPDIR="$FIX/tmp" DOT_GITHUB_BASE="$BASE" \
    DOT_OS=linux DOT_ARCH=x86_64 DOT_GITHUB_UNREACHABLE=1 \
    sh -c '. "$DOT_LIB_DIR/release.sh"; dot_release_install jq o/jq' 2>&1)
expect_has 'an earlier unreachable github short-circuits' 'unreachable' "$out"

# ------------------------------------------------------------------ 版本解析

printf '\n== tag to version ==\n'
vers=$(env DOT_LIB_DIR="$DOT_REPO/lib" sh -c '
. "$DOT_LIB_DIR/release.sh"
for t in v0.74.3 jq-1.8.2 1.2.3; do printf "%s " "$(_dot_release_version "$t")"; done')
# jq 的 tag 没有 v 前缀（jq-1.8.2），天真的 ${tag#v} 会对别的 tag 出错
expect 'a v prefix is stripped, other shapes are kept' '0.74.3 jq-1.8.2 1.2.3 ' "$vers"

guard=$(env DOT_LIB_DIR="$DOT_REPO/lib" sh -c '
. "$DOT_LIB_DIR/release.sh"
for v in 1.2.3 latest "" nodigits "bad;evil"; do
    _dot_release_version_ok "$v" && printf "ok " || printf "no "
done')
expect 'implausible versions are rejected' 'ok no no no no ' "$guard"

# ------------------------------------------------------------------ 真实网络

if [ "${DOT_TEST_NETWORK:-0}" = 1 ]; then
    printf '\n== the real upstream assets (network) ==\n'
    # 只拉最小的那个。这条存在的意义是发现上游改了资产名 —— 本地 fixture
    # 永远不会告诉你这件事。
    rm -rf "$FIX/homenet" && mkdir -p "$FIX/homenet"
    out=$(env DOT_LIB_DIR="$DOT_REPO/lib" HOME="$FIX/homenet" TMPDIR="$FIX/tmp" \
        DOT_OS="$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/')" \
        DOT_ARCH="$(uname -m | sed 's/aarch64/arm64/;s/amd64/x86_64/')" \
        sh -c '. "$DOT_LIB_DIR/release.sh"; dot_release_install jq jqlang/jq' 2>&1)
    ok_if 'jq really downloads from GitHub' '[ -x "$FIX/homenet/.local/bin/jq" ]'
    if [ -x "$FIX/homenet/.local/bin/jq" ]; then
        expect_has 'and it runs' 'jq-' "$("$FIX/homenet/.local/bin/jq" --version 2>&1)"
    fi
else
    printf '\n(set DOT_TEST_NETWORK=1 to also verify the real upstream assets)\n'
fi

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
