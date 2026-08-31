#!/usr/bin/env sh
#
# modules/ai-clis 与 bin/dot-ai-upgrade 的断言测试。
#
# 不真装 npm 包 —— 用替身 npm/PATH 让「安装」变成可观测的记录动作。
# 这样测试快、可离线、且不改本机已装的 AI CLI。
#
#   sh test/ai_clis_test.sh
#   dash test/ai_clis_test.sh
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BOOT="$DOT_REPO/bootstrap.sh"
UPGRADE="$DOT_REPO/bin/dot-ai-upgrade"

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT INT TERM

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

# ------------------------------------------------------------------ 替身环境
#
# 一个只含替身工具的 PATH：替身 npm 把调用记录到日志，替身 node 让
# 「npm 存在」的判断成立。这样能断言「装了什么包、用了什么参数」。

BIN="$FIX/bin"
mkdir -p "$BIN"

cat >"$BIN/npm" <<'NPM'
#!/bin/sh
# 替身 npm：把每次调用记录下来，并在「安装」时把可执行文件放进替身 bin。
# 保持极简 —— 之前写得太聪明（引用未设变量、case 模式匹配出错）导致
# 替身自己失败，测试却把锅算在被测代码上。
printf 'npm %s\n' "$*" >>"$DOT_TEST_LOG"

if [ -n "${DOT_TEST_NPM_FAIL:-}" ]; then
    exit 1
fi

if [ "$1" = config ]; then
    if [ "$2" = get ]; then
        printf '%s\n' "${DOT_TEST_NPM_PREFIX:-$HOME/.npm-fake}"
    fi
    exit 0
fi

if [ "$1" = install ]; then
    for a in "$@"; do
        case $a in
            *claude-code*) c=claude ;;
            *codex*) c=codex ;;
            *gemini-cli*) c=gemini ;;
            *) continue ;;
        esac
        printf '#!/bin/sh\nprintf "%%s\\n" "${DOT_TEST_VERSION:-9.9.9}"\n' >"$DOT_TEST_BIN/$c"
        chmod +x "$DOT_TEST_BIN/$c"
    done
fi
exit 0
NPM
chmod +x "$BIN/npm"

printf '#!/bin/sh\necho v22.0.0\n' >"$BIN/node"
chmod +x "$BIN/node"

# PATH 的构造有两个互相拉扯的要求：
#   1. 基础工具必须齐全 —— 手工列清单两次漏项（ln、readlink），
#      表现为模块在建链接时就失败，测试却把锅算在被测代码上
#   2. 真实的 AI CLI 必须不可见 —— 否则模块正确地跳过安装，
#      而断言期待的是「装了什么」，于是全红
#
# 解决：继承真实 PATH 拿到基础工具，但把真实 AI CLI 所在的目录剔除。
# 替身目录前置，覆盖 npm/node。
# 用一个排除文件 + grep -vxF 完成过滤。不写成 `... | while read` ——
# 管道里的 while 在子 shell 中执行，循环外设的 _excluded 在里面是空的，
# 过滤会静默失效（这个坑在 lib/fs.sh 里已经踩过一次）。
DOT_EXCL="$FIX/excluded-dirs"
: >"$DOT_EXCL"
for _c in claude codex gemini; do
    # 必须遍历 PATH 找可执行文件，不能用 command -v ——
    # 它会返回 alias 定义（实测 claude 就是个 alias），dirname 得到 "."，
    # 于是排除的是当前目录而不是真实 CLI 所在目录，过滤静默失效。
    # 这正是被测模块里 _dot_ac_present 要绕开 command -v 的同一个原因。
    _ifs=$IFS
    IFS=:
    for _d in $PATH; do
        [ -n "$_d" ] || continue
        if [ -x "$_d/$_c" ]; then
            printf '%s\n' "$_d" >>"$DOT_EXCL"
        fi
    done
    IFS=$_ifs
done
# 空的排除文件会让 grep -vxF -f 过滤掉所有行，加一个不可能匹配的哨兵
printf '%s\n' '__no_such_dir__' >>"$DOT_EXCL"
DOT_FAKE_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF -f "$DOT_EXCL" | paste -sd: -)
DOT_FAKE_PATH="$BIN:$DOT_FAKE_PATH"

# 跑 ai-clis 模块，PATH 只含替身 bin
runai() {
    _ra_manifest=$1
    shift
    mkdir -p "$FIX/cfg/ai"
    printf '%s\n' "$_ra_manifest" >"$FIX/cfg/ai/clis.txt"
    # 模块还会校验 mcp.json（同目录），给一份最小合法的
    printf '{"mcpServers":{}}\n' >"$FIX/cfg/ai/mcp.json"
    : >"$FIX/npm.log"
    rm -rf "$FIX/instbin"
    mkdir -p "$FIX/instbin"
    DOT_CONFIG_DIR="$FIX/cfg" \
        DOT_TEST_LOG="$FIX/npm.log" \
        DOT_TEST_BIN="$FIX/instbin" \
        DOT_TEST_NPM_FAIL="${DOT_TEST_NPM_FAIL:-}" \
        DOT_AI_CLIS="${DOT_AI_CLIS:-}" \
        HOME="$FIX/home" \
        PATH="$FIX/instbin:$DOT_FAKE_PATH" \
        sh "$BOOT" --only ai-clis "$@" 2>&1
}

npmlog() { cat "$FIX/npm.log" 2>/dev/null; }

mkdir -p "$FIX/home"

# ------------------------------------------------------------------ 安装

printf '== install via npm ==\n'
M="claude|all|npm:@anthropic-ai/claude-code|--version|Claude Code"
out=$(runai "$M")
expect_has 'npm install --global is used' 'npm install --global @anthropic-ai/claude-code' "$(npmlog)"
expect_lacks 'sudo is never used' 'sudo' "$out"
expect_has 'success is reported' 'claude installed via npm' "$out"

printf '\n== every manifest entry is processed ==\n'
# 守 stdin 被吃掉那类 bug（npm 会读 stdin）
M="claude|all|npm:@anthropic-ai/claude-code|--version|c
codex|all|npm:@openai/codex|--version|x
gemini|all|npm:@google/gemini-cli|--version|g"
runai "$M" >/dev/null
n=$(npmlog | grep -c 'install --global')
expect 'all three entries reach npm' '3' "$(printf '%s' "$n" | tr -d ' ')"

printf '\n== version is reported after install ==\n'
out=$(DOT_TEST_VERSION=1.2.3 runai "claude|all|npm:@anthropic-ai/claude-code|--version|c")
expect_has 'version appears in the output' '1.2.3' "$out"

printf '\n== version check failure is not fatal ==\n'
# 版本参数指向一个不存在的开关，命令会失败但模块应仍成功
M="claude|all|npm:@anthropic-ai/claude-code|--no-such-flag|c"
out=$(runai "$M")
expect_has 'install still reported as done' 'installed via npm' "$out"
mkdir -p "$FIX/cfg/ai"
printf '%s\n' "$M" >"$FIX/cfg/ai/clis.txt"
printf '{"mcpServers":{}}\n' >"$FIX/cfg/ai/mcp.json"
rm -rf "$FIX/instbin"
mkdir -p "$FIX/instbin"
DOT_CONFIG_DIR="$FIX/cfg" DOT_TEST_LOG="$FIX/npm.log" DOT_TEST_BIN="$FIX/instbin" \
    HOME="$FIX/home" PATH="$FIX/instbin:$DOT_FAKE_PATH" \
    sh "$BOOT" --only ai-clis >/dev/null 2>&1
expect 'module exits 0 despite the version check' 0 "$?"

# ------------------------------------------------------------------ 幂等

printf '\n== already installed: skip, do not reinstall ==\n'
mkdir -p "$FIX/instbin"
printf '#!/bin/sh\necho 5.5.5\n' >"$FIX/instbin/claude"
chmod +x "$FIX/instbin/claude"
mkdir -p "$FIX/cfg/ai"
printf '%s\n' "claude|all|npm:@anthropic-ai/claude-code|--version|c" >"$FIX/cfg/ai/clis.txt"
printf '{"mcpServers":{}}\n' >"$FIX/cfg/ai/mcp.json"
: >"$FIX/npm.log"
out=$(DOT_CONFIG_DIR="$FIX/cfg" DOT_TEST_LOG="$FIX/npm.log" DOT_TEST_BIN="$FIX/instbin" \
    HOME="$FIX/home" PATH="$FIX/instbin:$DOT_FAKE_PATH" sh "$BOOT" --only ai-clis 2>&1)
expect_has 'reports it as already installed' 'claude already installed' "$out"
expect_has 'reports the existing version' '5.5.5' "$out"
expect_lacks 'no install is attempted' 'install --global' "$(npmlog)"
rm -f "$FIX/instbin/claude"

printf '\n== a shell alias does not count as installed ==\n'
# 实测过的坑：`claude` 在交互式 shell 里是 alias，`command -v claude` 会成功
# 并输出 "alias claude=..." 而不是路径 —— 天真的检测会误判为已安装并跳过。
#
# 直接测模块里的检测函数本身（source 模块拿到 _dot_ac_present），
# 在一个 claude 确实不存在的 PATH 上定义 alias，检测必须仍报「不存在」。
alias_probe=$(
    DOT_LIB_DIR="$DOT_REPO/lib" \
        PATH="$FIX/emptybin:$DOT_FAKE_PATH" \
        sh -c '
        . "$DOT_LIB_DIR/log.sh"
        . "'"$DOT_REPO"'/modules/ai-clis/module.sh"
        alias claude="echo aliased"
        if _dot_ac_present claude; then printf present; else printf absent; fi
    ' 2>/dev/null
)
expect 'detection ignores the alias and reports absent' 'absent' "$alias_probe"

# 反面：PATH 里真有可执行文件时必须报存在
mkdir -p "$FIX/hasbin"
printf '#!/bin/sh\nexit 0\n' >"$FIX/hasbin/claude"
chmod +x "$FIX/hasbin/claude"
present_probe=$(
    DOT_LIB_DIR="$DOT_REPO/lib" \
        PATH="$FIX/hasbin:$DOT_FAKE_PATH" \
        sh -c '
        . "$DOT_LIB_DIR/log.sh"
        . "'"$DOT_REPO"'/modules/ai-clis/module.sh"
        if _dot_ac_present claude; then printf present; else printf absent; fi
    ' 2>/dev/null
)
expect 'a real executable is detected as present' 'present' "$present_probe"

# ------------------------------------------------------------------ 子集

printf '\n== DOT_AI_CLIS selects a subset ==\n'
M="claude|all|npm:@anthropic-ai/claude-code|--version|c
codex|all|npm:@openai/codex|--version|x
gemini|all|npm:@google/gemini-cli|--version|g"
DOT_AI_CLIS=codex runai "$M" >/dev/null
expect 'only the selected CLI is installed' '1' \
    "$(npmlog | grep -c 'install --global' | tr -d ' ')"
expect_has 'the selected one is codex' '@openai/codex' "$(npmlog)"

DOT_AI_CLIS=claude,gemini runai "$M" >/dev/null
expect 'comma-separated subset works' '2' \
    "$(npmlog | grep -c 'install --global' | tr -d ' ')"

# ------------------------------------------------------------------ dry-run

printf '\n== dry-run installs nothing ==\n'
out=$(runai "claude|all|npm:@anthropic-ai/claude-code|--version|c" --dry-run)
expect 'npm is never called' '' "$(npmlog)"
expect_has 'the plan is printed' 'would install claude via npm' "$out"

# ------------------------------------------------------------------ 无凭据

printf '\n== the install never asks for credentials ==\n'
out=$(runai "claude|all|npm:@anthropic-ai/claude-code|--version|c")
expect_lacks 'no API key prompt' 'API key' "$(printf '%s' "$out" | grep -i 'enter\|prompt\|paste' || true)"
expect_has 'auth is explicitly deferred' 'authentication is a separate step' "$out"
expect_has 'points at the keychain, not the repo' 'keychain' "$out"

# ------------------------------------------------------------------ npm 缺失

printf '\n== missing npm is reported, not fatal to the rest ==\n'
# 「npm 缺失」的场景不能靠从 PATH 里过滤 npm 所在目录来模拟 ——
# npm 可能同时存在于多个目录（实测 nvm 与 homebrew 各一份），
# 过滤一个不够、逐个过滤又脆弱。
#
# 改为构造一个只含必要基础工具的目录，并显式不放 npm。
# 工具清单从 bootstrap 实际用到的推导，缺了哪个会立刻在断言里暴露。
NONPM="$FIX/nonpm"
mkdir -p "$NONPM"
for _t in sh dash printf grep sed awk cat cut head tail tr sort uniq wc \
    ls find mkdir rm rmdir mv cp ln readlink chmod cmp mktemp date \
    dirname basename env uname id od dd tee xargs stty paste; do
    _p=$(command -v "$_t" 2>/dev/null) || continue
    ln -sf "$_p" "$NONPM/$_t" 2>/dev/null || true
done
NONPM_PATH="$NONPM"

out=$(DOT_CONFIG_DIR="$FIX/cfg" HOME="$FIX/home" PATH="$NONPM_PATH" sh "$BOOT" --only ai-clis 2>&1)
expect_has 'missing npm is named as the reason' 'needs npm' "$out"
expect_has 'suggests installing node' 'install node' "$out"

# ------------------------------------------------------------------ 平台

printf '\n== platform filtering ==\n'
# 钉住 DOT_OS：断言里写了具体平台名，不能随运行环境变化
out=$(DOT_AI_CLIS= DOT_OS=macos runai "linuxonly|linux|npm:@x/l|--version|linux only
claude|all|npm:@anthropic-ai/claude-code|--version|everywhere")
expect_has 'entry for another platform is skipped with a reason' 'linuxonly: not for macos' "$out"
expect_has 'the all-platform entry still installs' '@anthropic-ai/claude-code' "$(npmlog)"
expect_lacks 'the skipped entry is never installed' '@x/l' "$(npmlog)"

# ------------------------------------------------------------------ 清单校验

printf '\n== malformed manifest line ==\n'
out=$(runai "onlyaname")
expect_has 'malformed line is reported' 'malformed manifest line' "$out"

printf '\n== the real manifest is well formed ==\n'
REAL="$DOT_REPO/config/ai/clis.txt"
ok_if 'real manifest exists' '[ -f "$REAL" ]'
bad=''
while IFS='|' read -r c p h v d; do
    case $c in '' | \#*) continue ;; esac
    [ -n "$p" ] || bad="$bad $c(no-platform)"
    [ -n "$h" ] || bad="$bad $c(no-method)"
    [ -n "$d" ] || bad="$bad $c(no-desc)"
    case $h in
        npm:* | brew:* | script:*) ;;
        *) bad="$bad $c(bad-method:$h)" ;;
    esac
done <"$REAL"
expect 'every entry has platform, method and description' '' "$bad"
expect 'all three AI CLIs are listed' '3' \
    "$(grep -cvE '^\s*#|^\s*$' "$REAL" | tr -d ' ')"

# ------------------------------------------------------------------ 升级脚本

printf '\n== upgrade is a separate command ==\n'
out=$(sh "$UPGRADE" --help 2>&1)
expect_has 'help says it is separate from bootstrap' 'separate from ./bootstrap.sh' "$out"

printf '\n== upgrade skips tools that are not installed ==\n'
out=$(HOME="$FIX/home" PATH="$NONPM_PATH" sh "$UPGRADE" --dry-run 2>&1)
expect_has 'absent tool is reported' 'is not installed' "$out"

printf '\n== upgrade uses @latest ==\n'
mkdir -p "$FIX/instbin"
printf '#!/bin/sh\necho 1.0.0\n' >"$FIX/instbin/gemini"
chmod +x "$FIX/instbin/gemini"
: >"$FIX/npm.log"
out=$(DOT_TEST_LOG="$FIX/npm.log" DOT_TEST_BIN="$FIX/instbin" HOME="$FIX/home" \
    PATH="$FIX/instbin:$DOT_FAKE_PATH" sh "$UPGRADE" gemini 2>&1)
expect_has 'installs the @latest tag' '@google/gemini-cli@latest' "$(npmlog)"

printf '\n== upgrade refuses to shadow a version-manager copy ==\n'
VOLTA="$FIX/home/.volta/bin"
mkdir -p "$VOLTA"
printf '#!/bin/sh\necho 2.0.0\n' >"$VOLTA/claude"
chmod +x "$VOLTA/claude"
: >"$FIX/npm.log"
out=$(DOT_TEST_LOG="$FIX/npm.log" HOME="$FIX/home" PATH="$VOLTA:$DOT_FAKE_PATH" \
    sh "$UPGRADE" claude 2>&1)
expect_has 'volta ownership is detected' 'managed by volta' "$out"
expect_has 'suggests the right command' 'volta install' "$out"
expect_has 'explains the shadowing hazard' 'shadows this one' "$out"
expect_lacks 'npm -g is not invoked' 'install --global' "$(npmlog)"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
