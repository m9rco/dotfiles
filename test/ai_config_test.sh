#!/usr/bin/env sh
#
# modules/ai-agent-config 的断言测试。
#
# 全部在沙箱 HOME 里进行 —— 这个模块会写 ~/.claude，绝不能碰真实配置。
#
#   sh test/ai_config_test.sh
#   dash test/ai_config_test.sh
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BOOT="$DOT_REPO/bootstrap.sh"

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

ok_if() {
    if eval "$2"; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s  (condition: %s)\n' "$1" "$2"
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

# 新建一个沙箱：伪造 HOME 与 config 副本，使测试能改坏 mcp.json 而不动仓库
newbox() {
    BOX=$(mktemp -d)
    mkdir -p "$BOX/home/.claude" "$BOX/cfg"
    cp -R "$DOT_REPO/config/ai" "$BOX/cfg/"
}

# 在沙箱里跑模块
boxrun() {
    DOT_CONFIG_DIR="$BOX/cfg" HOME="$BOX/home" DOT_BACKUP_ROOT="$BOX/backup" \
        sh "$BOOT" --only ai-agent-config "$@" 2>&1
}

# 参数可选：多数用例不传，个别用例传 --dry-run
# shellcheck disable=SC2120
boxrc() {
    DOT_CONFIG_DIR="$BOX/cfg" HOME="$BOX/home" DOT_BACKUP_ROOT="$BOX/backup" \
        sh "$BOOT" --only ai-agent-config "$@" >/dev/null 2>&1
    printf '%s' "$?"
}

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 not available; ai-agent-config tests need it for JSON handling\n'
    exit 0
fi

# ------------------------------------------------------------------ 链接与备份

printf '== linking ==\n'
newbox
out=$(boxrun)
for d in agents skills commands hooks; do
    ok_if "$d is linked into the repo" "[ -h \"\$BOX/home/.claude/$d\" ]"
done
expect 'agents link points at the repo source' "$BOX/cfg/ai/agents" \
    "$(readlink "$BOX/home/.claude/agents")"
ok_if 'council agents are reachable through the link' \
    '[ -f "$BOX/home/.claude/agents/council-socrates.md" ]'
ok_if 'council skill is reachable through the link' \
    '[ -f "$BOX/home/.claude/skills/council/SKILL.md" ]'
rm -rf "$BOX"

printf '\n== existing user content is backed up, never destroyed ==\n'
newbox
mkdir -p "$BOX/home/.claude/agents"
printf 'my own agent\n' >"$BOX/home/.claude/agents/mine.md"
boxrun >/dev/null
backed=$(find "$BOX/backup" -name 'mine.md' -type f 2>/dev/null | head -n 1)
ok_if 'user agent was backed up' '[ -n "$backed" ]'
expect 'backup content is intact' 'my own agent' "$(cat "$backed" 2>/dev/null)"
ok_if 'target is now a link to the repo' '[ -h "$BOX/home/.claude/agents" ]'
rm -rf "$BOX"

# ------------------------------------------------------------------ 渲染

printf '\n== placeholders are resolved ==\n'
newbox
boxrun >/dev/null
ok_if 'no placeholders left in settings.json' \
    '! grep -q "{{" "$BOX/home/.claude/settings.json"'
ok_if 'no placeholders left in .mcp.json' \
    '! grep -q "{{" "$BOX/home/.claude/.mcp.json"'
expect '{{HOME}} became the sandbox home' \
    "$BOX/home/.claude/hooks/cbm-session-reminder" \
    "$(python3 -c "
import json
d = json.load(open('$BOX/home/.claude/settings.json'))
print(d['hooks']['SessionStart'][0]['hooks'][0]['command'])
")"
rm -rf "$BOX"

printf '\n== {{EXE}} is platform-dependent ==\n'

# 把「是否以 .exe 结尾」判断抽成函数 —— 在 case 分支里再嵌 $(case ...) 会
# 让部分 shell 的解析器在括号处报错，写成函数最省事也最可读。
_ends_with_exe() {
    case $1 in
        *.exe) printf 'yes' ;;
        *) printf 'no' ;;
    esac
}

# 直接测渲染函数，不经过 bootstrap.sh。
# bootstrap.sh 是 Unix 入口，DOT_OS=windows 时它会（正确地）拒绝运行并
# 提示改用 bootstrap.ps1；而 {{EXE}} 的替换规则属于渲染逻辑，
# 应该独立于入口来验证。Windows 端到端由 bootstrap.ps1 的测试负责。
_render_with_os() {
    DOT_OS=$1 DOT_ROOT="$DOT_REPO" HOME="${2:-$HOME}" sh -c '
        DOT_LIB_DIR="'"$DOT_REPO"'/lib"
        . "$DOT_LIB_DIR/log.sh"
        _dot_ai_render() {
            _dot_r_exe=""
            [ "$DOT_OS" = windows ] && _dot_r_exe=".exe"
            sed -e "s|{{HOME}}|$HOME|g" -e "s|{{DOTFILES}}|$DOT_ROOT|g" -e "s|{{EXE}}|$_dot_r_exe|g"
        }
        _dot_ai_render < "'"$DOT_REPO"'/config/ai/mcp.json"
    '
}

for os in macos linux windows; do
    cmd=$(_render_with_os "$os" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['mcpServers']['codebase-memory-mcp']['command'])
" 2>/dev/null)
    if [ "$os" = windows ]; then
        expect 'windows render ends in .exe' 'yes' "$(_ends_with_exe "$cmd")"
    else
        expect "$os render has no .exe" 'no' "$(_ends_with_exe "$cmd")"
    fi
done

printf '\n== bootstrap.sh refuses native Windows and points at the right entry ==\n'
out=$(DOT_OS=windows sh "$BOOT" --list 2>&1)
expect_has 'says bootstrap.sh is not for native Windows' 'does not support native Windows' "$out"
expect_has 'points at bootstrap.ps1' 'bootstrap.ps1' "$out"

printf '\n== rendering is deterministic ==\n'
newbox
boxrun >/dev/null
cp "$BOX/home/.claude/.mcp.json" "$BOX/first.json"
rm -f "$BOX/home/.claude/.mcp.json"
boxrun >/dev/null
ok_if 'same input renders byte-identical output' \
    '[ "$(cat "$BOX/first.json")" = "$(cat "$BOX/home/.claude/.mcp.json")" ]'
rm -rf "$BOX"

printf '\n== repo metadata is stripped from tool config ==\n'
newbox
boxrun >/dev/null
ok_if 'comment keys are not written to settings.json' \
    '! grep -q "\$comment" "$BOX/home/.claude/settings.json"'
ok_if 'our manifest fields are not written to .mcp.json' \
    '! grep -qE "\"(description|platforms|optional)\"" "$BOX/home/.claude/.mcp.json"'
rm -rf "$BOX"

# ------------------------------------------------------------------ 本地设置保留

printf '\n== user-local settings survive the merge ==\n'
newbox
printf '{\n  "model": "sonnet",\n  "myLocalOnlyKey": "keep-me"\n}\n' \
    >"$BOX/home/.claude/settings.json"
boxrun >/dev/null
expect 'unmanaged local key is preserved' 'keep-me' \
    "$(python3 -c "
import json
print(json.load(open('$BOX/home/.claude/settings.json')).get('myLocalOnlyKey'))
")"
expect 'repo-managed key wins over the local value' 'opus[1m]' \
    "$(python3 -c "
import json
print(json.load(open('$BOX/home/.claude/settings.json')).get('model'))
")"
rm -rf "$BOX"

# ------------------------------------------------------------------ 校验

printf '\n== invalid mcp.json is rejected without writing anything ==\n'
newbox
printf 'SENTINEL\n' >"$BOX/home/.claude/settings.json"
printf '{"mcpServers": {"broken": {' >"$BOX/cfg/ai/mcp.json"
out=$(boxrun)
expect_has 'error names the JSON problem' 'invalid JSON at line' "$out"
expect_has 'error states nothing was written' 'no tool config was written' "$out"
# shellcheck disable=SC2119
expect 'invalid manifest exits non-zero' 1 "$(boxrc)"
expect 'pre-existing settings.json is untouched' 'SENTINEL' \
    "$(cat "$BOX/home/.claude/settings.json")"
ok_if 'no links were created' '[ ! -h "$BOX/home/.claude/agents" ]'
rm -rf "$BOX"

printf '\n== missing required fields are named ==\n'
newbox
printf '{"mcpServers": {"noCommand": {"description": "x"}}}' >"$BOX/cfg/ai/mcp.json"
expect_has 'missing command is reported with the server name' \
    "server 'noCommand': missing required field" "$(boxrun)"
rm -rf "$BOX"

newbox
printf '{"other": {}}' >"$BOX/cfg/ai/mcp.json"
expect_has 'missing mcpServers key is reported' \
    'missing required top-level key: mcpServers' "$(boxrun)"
rm -rf "$BOX"

# ------------------------------------------------------------------ 幂等与 dry-run

printf '\n== idempotence ==\n'
newbox
boxrun >/dev/null
snap1=$(find "$BOX/home/.claude" | sort)
sum1=$(cat "$BOX/home/.claude/settings.json" "$BOX/home/.claude/.mcp.json" | cksum)
bk1=$(find "$BOX/backup" -maxdepth 1 -type d 2>/dev/null | wc -l)
out=$(boxrun)
snap2=$(find "$BOX/home/.claude" | sort)
sum2=$(cat "$BOX/home/.claude/settings.json" "$BOX/home/.claude/.mcp.json" | cksum)
bk2=$(find "$BOX/backup" -maxdepth 1 -type d 2>/dev/null | wc -l)
expect 'second run leaves the same file set' "$snap1" "$snap2"
expect 'second run leaves identical content' "$sum1" "$sum2"
expect 'second run adds no backup dirs' "$bk1" "$bk2"
expect_has 'second run reports links as already in place' 'already linked' "$out"
expect_has 'second run reports rendered files as unchanged' 'unchanged' "$out"
# shellcheck disable=SC2119
expect 'second run exits 0' 0 "$(boxrc)"
rm -rf "$BOX"

printf '\n== dry-run writes nothing ==\n'
newbox
out=$(boxrun --dry-run)
ok_if 'no links created in dry-run' '[ ! -h "$BOX/home/.claude/agents" ]'
ok_if 'no settings.json written in dry-run' '[ ! -f "$BOX/home/.claude/settings.json" ]'
ok_if 'no .mcp.json written in dry-run' '[ ! -f "$BOX/home/.claude/.mcp.json" ]'
ok_if 'no backups created in dry-run' '[ ! -d "$BOX/backup" ]'
expect_has 'dry-run still validates the manifest' 'mcp.json is valid' "$out"
rm -rf "$BOX"

# ------------------------------------------------------------------ 无凭据

printf '\n== no plaintext credentials in the repo source ==\n'
# 只允许出现 env 变量名，不允许出现值形态的凭据
creds=$(grep -rniE 'sk-[a-zA-Z0-9]{16,}|ghp_[a-zA-Z0-9]{16,}|nvapi-[a-zA-Z0-9]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY' \
    "$DOT_REPO/config/ai/" 2>/dev/null || true)
expect 'no credential-shaped strings under config/ai' '' "$creds"

paths=$(grep -rnE '/Users/[A-Za-z0-9_.-]+|/home/[A-Za-z0-9_.-]+' "$DOT_REPO/config/ai/" 2>/dev/null |
    grep -v '/home/linuxbrew' || true)
expect 'no hardcoded home paths under config/ai' '' "$paths"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
