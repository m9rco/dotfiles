#!/usr/bin/env sh
#
# legacy-migration spec 的断言测试。
#
# 迁移是一次性的破坏性操作，所以这些断言的价值在于「防回归」：
# 如果有人不小心把子模块加回来、或让 private/ 重新出现，这里会立刻发现。
#
#   sh test/migration_test.sh
#
# shellcheck shell=sh

set -u

DOT_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DOT_ROOT" || exit 1

_pass=0
_fail=0

ok_if() {
    if eval "$2"; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s  (condition: %s)\n' "$1" "$2"
    fi
}

expect() {
    if [ "$2" = "$3" ]; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$1" "$2" "$3"
    fi
}

if [ ! -d .git ]; then
    printf 'not a git working copy; skipping migration assertions\n'
    exit 0
fi

# ------------------------------------------------------------------ 子模块

printf '== git submodules are gone for good ==\n'
expect 'no gitlinks remain in the index' '0' \
    "$(git ls-files -s | awk '$1=="160000"' | wc -l | tr -d ' ')"
ok_if '.gitmodules does not exist' '[ ! -f .gitmodules ]'
# git 在属主不匹配时会拒绝操作（容器 CI 里常见）。那不是「有子模块」，
# 要单独识别，否则断言的失败信息会指向错误的方向。
_sub_status=$(git submodule status 2>&1)
case $_sub_status in
    *'dubious ownership'*)
        printf 'skip git submodule status (git refuses: dubious ownership)\n'
        printf '     fix in CI with: git config --global --add safe.directory <path>\n'
        ;;
    *)
        expect 'git submodule status is empty' '' "$_sub_status"
        ;;
esac
ok_if '.git/modules has no leftovers' '[ -z "$(ls -A .git/modules 2>/dev/null)" ]'
ok_if 'docker/ is gone from the working tree' '[ ! -d docker ]'

printf '\n== no third-party plugin sources are carried ==\n'
ok_if 'no vim plugin directory' '[ ! -d private/vim/plugins ] && [ ! -d config/vim/plugins ]'
# 归档里可以有 vimrc.plugins（那是清单，不是插件源码）
ok_if 'the old vim-plug manifest is archived for reference' \
    '[ -f legacy/private/vim/vimrc.plugins ]'

# ------------------------------------------------------------------ 归档

printf '\n== private/ is archived, not deleted ==\n'
ok_if 'top-level private/ is gone' '[ ! -d private ]'
ok_if 'legacy/private/ exists' '[ -d legacy/private ]'
ok_if 'the old install.sh is in the archive' '[ -f legacy/private/install.sh ]'
ok_if 'the archive is not empty' '[ "$(find legacy/private -type f | wc -l | tr -d " ")" -gt 30 ]'
ok_if 'legacy/ has a README explaining the archive' '[ -f legacy/README.md ]'

printf '\n== the old install script is no longer an entry point ==\n'
ok_if 'no install.sh at the repo root' '[ ! -f install.sh ]'
ok_if 'the old lib/utils.sh copy is gone' '[ ! -f lib/utils.sh ]'

printf '\n== legacy/ does not participate in installation ==\n'
listing=$(./bootstrap.sh --list 2>/dev/null || true)
ok_if 'no module comes from legacy/' \
    '! printf "%s" "$listing" | grep -qi legacy'

# ------------------------------------------------------------------ 目录结构

printf '\n== the new layout is in place ==\n'
for d in lib platform config modules legacy test bin; do
    ok_if "$d/ exists" "[ -d $d ]"
done
ok_if 'bootstrap.sh exists' '[ -f bootstrap.sh ]'
ok_if 'bootstrap.ps1 exists' '[ -f bootstrap.ps1 ]'

printf '\n== config/ holds content, modules/ holds logic ==\n'
# config/ 下不该有安装脚本（zshrc 等是被 link 的配置，不是安装逻辑）
ok_if 'no module.sh under config/' \
    '[ -z "$(find config -name "module.sh" 2>/dev/null)" ]'
# modules/ 下不该有被 link 的配置文件
ok_if 'no zshrc-like config under modules/' \
    '[ -z "$(find modules -name "zshrc" -o -name "gitconfig" 2>/dev/null)" ]'

# ------------------------------------------------------------------ CI

printf '\n== CI moved from Travis to GitHub Actions ==\n'
ok_if '.travis.yml is gone' '[ ! -f .travis.yml ]'
ok_if 'the GitHub Actions workflow exists' '[ -f .github/workflows/ci.yml ]'

if command -v yq >/dev/null 2>&1; then
    ok_if 'the workflow parses as YAML' 'yq "." .github/workflows/ci.yml >/dev/null 2>&1'
    jobs=$(yq '.jobs | keys | .[]' .github/workflows/ci.yml 2>/dev/null | tr -d '"' | tr '\n' ' ')
    for j in lint secrets test smoke windows container; do
        ok_if "the $j job is defined" "printf '%s' \"$jobs\" | grep -q $j"
    done
else
    printf 'skip (yq not installed) — workflow structure not checked\n'
fi

# ------------------------------------------------------------------ 文档

printf '\n== documentation reflects the new structure ==\n'
ok_if 'README mentions bootstrap.sh' 'grep -q "bootstrap.sh" README.md'
ok_if 'README mentions bootstrap.ps1' 'grep -q "bootstrap.ps1" README.md'
ok_if 'README has no stale submodule usage' \
    '! grep -qE "git submodule (add|foreach)" README.md'
ok_if 'README points at --list instead of a hardcoded module list' \
    'grep -q -- "--list" README.md'
ok_if 'an upgrade guide exists' '[ -f docs/UPGRADING.md ]'
ok_if 'the upgrade guide names the backup location' \
    'grep -q "dotfiles-backup" docs/UPGRADING.md'
ok_if 'the upgrade guide covers the git identity move' \
    'grep -q "gitconfig.local" docs/UPGRADING.md'

# ------------------------------------------------------------------ 迁移记录

printf '\n== the removal was documented before it happened ==\n'
NOTES=openspec/changes/modernize-dotfiles/notes
ok_if 'the submodule verification report exists' "[ -f $NOTES/submodule-removal.md ]"
ok_if 'the report records remote reachability' \
    "grep -q '远端可达' $NOTES/submodule-removal.md"
ok_if 'the vim plugin decision is written down' "[ -f $NOTES/vim-plugins.md ]"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
