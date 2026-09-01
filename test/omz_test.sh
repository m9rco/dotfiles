#!/usr/bin/env sh
#
# modules/omz 的断言测试。
#
# 不真 clone —— 网络请求会让测试慢且在离线/CI 受限环境下不可靠。手段是
# 往 PATH 前面放一个假的 git：它把「被要求 clone 什么」记进日志，并按需
# 造出真实 clone 会产生的入口文件，于是安装动作变成可观测的记录动作。
#
# 所有用例都在沙箱 HOME + DOT_OMZ_DIR 里跑，绝不碰真实的 ~/.oh-my-zsh。
#
#   sh test/omz_test.sh
#   dash test/omz_test.sh
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

# ------------------------------------------------------------------ 替身 git
#
# 造一个假 git 放进 PATH 最前面。它只认 clone，其余子命令（模块本身不用，
# 但 bootstrap 的其他部分可能用）转交真 git。
#
# MODE 控制行为：
#   ok   —— 记录并造出入口文件，模拟成功
#   fail —— 记录并返回非零，模拟仓库不可达
make_fake_git() {
    _fg_bin="$FIX/bin"
    mkdir -p "$_fg_bin"

    # 真 git 的位置要在生成脚本时就固定下来 —— 脚本运行时 PATH 已被
    # 改写，再查 git 会查到它自己，无限递归。
    _fg_real=$(command -v git 2>/dev/null || printf '/usr/bin/git')

    cat >"$_fg_bin/git" <<FAKEGIT
#!/usr/bin/env sh
if [ "\${1:-}" != clone ]; then
    exec $_fg_real "\$@"
fi

# 目标目录是最后一个参数；仓库 URL 是倒数第二个
for _a in "\$@"; do
    _url=\$_prev
    _prev=\$_a
done
_dest=\$_prev
# 整条命令行都记下来，好让「是否用了 --depth」这类断言可验证
printf 'argv: %s\n' "\$*" >>"$FIX/clone.log"
printf '%s -> %s\n' "\$_url" "\$_dest" >>"$FIX/clone.log"

if [ "\$(cat "$FIX/mode")" = fail ]; then
    exit 1
fi

# 造出真实 clone 会有的入口文件，让幂等判定能生效
mkdir -p "\$_dest"
case \$_dest in
    *.oh-my-zsh) : >"\$_dest/oh-my-zsh.sh" ;;
    *) _name=\$(basename -- "\$_dest"); : >"\$_dest/\$_name.plugin.zsh" ;;
esac
exit 0
FAKEGIT
    chmod +x "$_fg_bin/git"
}

# 跑一次 omz 模块。额外参数透传给 bootstrap。
# 每次用独立的沙箱 HOME 与 DOT_OMZ_DIR，用例之间互不影响。
run_omz() {
    _ro_box=$1
    shift
    mkdir -p "$_ro_box"
    : >"$FIX/clone.log"
    HOME="$_ro_box" \
        DOT_OMZ_DIR="$_ro_box/.oh-my-zsh" \
        DOT_BACKUP_ROOT="$_ro_box/bk" \
        PATH="$FIX/bin:$PATH" \
        sh "$BOOT" --only omz "$@" </dev/null 2>&1
}

clone_log() {
    cat "$FIX/clone.log" 2>/dev/null
}

make_fake_git
printf 'ok\n' >"$FIX/mode"

# ------------------------------------------------------------------ 基本安装

printf '== a fresh machine gets the framework and all three plugins ==\n'

BOX1="$FIX/box1"
out=$(run_omz "$BOX1")
log=$(clone_log)

expect_has 'the framework is cloned' 'ohmyzsh.git' "$log"
expect_has 'the clone is shallow (no full history)' 'depth' "$out$log"
ok_if 'oh-my-zsh.sh ends up in place' "[ -f '$BOX1/.oh-my-zsh/oh-my-zsh.sh' ]"
expect_has 'the module reports success' 'oh-my-zsh installed' "$out"

# 三个插件都要装，且目录名必须与 20-omz.zsh 的探测路径一致
for p in zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search; do
    expect_has "$p is cloned" "$p" "$log"
    ok_if "$p has its plugin entry file" \
        "[ -f '$BOX1/.oh-my-zsh/custom/plugins/$p/$p.plugin.zsh' ]"
done

expect_has 'the summary counts three plugins' 'plugins installed: 3' "$out"

# ------------------------------------------------------------------ 名字契约
#
# 插件目录名与 config/zsh/zshrc.d/20-omz.zsh 的探测路径是一个跨文件契约：
# 名字对不上时插件装好了却不会被加载，而且没有任何报错。两处都改才算改对。

printf '\n== plugin names match what 20-omz.zsh looks for ==\n'

FRAG="$DOT_REPO/config/zsh/zshrc.d/20-omz.zsh"
ok_if 'the omz fragment exists' "[ -f '$FRAG' ]"
for p in zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search; do
    ok_if "20-omz.zsh references $p" "grep -q '$p' '$FRAG'"
done

# 反向：模块声明的插件列表不应出现片段里没提到的名字
mod_plugins=$(grep '^DOT_OMZ_PLUGINS=' "$DOT_REPO/modules/omz/module.sh" |
    sed "s/^DOT_OMZ_PLUGINS='//; s/'$//")
unreferenced=''
for p in $mod_plugins; do
    grep -q "$p" "$FRAG" || unreferenced="$unreferenced $p"
done
expect 'every plugin the module installs is referenced by the fragment' '' "$unreferenced"

# ------------------------------------------------------------------ 幂等

printf '\n== a second run changes nothing ==\n'

out=$(run_omz "$BOX1")
log=$(clone_log)

expect 'nothing is cloned again' '' "$log"
expect_has 'the framework is reported as already present' 'already installed' "$out"
expect_has 'the summary counts three as present' 'already present: 3' "$out"

# ------------------------------------------------------------------ dry-run

printf '\n== dry-run touches nothing ==\n'

BOX2="$FIX/box2"
out=$(run_omz "$BOX2" --dry-run)
log=$(clone_log)

expect 'dry-run does not clone' '' "$log"
ok_if 'dry-run creates no oh-my-zsh directory' "[ ! -d '$BOX2/.oh-my-zsh' ]"
expect_has 'dry-run says what it would do' 'would clone' "$out"

# ------------------------------------------------------------------ 沙箱隔离
#
# 模块刻意不读 $ZSH —— 交互式 shell 会导出它，指向真实家目录，读了会
# 让 HOME 沙箱失效（开发时真的踩到过：测试往 ~/.oh-my-zsh 里装了东西）。

printf '\n== an ambient $ZSH does not escape the sandbox ==\n'

BOX3="$FIX/box3"
mkdir -p "$BOX3"
: >"$FIX/clone.log"
out=$(HOME="$BOX3" ZSH="$FIX/decoy-must-not-be-touched" \
    DOT_OMZ_DIR="$BOX3/.oh-my-zsh" DOT_BACKUP_ROOT="$BOX3/bk" \
    PATH="$FIX/bin:$PATH" sh "$BOOT" --only omz </dev/null 2>&1)

ok_if 'the decoy directory is never created' "[ ! -d '$FIX/decoy-must-not-be-touched' ]"
expect_lacks 'no clone targets the ambient $ZSH path' 'decoy' "$(clone_log)"
ok_if 'the sandbox got the framework instead' "[ -f '$BOX3/.oh-my-zsh/oh-my-zsh.sh' ]"

# ------------------------------------------------------------------ 失败处理

printf '\n== a failed clone is reported, not swallowed ==\n'

printf 'fail\n' >"$FIX/mode"
BOX4="$FIX/box4"
out=$(run_omz "$BOX4")
rc=$?

expect 'the module exits non-zero' '1' "$rc"
expect_has 'the failure is named' 'failed to clone' "$out"
printf 'ok\n' >"$FIX/mode"

# 插件 clone 失败不该留下半个目录 —— 那会让下一次运行撞上「目录非空」检查
printf '\n== a failed plugin clone leaves no debris ==\n'

BOX5="$FIX/box5"
mkdir -p "$BOX5/.oh-my-zsh"
: >"$BOX5/.oh-my-zsh/oh-my-zsh.sh" # 框架已就位，只让插件失败
printf 'fail\n' >"$FIX/mode"
out=$(run_omz "$BOX5")
printf 'ok\n' >"$FIX/mode"

expect_has 'plugin failure is reported' 'could not install plugin' "$out"
expect_has 'the tip says zsh still works' 'zsh still works' "$out"
ok_if 'no half-cloned plugin directory is left behind' \
    "[ -z \"\$(ls -A '$BOX5/.oh-my-zsh/custom/plugins' 2>/dev/null)\" ]"

# 装完还能再跑 —— 失败后重试不应被自己留下的残骸挡住
out=$(run_omz "$BOX5")
expect_has 'a retry after failure succeeds' 'plugins installed: 3' "$out"

# ------------------------------------------------------------------ 非空目录

printf '\n== a non-empty target is refused, not silently wiped ==\n'

BOX6="$FIX/box6"
mkdir -p "$BOX6/.oh-my-zsh"
printf 'precious\n' >"$BOX6/.oh-my-zsh/user-data.txt"
out=$(run_omz "$BOX6")
rc=$?

expect 'the module refuses to proceed' '1' "$rc"
expect_has 'it explains why' 'no oh-my-zsh.sh' "$out"
ok_if "the user's file is untouched" "[ -f '$BOX6/.oh-my-zsh/user-data.txt' ]"
expect 'nothing was cloned into it' '' "$(clone_log)"

# ------------------------------------------------------------------ 缺 git

printf '\n== a missing git fails loudly ==\n'

# 直接 source 模块并调 install()，不走 bootstrap —— 走 bootstrap 的话，
# 没有 git 的 PATH 会连带让 zsh 依赖装不上（brew 也不在 PATH 里），于是
# omz 因依赖失败被跳过，根本走不到 git 检查。那样测的是 runner 的依赖
# 机制，不是本模块的前置检查。
#
# git 的「缺失」用一个只放了基础命令、没有 git 的 PATH 来实现 ——
# 覆盖 command 这个内建更省事，但那会连带改掉模块里所有的 command 调用，
# 是在测一个被我们改造过的模块。
BOX7="$FIX/box7"
mkdir -p "$BOX7"
NOGIT="$FIX/nogit-bin"
mkdir -p "$NOGIT"
for c in sh env printf mkdir rm ls cat grep sed basename dirname chmod ln find date tr; do
    _p=$(command -v "$c" 2>/dev/null) && ln -sf "$_p" "$NOGIT/$c" 2>/dev/null
done
ok_if 'the git-less PATH really has no git' "! PATH='$NOGIT' command -v git >/dev/null 2>&1"

out=$(
    HOME="$BOX7"
    DOT_OMZ_DIR="$BOX7/.oh-my-zsh"
    DOT_ROOT="$DOT_REPO"
    DOT_LIB_DIR="$DOT_REPO/lib"
    DOT_DRY_RUN=0
    export HOME DOT_OMZ_DIR DOT_ROOT DOT_LIB_DIR DOT_DRY_RUN
    # shellcheck disable=SC1091
    . "$DOT_REPO/lib/log.sh"
    # shellcheck disable=SC1091
    . "$DOT_REPO/lib/fs.sh"
    # shellcheck disable=SC1091
    . "$DOT_REPO/modules/omz/module.sh"
    PATH="$NOGIT"
    export PATH
    install 2>&1
    printf 'rc=%s\n' "$?"
)

expect_has 'the missing git is named' 'git is required' "$out"
expect_has 'it exits non-zero' 'rc=1' "$out"
ok_if 'nothing is installed without git' "[ ! -d '$BOX7/.oh-my-zsh' ]"

# ------------------------------------------------------------------ 模块元数据

printf '\n== module metadata ==\n'

MOD="$DOT_REPO/modules/omz/module.sh"
ok_if 'omz declares a dependency on zsh' "grep -q 'MODULE_REQUIRES=.*zsh' '$MOD'"
# omz 是 Unix 的东西；Windows 侧走 PowerShell profile，不该被列进来
platforms=$(grep '^MODULE_PLATFORMS=' "$MOD" | cut -d'"' -f2)
expect 'omz is macos+linux only' 'macos linux' "$platforms"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
