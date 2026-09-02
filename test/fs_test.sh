#!/usr/bin/env sh
#
# lib/fs.sh 的断言测试。备份保证是整个重构里风险最高的行为
# （旧 lnif() 直接 rm -rf 目标），所以这里覆盖得比其他部分更密。
#
# 全部在 mktemp 沙箱内进行，不触碰真实 $HOME。
#
#   sh test/fs_test.sh
#   dash test/fs_test.sh
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
DOT_LIB_DIR="$DOT_REPO/lib"
export DOT_LIB_DIR

_pass=0
_fail=0

# 各用例在子 shell 中运行以隔离状态，通过这个记分文件把结果带回父 shell。
DOT_SCORE=$(mktemp)
trap 'rm -f "$DOT_SCORE"' EXIT INT TERM

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

# 把子 shell 用例的记分累加到父 shell
tally() {
    read -r _t_pass _t_fail <"$DOT_SCORE" 2>/dev/null || return 0
    _pass=$((_pass + _t_pass))
    _fail=$((_fail + _t_fail))
    : >"$DOT_SCORE"
}

# 每个用例一个干净沙箱：伪造 HOME，备份根指向沙箱内。
# 在子 shell 里跑，避免用例之间通过 DOT_BACKUP_DIR 等状态互相污染。
sandbox() {
    # 子 shell 继承了父 shell 的计数，必须归零 —— 否则 tally 会把父 shell
    # 已累计的分数重复加回去（分数会指数级膨胀）。
    _pass=0
    _fail=0

    SBOX=$(mktemp -d)
    export HOME="$SBOX/home"
    export DOT_BACKUP_ROOT="$SBOX/backup"
    mkdir -p "$HOME"
    unset DOT_DRY_RUN DOT_FS_SH_LOADED DOT_LOG_SH_LOADED DOT_BACKUP_DIR 2>/dev/null || true
    # shellcheck source=lib/fs.sh
    . "$DOT_LIB_DIR/fs.sh"
    DOT_BACKUP_DIR=''
    mkdir -p "$SBOX/repo"
    printf 'REPO CONTENT\n' >"$SBOX/repo/zshrc"
}

cleanup() { rm -rf "$SBOX"; }

printf '== case 1: fresh link ==\n'
(
    sandbox
    dot_link "$SBOX/repo/zshrc" "$HOME/.zshrc" >/dev/null 2>&1
    ok_if 'creates symlink' '[ -h "$HOME/.zshrc" ]'
    expect 'points at source' "$SBOX/repo/zshrc" "$(readlink "$HOME/.zshrc")"
    expect 'content readable through link' 'REPO CONTENT' "$(cat "$HOME/.zshrc")"
    ok_if 'no backup dir created' '[ ! -d "$DOT_BACKUP_ROOT" ]'
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 2: real file is backed up, never destroyed ==\n'
(
    sandbox
    printf 'USER PRECIOUS CONFIG\n' >"$HOME/.zshrc"
    dot_link "$SBOX/repo/zshrc" "$HOME/.zshrc" >/dev/null 2>&1
    ok_if 'target became a symlink' '[ -h "$HOME/.zshrc" ]'
    expect 'link points at repo' "$SBOX/repo/zshrc" "$(readlink "$HOME/.zshrc")"
    ok_if 'backup dir exists' '[ -d "$DOT_BACKUP_ROOT" ]'
    backed=$(find "$DOT_BACKUP_ROOT" -name '.zshrc' -type f | head -n 1)
    ok_if 'backup file found' '[ -n "$backed" ]'
    expect 'backup content is byte-identical' 'USER PRECIOUS CONFIG' "$(cat "$backed" 2>/dev/null)"
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 3: idempotent (already correctly linked) ==\n'
(
    sandbox
    dot_link "$SBOX/repo/zshrc" "$HOME/.zshrc" >/dev/null 2>&1
    before_ts=$(ls -lT "$HOME/.zshrc" 2>/dev/null || ls -l --time-style=full-iso "$HOME/.zshrc")
    out=$(dot_link "$SBOX/repo/zshrc" "$HOME/.zshrc" 2>&1)
    after_ts=$(ls -lT "$HOME/.zshrc" 2>/dev/null || ls -l --time-style=full-iso "$HOME/.zshrc")
    expect 'second run does not touch the link' "$before_ts" "$after_ts"
    ok_if 'reports as skipped' 'printf "%s" "$out" | grep -q "already linked"'
    ok_if 'no backup created on repeat' '[ ! -d "$DOT_BACKUP_ROOT" ]'
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 4: symlink pointing elsewhere is replaced without backup ==\n'
(
    sandbox
    printf 'OTHER\n' >"$SBOX/other"
    ln -s "$SBOX/other" "$HOME/.zshrc"
    dot_link "$SBOX/repo/zshrc" "$HOME/.zshrc" >/dev/null 2>&1
    expect 'now points at repo' "$SBOX/repo/zshrc" "$(readlink "$HOME/.zshrc")"
    ok_if 'no backup (symlink has no content)' '[ ! -d "$DOT_BACKUP_ROOT" ]'
    ok_if 'original target file untouched' '[ -f "$SBOX/other" ]'
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 5: missing parent dir is created ==\n'
(
    sandbox
    dot_link "$SBOX/repo/zshrc" "$HOME/.config/deep/nested/file" >/dev/null 2>&1
    ok_if 'nested link created' '[ -h "$HOME/.config/deep/nested/file" ]'
    expect 'content reachable' 'REPO CONTENT' "$(cat "$HOME/.config/deep/nested/file")"
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 6: real DIRECTORY is backed up, not clobbered ==\n'
(
    sandbox
    mkdir -p "$HOME/.claude/agents"
    printf 'user agent\n' >"$HOME/.claude/agents/mine.md"
    mkdir -p "$SBOX/repo/agents"
    dot_link "$SBOX/repo/agents" "$HOME/.claude/agents" >/dev/null 2>&1
    ok_if 'target is now a symlink' '[ -h "$HOME/.claude/agents" ]'
    backed=$(find "$DOT_BACKUP_ROOT" -name 'mine.md' -type f | head -n 1)
    ok_if 'directory contents preserved in backup' '[ -n "$backed" ]'
    expect 'backed-up file content intact' 'user agent' "$(cat "$backed" 2>/dev/null)"
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 7: dry-run has zero side effects ==\n'
(
    sandbox
    printf 'UNTOUCHED\n' >"$HOME/.zshrc"
    export DOT_DRY_RUN=1
    out=$(dot_link "$SBOX/repo/zshrc" "$HOME/.zshrc" 2>&1)
    ok_if 'target still a regular file' '[ -f "$HOME/.zshrc" ] && [ ! -h "$HOME/.zshrc" ]'
    expect 'content unchanged' 'UNTOUCHED' "$(cat "$HOME/.zshrc")"
    ok_if 'no backup dir' '[ ! -d "$DOT_BACKUP_ROOT" ]'
    ok_if 'prints dry-run plan' 'printf "%s" "$out" | grep -q "dry-run"'
    # dry-run 也不应创建父目录
    dot_link "$SBOX/repo/zshrc" "$HOME/.config/new/x" >/dev/null 2>&1
    ok_if 'dry-run does not create parent dirs' '[ ! -d "$HOME/.config/new" ]'
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 8: missing source is an error ==\n'
(
    sandbox
    if dot_link "$SBOX/repo/does-not-exist" "$HOME/.zshrc" >/dev/null 2>&1; then
        _fail=$((_fail + 1))
        printf 'FAIL missing source should fail\n'
    else
        _pass=$((_pass + 1))
        printf 'ok   missing source returns non-zero\n'
    fi
    ok_if 'no link created' '[ ! -e "$HOME/.zshrc" ]'
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 9: broken symlink at target is replaced ==\n'
(
    sandbox
    ln -s "$SBOX/gone" "$HOME/.zshrc"
    ok_if 'precondition: target is a broken link' '[ -h "$HOME/.zshrc" ] && [ ! -e "$HOME/.zshrc" ]'
    dot_link "$SBOX/repo/zshrc" "$HOME/.zshrc" >/dev/null 2>&1
    expect 'broken link replaced' "$SBOX/repo/zshrc" "$(readlink "$HOME/.zshrc")"
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 10: backup preserves path structure ==\n'
(
    sandbox
    mkdir -p "$HOME/.config/starship"
    printf 'old\n' >"$HOME/.config/starship/config.toml"
    dot_link "$SBOX/repo/zshrc" "$HOME/.config/starship/config.toml" >/dev/null 2>&1
    ok_if 'backup keeps relative path under HOME' \
        '[ -f "$DOT_BACKUP_DIR/.config/starship/config.toml" ]'
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 11: dot_write idempotence ==\n'
(
    sandbox
    printf 'hello\n' | dot_write "$HOME/.config/gen/out.txt" >/dev/null 2>&1
    expect 'writes content' 'hello' "$(cat "$HOME/.config/gen/out.txt")"
    before=$(ls -lT "$HOME/.config/gen/out.txt" 2>/dev/null || ls -l --time-style=full-iso "$HOME/.config/gen/out.txt")
    out=$(printf 'hello\n' | dot_write "$HOME/.config/gen/out.txt" 2>&1)
    after=$(ls -lT "$HOME/.config/gen/out.txt" 2>/dev/null || ls -l --time-style=full-iso "$HOME/.config/gen/out.txt")
    expect 'same content = no rewrite' "$before" "$after"
    ok_if 'reports unchanged' 'printf "%s" "$out" | grep -q "unchanged"'
    printf 'changed\n' | dot_write "$HOME/.config/gen/out.txt" >/dev/null 2>&1
    expect 'different content rewrites' 'changed' "$(cat "$HOME/.config/gen/out.txt")"
    perms=$(ls -l "$HOME/.config/gen/out.txt" | cut -c1-10)
    expect 'default mode is 644' '-rw-r--r--' "$perms"
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 11b: dot_write idempotence without diffutils ==\n'
#
# 幂等判定不得依赖 cmp/diff —— 它们属于 diffutils，不是必装包。
# rockylinux:9 的最小镜像里两个都没有，而 debian:stable-slim 里有 cmp，
# 所以旧实现能在 debian 容器 job 里一路绿灯。
# 缺 cmp 时 `cmp -s a b` 返回非零 → 被当成「内容不同」→ 每次都重写，
# 幂等性在整个 RHEL 族上静默失效。实测 Rocky 9 就是这么发现的。
#
# 这里把 PATH 收窄到只有必需命令（刻意不含 cmp/diff）再验一次。
(
    sandbox
    NODIFF="$HOME/nodiff-bin"
    mkdir -p "$NODIFF"
    for _c in sh printf cat mktemp rm mkdir chmod wc dirname date ls sed grep tr id find mv cp; do
        _p=$(command -v "$_c" 2>/dev/null) && ln -sf "$_p" "$NODIFF/$_c"
    done
    ok_if 'the narrowed PATH really has no cmp' \
        '! PATH="$NODIFF" command -v cmp >/dev/null 2>&1'

    printf 'hello\n' | dot_write "$HOME/.config/nd/out.txt" >/dev/null 2>&1
    before=$(ls -lT "$HOME/.config/nd/out.txt" 2>/dev/null ||
        ls -l --time-style=full-iso "$HOME/.config/nd/out.txt")
    out=$(printf 'hello\n' | PATH="$NODIFF" dot_write "$HOME/.config/nd/out.txt" 2>&1)
    after=$(ls -lT "$HOME/.config/nd/out.txt" 2>/dev/null ||
        ls -l --time-style=full-iso "$HOME/.config/nd/out.txt")
    expect 'same content = no rewrite even without cmp' "$before" "$after"
    ok_if 'still reports unchanged' 'printf "%s" "$out" | grep -q "unchanged"'
    # 反面：内容不同时仍然要写
    printf 'other\n' | PATH="$NODIFF" dot_write "$HOME/.config/nd/out.txt" >/dev/null 2>&1
    expect 'different content still rewrites' 'other' "$(cat "$HOME/.config/nd/out.txt")"
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n== case 12: dot_write honors explicit mode (secrets) ==\n'
(
    sandbox
    printf 'secret\n' | dot_write "$HOME/.config/dotfiles/env.local" 600 >/dev/null 2>&1
    perms=$(ls -l "$HOME/.config/dotfiles/env.local" | cut -c1-10)
    expect 'mode 600 applied' '-rw-------' "$perms"
    cleanup
    printf '%s %s\n' "$_pass" "$_fail" >"$DOT_SCORE"
)
tally

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
