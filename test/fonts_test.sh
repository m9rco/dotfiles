#!/usr/bin/env sh
#
# modules/fonts 的断言测试。
#
# 不依赖网络：用本地 HTTP server 提供替身 zip，因此在 CI 与离线环境下
# 都能跑，也不会因为上游 release 改名而随机失败。
# 只有一个用例可选地打真实网络（DOT_TEST_NETWORK=1 才跑）。
#
# 字体一律装到沙箱目录（DOT_FONT_DIR），绝不碰真实字体目录。
#
#   sh test/fonts_test.sh
#   DOT_TEST_NETWORK=1 sh test/fonts_test.sh   # 额外验证真实下载
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BOOT="$DOT_REPO/bootstrap.sh"

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

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 not available; font tests need it to serve fixtures\n'
    exit 0
fi

# ------------------------------------------------------------------ 替身素材

WEB="$FIX/web"
mkdir -p "$WEB"

# 造一个含多种变体的字体 zip，模拟 Nerd Fonts 的真实结构：
# 同一字体有 NerdFont / NerdFontMono / NerdFontPropo，外加 Windows Compatible
# 与非字体文件（README/LICENSE）。
python3 - "$WEB/testfont.zip" <<'PY'
import sys, zipfile

names = [
    "TestFontNerdFont-Regular.ttf",
    "TestFontNerdFont-Bold.ttf",
    "TestFontNerdFontMono-Regular.ttf",
    "TestFontNerdFontMono-Bold.ttf",
    "TestFontNerdFontPropo-Regular.ttf",
    "TestFont Windows Compatible.ttf",
    "README.md",
    "LICENSE",
]
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for n in names:
        z.writestr(n, "not a real font, just bytes for the test\n")
PY

# 一个伪装成 zip 的 HTML 错误页（代理/CDN 返回登录页时的真实情形）
printf '<html><body>404 Not Found</body></html>' >"$WEB/broken.zip"

# 一个空文件
: >"$WEB/empty.zip"

python3 -m http.server 18931 --directory "$WEB" >/dev/null 2>&1 &
SRV_PID=$!
# 等服务起来
_tries=0
while [ "$_tries" -lt 30 ]; do
    if curl -fsS -o /dev/null "http://127.0.0.1:18931/testfont.zip" 2>/dev/null; then break; fi
    _tries=$((_tries + 1))
    sleep 0.2
done
if [ "$_tries" -ge 30 ]; then
    printf 'could not start local fixture server; skipping font tests\n'
    exit 0
fi

BASE='http://127.0.0.1:18931'

# 写一份替身清单并跑字体模块
runfonts() {
    _rf_manifest=$1
    _rf_fontdir=$2
    shift 2
    mkdir -p "$FIX/cfg/fonts"
    printf '%s\n' "$_rf_manifest" >"$FIX/cfg/fonts/fonts.txt"
    DOT_CONFIG_DIR="$FIX/cfg" DOT_FONT_DIR="$_rf_fontdir" \
        sh "$BOOT" --only fonts "$@" 2>&1
}

rcfonts() {
    _rc_manifest=$1
    _rc_fontdir=$2
    shift 2
    mkdir -p "$FIX/cfg/fonts"
    printf '%s\n' "$_rc_manifest" >"$FIX/cfg/fonts/fonts.txt"
    DOT_CONFIG_DIR="$FIX/cfg" DOT_FONT_DIR="$_rc_fontdir" \
        sh "$BOOT" --only fonts "$@" >/dev/null 2>&1
    printf '%s' "$?"
}

# ------------------------------------------------------------------ 基本安装

printf '== install from an archive ==\n'
D="$FIX/d1"
out=$(runfonts "Test Font|$BASE/testfont.zip|TestFontNerdFont|" "$D")
expect_has 'reports success' 'Test Font installed' "$out"
ok_if 'font files landed in the sandbox dir' '[ -n "$(ls -A "$D" 2>/dev/null)" ]'
expect 'non-font files are not copied' '' \
    "$(find "$D" -maxdepth 1 \( -name 'README*' -o -name 'LICENSE*' \) 2>/dev/null)"
expect 'Windows Compatible variant is excluded' '' \
    "$(find "$D" -maxdepth 1 -name '*Windows Compatible*' 2>/dev/null)"
expect 'exits 0 on success' 0 "$(rcfonts "Test Font|$BASE/testfont.zip|TestFontNerdFont|" "$FIX/d1b")"

# ------------------------------------------------------------------ 变体过滤

printf '\n== variant filter ==\n'
D="$FIX/d2"
runfonts "Test Font|$BASE/testfont.zip|TestFontNerdFontMono|TestFontNerdFontMono-" "$D" >/dev/null
expect 'only the filtered variant is installed' '2' "$(ls "$D" | wc -l | tr -d ' ')"
ok_if 'filtered family present' '[ -f "$D/TestFontNerdFontMono-Regular.ttf" ]'
ok_if 'other variants excluded' '[ ! -f "$D/TestFontNerdFontPropo-Regular.ttf" ]'

D="$FIX/d3"
runfonts "Test Font|$BASE/testfont.zip|TestFontNerdFont|" "$D" >/dev/null
expect 'empty filter installs every font in the archive' '5' "$(ls "$D" | wc -l | tr -d ' ')"

# ------------------------------------------------------------------ 幂等

printf '\n== idempotence ==\n'
D="$FIX/d4"
runfonts "Test Font|$BASE/testfont.zip|TestFontNerdFont|" "$D" >/dev/null
snap1=$(ls -l "$D" | cksum)
out=$(runfonts "Test Font|$BASE/testfont.zip|TestFontNerdFont|" "$D")
snap2=$(ls -l "$D" | cksum)
expect 'second run changes nothing' "$snap1" "$snap2"
expect_has 'second run reports already installed' 'already installed' "$out"
expect_lacks 'second run does not download' 'downloading' "$out"
expect 'second run exits 0' 0 "$(rcfonts "Test Font|$BASE/testfont.zip|TestFontNerdFont|" "$D")"

# ------------------------------------------------------------------ dry-run

printf '\n== dry-run ==\n'
D="$FIX/d5"
out=$(runfonts "Test Font|$BASE/testfont.zip|TestFontNerdFont|" "$D" --dry-run)
ok_if 'dry-run creates no font dir' '[ ! -d "$D" ] || [ -z "$(ls -A "$D" 2>/dev/null)" ]'
expect_has 'dry-run states the plan' 'would download' "$out"
expect_lacks 'dry-run does not actually download' '-> downloading' "$out"

# ------------------------------------------------------------------ 损坏归档

printf '\n== corrupt archive is rejected before extraction ==\n'
D="$FIX/d6"
out=$(runfonts "Broken|$BASE/broken.zip|Broken|" "$D")
expect_has 'reports an invalid archive' 'not a valid zip archive' "$out"
expect_has 'says what it actually got' 'HTML' "$out"
ok_if 'nothing is written to the font dir' '[ ! -d "$D" ] || [ -z "$(ls -A "$D" 2>/dev/null)" ]'
expect 'corrupt archive exits non-zero' 1 "$(rcfonts "Broken|$BASE/broken.zip|Broken|" "$FIX/d6b")"

printf '\n== empty download is rejected ==\n'
D="$FIX/d7"
out=$(runfonts "Empty|$BASE/empty.zip|Empty|" "$D")
expect_has 'empty file is not treated as an archive' 'not a valid zip archive' "$out"

# ------------------------------------------------------------------ 下载失败

printf '\n== dead URL ==\n'
D="$FIX/d8"
out=$(runfonts "Missing|$BASE/does-not-exist.zip|Missing|" "$D")
expect_has 'download failure is reported with the URL' 'download failed' "$out"
expect 'dead URL exits non-zero' 1 "$(rcfonts "Missing|$BASE/does-not-exist.zip|Missing|" "$FIX/d8b")"

printf '\n== one failure does not stop the others ==\n'
D="$FIX/d9"
MANIFEST="Missing|$BASE/does-not-exist.zip|Missing|
Test Font|$BASE/testfont.zip|TestFontNerdFont|"
out=$(runfonts "$MANIFEST" "$D")
expect_has 'the good font still installs' 'Test Font installed' "$out"
expect_has 'the failed font is named' 'failed fonts: Missing' "$out"
ok_if 'good font files are present' '[ -f "$D/TestFontNerdFont-Regular.ttf" ]'
# 部分失败也必须是非零 —— 否则无人值守场景会忽略掉缺失的字体
expect 'partial failure still exits non-zero' 1 "$(rcfonts "$MANIFEST" "$FIX/d9b")"

# ------------------------------------------------------------------ 清单校验

printf '\n== malformed manifest line ==\n'
D="$FIX/d10"
out=$(runfonts "JustAName" "$D")
expect_has 'malformed line is reported' 'malformed manifest line' "$out"

printf '\n== comments and blank lines are ignored ==\n'
D="$FIX/d11"
MANIFEST="# this is a comment

Test Font|$BASE/testfont.zip|TestFontNerdFont|"
out=$(runfonts "$MANIFEST" "$D")
expect_has 'the real entry is processed' 'Test Font installed' "$out"
expect_lacks 'comments do not become failures' 'failed fonts' "$out"

# ------------------------------------------------------------------ 环境跳过

printf '\n== skipped where fonts make no sense ==\n'
D="$FIX/d12"
out=$(DOT_CONFIG_DIR="$FIX/cfg" DOT_FONT_DIR="$D" CI=1 sh "$BOOT" --only fonts 2>&1)
expect_has 'headless skips the module' 'requires a graphical environment' "$out"
ok_if 'headless installs nothing' '[ ! -d "$D" ] || [ -z "$(ls -A "$D" 2>/dev/null)" ]'

# WSL 场景：DOT_WSL 由 detect 从内核版本串推出，直接在环境里设它会被
# _dot_detect_wsl 重置为 0。要模拟 WSL 必须注入探测文件（同 detect_test 的做法），
# 并且让平台是 linux —— 这才是真机上真正走到的那条路径。
printf '\n== WSL defers fonts to the Windows host ==\n'
D="$FIX/d13"
mkdir -p "$FIX/cfg/fonts"
printf '%s\n' "Test Font|$BASE/testfont.zip|TestFontNerdFont|" >"$FIX/cfg/fonts/fonts.txt"
printf '5.15.90.1-microsoft-standard-WSL2\n' >"$FIX/wsl-osrelease"
out=$(DOT_CONFIG_DIR="$FIX/cfg" DOT_FONT_DIR="$D" \
    DOT_OS=linux DOT_PKG_OVERRIDE=apt \
    DOT_WSL_PROBE_FILES="$FIX/wsl-osrelease" \
    CI= SSH_CONNECTION= SSH_TTY= SSH_CLIENT= \
    sh "$BOOT" --only fonts 2>&1)
expect_has 'WSL skips and explains why' 'must be installed on the Windows host' "$out"
ok_if 'WSL installs nothing' '[ ! -d "$D" ] || [ -z "$(ls -A "$D" 2>/dev/null)" ]'
expect 'WSL skip is not a failure' 0 \
    "$(
        DOT_CONFIG_DIR="$FIX/cfg" DOT_FONT_DIR="$FIX/d13b" \
            DOT_OS=linux DOT_PKG_OVERRIDE=apt \
            DOT_WSL_PROBE_FILES="$FIX/wsl-osrelease" \
            CI= SSH_CONNECTION= SSH_TTY= SSH_CLIENT= \
            sh "$BOOT" --only fonts >/dev/null 2>&1
        printf '%s' "$?"
    )"

# ------------------------------------------------------------------ 真实网络（可选）

if [ "${DOT_TEST_NETWORK:-0}" = 1 ]; then
    printf '\n== real upstream URLs (network) ==\n'
    while IFS='|' read -r _name _url _prefix _filter; do
        case $_name in '' | \#*) continue ;; esac
        code=$(curl -sIL -o /dev/null -w '%{http_code}' "$_url" 2>/dev/null)
        expect "upstream URL for $_name is reachable" '200' "$code"
    done <"$DOT_REPO/config/fonts/fonts.txt"
else
    printf '\n(set DOT_TEST_NETWORK=1 to also verify the real upstream URLs)\n'
fi

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
