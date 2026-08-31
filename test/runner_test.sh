#!/usr/bin/env sh
#
# lib/runner.sh 与 bootstrap.sh 的断言测试。
#
# 用临时的替身模块目录（DOT_MODULES_DIR）验证 runner 行为，
# 不依赖真实 modules/ 的内容，因此新增真实模块不会让这些测试失效。
#
#   sh test/runner_test.sh
#   dash test/runner_test.sh
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BOOT="$DOT_REPO/bootstrap.sh"

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

# 断言输出中包含某个子串
expect_has() {
    if printf '%s' "$3" | grep -q -- "$2"; then
        _pass=$((_pass + 1))
        printf 'ok   %s\n' "$1"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s\n       expected output to contain: %s\n       got: %s\n' "$1" "$2" "$3"
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

# 写一个替身模块
mkmod() {
    mkdir -p "$FIX/$1"
    cat >"$FIX/$1/module.sh"
}

# 用替身模块目录跑 bootstrap，回显合并后的输出
run() {
    DOT_MODULES_DIR="$FIX" sh "$BOOT" "$@" 2>&1
}

# 同上但只要退出码
rc() {
    DOT_MODULES_DIR="$FIX" sh "$BOOT" "$@" >/dev/null 2>&1
    printf '%s' "$?"
}

# ------------------------------------------------------------------ 依赖排序

mkmod base <<'EOF'
MODULE_DESC="base module"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="core"
install() { dot_info "RAN:base"; }
EOF
mkmod mid <<'EOF'
MODULE_DESC="mid module"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="core"
MODULE_REQUIRES="base"
install() { dot_info "RAN:mid"; }
EOF
mkmod leaf <<'EOF'
MODULE_DESC="leaf module"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="core"
MODULE_REQUIRES="mid"
install() { dot_info "RAN:leaf"; }
EOF

printf '== dependency ordering ==\n'
order=$(run --only leaf | grep 'RAN:' | sed 's/.*RAN://' | tr '\n' ' ' | sed 's/ $//')
expect 'dependencies run before dependents' 'base mid leaf' "$order"

out=$(run --only base)
expect_lacks 'selecting a dependency alone does not pull dependents' 'RAN:leaf' "$out"

printf '\n== module discovery ==\n'
out=$(run --list)
expect_has 'newly created module is discovered' 'leaf' "$out"
expect_has 'list shows description' 'leaf module' "$out"
expect_has 'list shows platforms' 'macos linux windows' "$out"
expect 'list exits 0' 0 "$(rc --list)"

printf '\n== --list and --info are side-effect free ==\n'
before=$(find "$FIX" -type f | sort)
run --list >/dev/null
run --info >/dev/null
after=$(find "$FIX" -type f | sort)
expect 'no files created by --list/--info' "$before" "$after"

printf '\n== --help is dynamic ==\n'
out=$(run --help)
expect_has 'help mentions available tags' 'Available tags' "$out"
expect_has 'help points at --list instead of hardcoding modules' -- "$out"
# 帮助里不应出现硬编码的模块名清单：加一个古怪标签的模块，它应出现在标签行
mkmod oddball <<'EOF'
MODULE_DESC="oddly tagged"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="zzquirky"
install() { :; }
EOF
out=$(run --help)
expect_has 'tags line reflects modules on disk' 'zzquirky' "$out"
rm -rf "$FIX/oddball"

# ------------------------------------------------------------------ 环与未知依赖

printf '\n== circular dependency ==\n'
mkmod cyca <<'EOF'
MODULE_DESC="a"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="cyc"
MODULE_REQUIRES="cycb"
install() { :; }
EOF
mkmod cycb <<'EOF'
MODULE_DESC="b"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="cyc"
MODULE_REQUIRES="cyca"
install() { :; }
EOF
out=$(run --only cyca)
expect_has 'cycle is reported' 'circular dependency' "$out"
expect_has 'cycle shows the chain' 'cyca -> cycb -> cyca' "$out"
expect 'cycle exits non-zero' 1 "$(rc --only cyca)"
expect_lacks 'nothing runs when a cycle exists' 'RAN:' "$out"
rm -rf "$FIX/cyca" "$FIX/cycb"

printf '\n== unknown dependency ==\n'
mkmod orphan <<'EOF'
MODULE_DESC="depends on a ghost"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="orph"
MODULE_REQUIRES="ghost"
install() { :; }
EOF
out=$(run --only orphan)
expect_has 'unknown dependency is reported' "unknown dependency 'ghost'" "$out"
expect 'unknown dependency exits non-zero' 1 "$(rc --only orphan)"
rm -rf "$FIX/orphan"

# ------------------------------------------------------------------ 元数据校验

printf '\n== module validation ==\n'
mkdir -p "$FIX/nometa"
printf 'MODULE_DESC="x"\nMODULE_TAGS="core"\ninstall() { :; }\n' >"$FIX/nometa/module.sh"
out=$(run --list)
expect_has 'missing MODULE_PLATFORMS is rejected' 'missing MODULE_PLATFORMS' "$out"
expect 'invalid module makes bootstrap exit non-zero' 1 "$(rc --list)"
rm -rf "$FIX/nometa"

mkdir -p "$FIX/nodesc"
printf 'MODULE_PLATFORMS="macos"\nMODULE_TAGS="core"\ninstall() { :; }\n' >"$FIX/nodesc/module.sh"
expect_has 'missing MODULE_DESC is rejected' 'missing MODULE_DESC' "$(run --list)"
rm -rf "$FIX/nodesc"

mkdir -p "$FIX/notags"
printf 'MODULE_DESC="x"\nMODULE_PLATFORMS="macos"\ninstall() { :; }\n' >"$FIX/notags/module.sh"
expect_has 'missing MODULE_TAGS is rejected' 'missing MODULE_TAGS' "$(run --list)"
rm -rf "$FIX/notags"

# /usr/bin/install 是标准工具，缺少 install() 的模块不能因此被误判为合规
mkdir -p "$FIX/noinstall"
printf 'MODULE_DESC="x"\nMODULE_PLATFORMS="macos"\nMODULE_TAGS="core"\n' >"$FIX/noinstall/module.sh"
out=$(run --list)
expect_has 'missing install() is rejected despite /usr/bin/install existing' \
    'missing install() function' "$out"
expect 'missing install() exits non-zero' 1 "$(rc --list)"
rm -rf "$FIX/noinstall"

# ------------------------------------------------------------------ 过滤

printf '\n== platform filtering ==\n'
mkmod winonly <<'EOF'
MODULE_DESC="windows only"
MODULE_PLATFORMS="windows"
MODULE_TAGS="filt"
install() { dot_info "RAN:winonly"; }
EOF
out=$(DOT_MODULES_DIR="$FIX" DOT_OS=macos sh "$BOOT" --tag filt 2>&1)
expect_lacks 'wrong-platform module does not run' 'RAN:winonly' "$out"
expect_has 'skip states the reason' 'platform not supported' "$out"
expect_has 'skip names the required platform' 'needs: windows' "$out"

printf '\n== headless filtering ==\n'
mkmod guimod <<'EOF'
MODULE_DESC="needs a GUI"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="filt"
MODULE_NEEDS_GUI="1"
install() { dot_info "RAN:guimod"; }
EOF
out=$(DOT_MODULES_DIR="$FIX" CI=1 sh "$BOOT" --tag filt 2>&1)
expect_lacks 'GUI module skipped when headless' 'RAN:guimod' "$out"
expect_has 'headless skip states the reason' 'requires a graphical environment' "$out"

out=$(DOT_MODULES_DIR="$FIX" CI= SSH_CONNECTION= SSH_TTY= SSH_CLIENT= sh "$BOOT" --tag filt 2>&1)
expect_has 'GUI module runs when not headless' 'RAN:guimod' "$out"
rm -rf "$FIX/winonly" "$FIX/guimod"

# ------------------------------------------------------------------ 失败处理

printf '\n== failure handling ==\n'
mkmod boom <<'EOF'
MODULE_DESC="always fails"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="failgrp"
install() { dot_error "intentional failure"; return 1; }
EOF
mkmod after_boom <<'EOF'
MODULE_DESC="depends on boom"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="failgrp"
MODULE_REQUIRES="boom"
install() { dot_info "RAN:after_boom"; }
EOF
mkmod sibling <<'EOF'
MODULE_DESC="independent"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="failgrp"
install() { dot_info "RAN:sibling"; }
EOF
out=$(run --tag failgrp)
expect_has 'independent module still runs after a failure' 'RAN:sibling' "$out"
expect_lacks 'dependent of a failed module does not run' 'RAN:after_boom' "$out"
expect_has 'dependent is marked skipped with cause' 'dependency failed: boom' "$out"
expect_has 'summary lists failures' 'failed (1)' "$out"
expect_has 'summary lists successes' 'succeeded (1)' "$out"
expect_has 'summary lists skips' 'skipped (1)' "$out"
expect 'any failure means non-zero exit' 1 "$(rc --tag failgrp)"
rm -rf "$FIX/boom" "$FIX/after_boom" "$FIX/sibling"

# ------------------------------------------------------------------ 选择

printf '\n== module selection ==\n'
expect 'unknown --only module exits non-zero' 1 "$(rc --only definitely-not-a-module)"
expect_has 'unknown module is named in the error' 'unknown module' \
    "$(run --only definitely-not-a-module)"
expect 'unknown --skip module exits non-zero' 1 "$(rc --skip definitely-not-a-module)"

out=$(run --skip leaf --tag core)
expect_has '--skip keeps other modules' 'RAN:base' "$out"
expect_lacks '--skip excludes the named module' 'RAN:leaf' "$out"

out=$(run --only base,mid)
expect_has 'comma-separated --only works (first)' 'RAN:base' "$out"
expect_has 'comma-separated --only works (second)' 'RAN:mid' "$out"

expect 'nonexistent tag exits non-zero' 1 "$(rc --tag no-such-tag)"

printf '\n== unknown option ==\n'
expect 'unknown flag exits non-zero' 1 "$(rc --nonsense)"
expect_has 'unknown flag is reported' 'unknown option' "$(run --nonsense)"

# ------------------------------------------------------------------ dry-run

printf '\n== dry-run ==\n'
mkmod writer <<'EOF'
MODULE_DESC="writes a file via the fs primitives"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="dry"
install() {
    printf 'content\n' | dot_write "$DOT_TEST_TARGET"
}
EOF
target="$FIX/should-not-exist.txt"
out=$(DOT_MODULES_DIR="$FIX" DOT_TEST_TARGET="$target" sh "$BOOT" --dry-run --tag dry 2>&1)
expect_has 'dry-run announces itself' 'dry run' "$out"
if [ -e "$target" ]; then
    _fail=$((_fail + 1))
    printf 'FAIL dry-run must not create files\n'
else
    _pass=$((_pass + 1))
    printf 'ok   dry-run creates no files\n'
fi
# 非 dry-run 时同一模块确实会写
DOT_MODULES_DIR="$FIX" DOT_TEST_TARGET="$target" sh "$BOOT" --tag dry >/dev/null 2>&1
if [ -f "$target" ]; then
    _pass=$((_pass + 1))
    printf 'ok   real run does create the file (proves dry-run was the difference)\n'
else
    _fail=$((_fail + 1))
    printf 'FAIL real run should have created the file\n'
fi
rm -rf "$FIX/writer" "$target"

# ------------------------------------------------------------------ 幂等

printf '\n== idempotence ==\n'
mkmod linker <<'EOF'
MODULE_DESC="links a file"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="idem"
install() {
    dot_link "$DOT_TEST_SRC" "$DOT_TEST_DST"
}
EOF
src="$FIX/src.conf"
printf 'src\n' >"$src"
dst="$FIX/home/.conf"
export DOT_BACKUP_ROOT="$FIX/backup"
DOT_MODULES_DIR="$FIX" DOT_TEST_SRC="$src" DOT_TEST_DST="$dst" \
    sh "$BOOT" --tag idem >/dev/null 2>&1
first=$(ls -l "$dst")
out=$(DOT_MODULES_DIR="$FIX" DOT_TEST_SRC="$src" DOT_TEST_DST="$dst" \
    sh "$BOOT" --tag idem 2>&1)
second=$(ls -l "$dst")
expect 'second run leaves the link untouched' "$first" "$second"
expect_has 'second run reports it as already linked' 'already linked' "$out"
if [ -d "$DOT_BACKUP_ROOT" ]; then
    _fail=$((_fail + 1))
    printf 'FAIL idempotent rerun must not create backups\n'
else
    _pass=$((_pass + 1))
    printf 'ok   idempotent rerun creates no backup\n'
fi
expect 'idempotent rerun exits 0' 0 \
    "$(
        DOT_MODULES_DIR="$FIX" DOT_TEST_SRC="$src" DOT_TEST_DST="$dst" \
            sh "$BOOT" --tag idem >/dev/null 2>&1
        printf '%s' "$?"
    )"

printf '\n== path overrides are honoured ==\n'
# 这三个变量必须用 ${X:-default} 赋值。曾三次踩到同一个坑：
# bootstrap.sh 无条件赋值 -> 环境里预设的替身目录被静默丢弃 ->
# 测试在「以为用了替身、实际用了真目录」的前提下假通过。
# 这里直接断言覆盖生效，让回归立刻可见。
for _v in DOT_MODULES_DIR DOT_CONFIG_DIR DOT_PLATFORM_DIR; do
    if grep -q "^${_v}=\${${_v}:-" "$BOOT"; then
        _pass=$((_pass + 1))
        printf 'ok   %s is overridable\n' "$_v"
    else
        _fail=$((_fail + 1))
        printf 'FAIL %s must be assigned as ${%s:-default} so tests can override it\n' "$_v" "$_v"
    fi
done

# 行为层面的验证：指向一个替身 modules 目录，真实模块就不该出现
out=$(run --list)
expect_lacks 'real modules are invisible when DOT_MODULES_DIR is overridden' 'ai-agent-config' "$out"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
