#!/usr/bin/env sh
#
# modules/modern-cli 与 modules/git 的断言测试。
#
# 不真装软件包 —— 用替身清单 + 替身 platform 层，让「安装」变成可观测的
# 记录动作。这样测试快、可离线、且不改本机状态。
# git 相关用例全部在沙箱 HOME 里跑。
#
#   sh test/cli_test.sh
#   dash test/cli_test.sh
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

# 读取文件权限。BSD 与 GNU 的 stat 参数不同，且不能靠「失败再试」——
# GNU 的 -f 是显示文件系统信息，对任意文件都成功。校验输出形状才可靠。
# （被测代码里的 _dot_secret_mode 同理，见 lib/secrets.sh 的说明。）
file_mode() {
    _fm=$(stat -c '%a' "$1" 2>/dev/null)
    case $_fm in
        [0-7][0-7][0-7] | [0-7][0-7][0-7][0-7])
            printf '%s' "$_fm"
            return 0
            ;;
    esac
    _fm=$(stat -f '%Lp' "$1" 2>/dev/null)
    case $_fm in
        [0-7][0-7][0-7] | [0-7][0-7][0-7][0-7])
            printf '%s' "$_fm"
            return 0
            ;;
    esac
    printf 'unknown'
}

# ------------------------------------------------------------------ 替身平台层
#
# 把「安装」替换成往日志文件追加一行。这样能精确断言「哪些工具被尝试安装、
# 顺序如何」，而不用真的动包管理器。
# 同时用 DOT_TEST_FAKE_PRESENT 控制哪些工具被视为「已安装」。

mkdir -p "$FIX/platform"
cat >"$FIX/platform/macos.sh" <<'PLAT'
# shellcheck shell=sh
[ -n "${DOT_PLATFORM_MACOS_LOADED:-}" ] && return 0
DOT_PLATFORM_MACOS_LOADED=1
. "${DOT_LIB_DIR}/log.sh"

dot_platform_pkg_name() {
    # 模拟「某些工具在本平台的仓库里没有」
    case $1 in
        norepo) printf '' ;;
        *) printf '%s' "$1" ;;
    esac
}

dot_platform_pkg_install() {
    printf 'INSTALL:%s\n' "$1" >>"$DOT_TEST_LOG"
    # alwaysfails 用来验证「包管理器失败 -> 走回退链」
    case $1 in
        alwaysfails) return 1 ;;
        *) return 0 ;;
    esac
}

dot_platform_font_dir() { printf '%s' "${DOT_FONT_DIR:-$HOME/Library/Fonts}"; }
dot_platform_font_refresh() { return 0; }
PLAT
cp "$FIX/platform/macos.sh" "$FIX/platform/linux.sh"
sed -i.bak 's/DOT_PLATFORM_MACOS_LOADED/DOT_PLATFORM_LINUX_LOADED/g' "$FIX/platform/linux.sh"
rm -f "$FIX/platform/linux.sh.bak"

# 让 dot_pkg_installed 认为某些工具已存在：用一个只含替身可执行文件的 PATH
mkdir -p "$FIX/bin"
fake_present() {
    for _fp in "$@"; do
        printf '#!/bin/sh\nexit 0\n' >"$FIX/bin/$_fp"
        chmod +x "$FIX/bin/$_fp"
    done
}

# 跑 modern-cli，用替身清单与替身平台层
runcli() {
    _rc_manifest=$1
    shift
    mkdir -p "$FIX/cfg/cli"
    printf '%s\n' "$_rc_manifest" >"$FIX/cfg/cli/tools.txt"
    : >"$FIX/install.log"
    DOT_CONFIG_DIR="$FIX/cfg" \
        DOT_PLATFORM_DIR="$FIX/platform" \
        DOT_TEST_LOG="$FIX/install.log" \
        PATH="$FIX/bin:/usr/bin:/bin" \
        sh "$BOOT" --only modern-cli "$@" 2>&1
}

installed_log() {
    sed 's/^INSTALL://' "$FIX/install.log" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

# ------------------------------------------------------------------ 清单处理

printf '== every manifest entry is processed ==\n'
# 这是最关键的一条：曾经有过「包管理器从 stdin 吃掉剩余清单行、
# 循环提前结束却报成功」的 bug，12 个工具只装了前 3 个。
MANIFEST="one|all|default||first
two|all|default||second
three|all|default||third
four|all|default||fourth
five|all|default||fifth"
out=$(runcli "$MANIFEST")
expect 'all five entries reach the installer' 'one two three four five' "$(installed_log)"
expect_has 'summary counts them all' 'installed/present: 5' "$out"

printf '\n== comments and blank lines are skipped ==\n'
MANIFEST="# a comment

one|all|default||first
# another
two|all|default||second"
runcli "$MANIFEST" >/dev/null
expect 'only real entries are installed' 'one two' "$(installed_log)"

printf '\n== malformed line is reported ==\n'
out=$(runcli "brokenline")
expect_has 'malformed entry is named' 'malformed manifest line' "$out"

# ------------------------------------------------------------------ 幂等

printf '\n== already-present tools are skipped ==\n'
fake_present alreadythere
MANIFEST="alreadythere|all|default||present already
notyet|all|default||missing"
out=$(runcli "$MANIFEST")
expect 'present tool is not reinstalled' 'notyet' "$(installed_log)"
expect_has 'skip is reported' 'alreadythere already available' "$out"
rm -f "$FIX/bin/alreadythere"

# ------------------------------------------------------------------ 平台筛选

printf '\n== platform filtering ==\n'
# 显式钉住 DOT_OS —— 否则断言会随运行环境的平台而变
# （本机 macOS 通过、Ubuntu runner 上全红）
MANIFEST="everywhere|all|default||all platforms
thisplatform|macos|default||only for the pinned platform
otherplatform|windows|default||not for the pinned platform"
out=$(DOT_OS=macos runcli "$MANIFEST")
expect 'only entries for the current platform install' 'everywhere thisplatform' "$(installed_log)"
expect_has 'skipped entry states the platform' 'not for macos' "$out"

# ------------------------------------------------------------------ optional

printf '\n== optional tools need an explicit opt-in ==\n'
MANIFEST="normal|all|default||default tool
extra|all|optional||opt-in tool"
out=$(runcli "$MANIFEST")
expect 'optional tool is not installed by default' 'normal' "$(installed_log)"
expect_has 'optional skip explains itself' 'optional, not requested' "$out"

out=$(DOT_WANT_EXTRA=1 runcli "$MANIFEST")
expect 'DOT_WANT_<NAME> opts in' 'normal extra' "$(installed_log)"

out=$(DOT_CLI_OPTIONAL=extra runcli "$MANIFEST")
expect 'DOT_CLI_OPTIONAL opts in' 'normal extra' "$(installed_log)"

# 名字里有连字符时环境变量名的归一化
MANIFEST="some-tool|all|optional||hyphenated name"
DOT_WANT_SOME_TOOL=1 runcli "$MANIFEST" >/dev/null
expect 'hyphenated name maps to DOT_WANT_SOME_TOOL' 'some-tool' "$(installed_log)"

# ------------------------------------------------------------------ dry-run

printf '\n== dry-run installs nothing ==\n'
MANIFEST="one|all|default||first
two|all|default||second"
out=$(runcli "$MANIFEST" --dry-run)
expect 'no installer is invoked' '' "$(installed_log)"
expect_has 'plan is printed' 'would install' "$out"

# ------------------------------------------------------------------ 失败处理

printf '\n== a failing tool does not stop the rest ==\n'
MANIFEST="alwaysfails|all|default||this one fails
after|all|default||should still run"
out=$(runcli "$MANIFEST")
expect_has 'later tool is still attempted' 'INSTALL:after' "$(cat "$FIX/install.log")"
expect_has 'failure is reported' 'could not install' "$out"
expect_has 'the failed tool is named' 'alwaysfails' "$out"

printf '\n== failure makes the module exit non-zero ==\n'
mkdir -p "$FIX/cfg/cli"
printf '%s\n' "alwaysfails|all|default||fails" >"$FIX/cfg/cli/tools.txt"
: >"$FIX/install.log"
DOT_CONFIG_DIR="$FIX/cfg" DOT_PLATFORM_DIR="$FIX/platform" \
    DOT_TEST_LOG="$FIX/install.log" PATH="$FIX/bin:/usr/bin:/bin" \
    sh "$BOOT" --only modern-cli >/dev/null 2>&1
expect 'exit code reflects the failure' 1 "$?"

printf '\n== not in the repos: falls back ==\n'
# norepo 的包名映射返回空，应直接走回退链而不调用包管理器
MANIFEST="norepo|all|default|cargo:norepo-crate|not in repos"
out=$(runcli "$MANIFEST")
expect 'package manager is not called for it' '' "$(installed_log)"
expect_has 'fallback is attempted or reported' 'norepo' "$out"

# ------------------------------------------------------------------ 真实清单

printf '\n== the real manifest is well formed ==\n'
REAL="$DOT_REPO/config/cli/tools.txt"
ok_if 'real manifest exists' '[ -f "$REAL" ]'

bad=''
while IFS='|' read -r n p t f d; do
    case $n in '' | \#*) continue ;; esac
    if [ -z "$p" ] || [ -z "$t" ]; then
        bad="$bad $n"
        continue
    fi
    case $t in
        default | optional) ;;
        *) bad="$bad $n(tag=$t)" ;;
    esac
    # 每个工具都该有说明 —— 半年后回头看清单要能想起为什么装它
    [ -n "$d" ] || bad="$bad $n(no-desc)"
done <"$REAL"
expect 'every real entry has platforms, a valid tag and a description' '' "$bad"

# atuin 必须是 optional —— 它会接管 Ctrl-R 并改变历史行为
atuin_tag=$(grep '^atuin|' "$REAL" | cut -d'|' -f3)
expect 'atuin stays optional' 'optional' "$atuin_tag"

# 默认集应该正好是设计里确定的 14 个：12 个现代 CLI 工具，加上
# direnv 与 tmux —— 这两个是 zshrc.d 的片段已经引用的，不装它们
# 对应功能会静默失效。改这个数字前请确认新增的确实该默认装。
default_count=$(grep -vE '^\s*#|^\s*$' "$REAL" | cut -d'|' -f3 | grep -c '^default$')
expect 'the default set has 14 tools' '14' "$(printf '%s' "$default_count" | tr -d ' ')"

# 配置片段引用了却没人安装的工具是最难发现的一类问题 —— 装不上会报错，
# 而「压根没进清单」只是功能静默消失。这里把两处钉在一起。
for referenced in direnv tmux; do
    ok_if "$referenced is in the manifest (referenced by zshrc.d)" \
        "grep -q '^$referenced|' '$REAL'"
done

# ------------------------------------------------------------------ git 模块

printf '\n== git config is linked ==\n'
GB="$FIX/gitbox"
mkdir -p "$GB"
out=$(HOME="$GB" DOT_BACKUP_ROOT="$GB/bk" sh "$BOOT" --only git </dev/null 2>&1)
ok_if 'gitconfig is linked' '[ -h "$GB/.gitconfig" ]'
ok_if 'global gitignore is linked' '[ -h "$GB/.gitignore_global" ]'
expect 'gitconfig points at the repo' "$DOT_REPO/config/git/gitconfig" \
    "$(readlink "$GB/.gitconfig")"

printf '\n== identity goes to the untracked local file, never the repo ==\n'
GB2="$FIX/gitbox2"
mkdir -p "$GB2"
HOME="$GB2" DOT_BACKUP_ROOT="$GB2/bk" sh "$BOOT" --only git </dev/null >/dev/null 2>&1
# 非交互下不应提示，也不该写身份
expect_lacks 'repo gitconfig contains no email' '@' \
    "$(grep -E '^\s*email' "$DOT_REPO/config/git/gitconfig" 2>/dev/null || true)"
ok_if 'repo gitconfig has no [user] section at all' \
    '! grep -q "^\[user\]" "$DOT_REPO/config/git/gitconfig"'
out=$(HOME="$GB2" DOT_BACKUP_ROOT="$GB2/bk" sh "$BOOT" --only git </dev/null 2>&1)
expect_has 'non-interactive run explains how to set identity later' 'set it later' "$out"

printf '\n== existing gitconfig is backed up, identity recoverable ==\n'
GB3="$FIX/gitbox3"
mkdir -p "$GB3"
printf '[user]\n\tname = Old User\n\temail = old@example.com\n' >"$GB3/.gitconfig"
HOME="$GB3" DOT_BACKUP_ROOT="$GB3/bk" sh "$BOOT" --only git </dev/null >/dev/null 2>&1
backed=$(find "$GB3/bk" -name '.gitconfig' -type f 2>/dev/null | head -n 1)
ok_if 'old gitconfig is in the backup' '[ -n "$backed" ]'
expect_has 'old identity is recoverable' 'old@example.com' "$(cat "$backed" 2>/dev/null)"

printf '\n== the repo gitconfig is usable by git ==\n'
# core.pager 里写了 shell 回退表达式，必须能被 git 正常解析
val=$(HOME="$GB" git config --global --get init.defaultBranch 2>/dev/null)
expect 'git can read the linked config' 'main' "$val"
val=$(HOME="$GB" git config --global --get pull.rebase 2>/dev/null)
expect 'pull.rebase is on' 'true' "$val"

printf '\n== git idempotence ==\n'
before=$(ls -l "$GB/.gitconfig" "$GB/.gitignore_global")
out=$(HOME="$GB" DOT_BACKUP_ROOT="$GB/bk" sh "$BOOT" --only git </dev/null 2>&1)
after=$(ls -l "$GB/.gitconfig" "$GB/.gitignore_global")
expect 'second run changes nothing' "$before" "$after"
expect_has 'links reported as already in place' 'already linked' "$out"

# ------------------------------------------------------------------ zsh 默认 shell
#
# spec 要求三种情形：zsh 缺失时安装、已是默认则跳过 chsh、headless 下不改。
# 用替身 chsh 记录调用 —— 真的改默认 shell 会动到跑测试的这台机器。

printf '\n== default shell handling ==\n'

ZBIN="$FIX/zshbin"
mkdir -p "$ZBIN"
for t in sh printf grep sed cat command mktemp rm mkdir chmod find ls date dirname basename tr cut head env uname id ln readlink cmp mv cp wc od dd sort uniq stty; do
    if p=$(command -v "$t" 2>/dev/null); then ln -sf "$p" "$ZBIN/$t" 2>/dev/null || true; fi
done
# 替身 zsh 与 chsh
printf '#!/bin/sh\nexit 0\n' >"$ZBIN/zsh"
chmod +x "$ZBIN/zsh"
cat >"$ZBIN/chsh" <<'CHSH'
#!/bin/sh
printf 'chsh %s\n' "$*" >>"$DOT_TEST_CHSH_LOG"
exit 0
CHSH
chmod +x "$ZBIN/chsh"

run_zsh_module() {
    : >"$FIX/chsh.log"
    mkdir -p "$FIX/zhome"
    env -i HOME="$FIX/zhome" PATH="$ZBIN" \
        SHELL="${1:-/bin/bash}" \
        DOT_TEST_CHSH_LOG="$FIX/chsh.log" \
        DOT_BACKUP_ROOT="$FIX/zbackup" \
        ${2:+CI=1} \
        sh "$BOOT" --only zsh </dev/null 2>&1
}

# headless（CI=1）下绝不能调 chsh
out=$(run_zsh_module /bin/bash headless)
expect_has 'headless run explains why it skips chsh' 'not changing the default shell' "$out"
expect 'headless run never calls chsh' '' "$(cat "$FIX/chsh.log" 2>/dev/null)"

# 已是 zsh 时跳过，且给出提示
out=$(run_zsh_module /usr/bin/zsh headless)
expect_has 'already-zsh is reported as already in place' 'already the default shell' "$out"
expect 'already-zsh never calls chsh' '' "$(cat "$FIX/chsh.log" 2>/dev/null)"

# zsh 缺失时应尝试安装。用一个没有 zsh 的 PATH。
NOZSH="$FIX/nozsh"
mkdir -p "$NOZSH"
for t in sh printf grep sed cat command mktemp rm mkdir chmod find ls date dirname basename tr cut head env uname id ln readlink cmp mv cp wc od dd sort uniq stty; do
    if p=$(command -v "$t" 2>/dev/null); then ln -sf "$p" "$NOZSH/$t" 2>/dev/null || true; fi
done
: >"$FIX/install.log"
out=$(env -i HOME="$FIX/zhome2" PATH="$NOZSH" CI=1 \
    DOT_PLATFORM_DIR="$FIX/platform" DOT_TEST_LOG="$FIX/install.log" \
    DOT_BACKUP_ROOT="$FIX/zbackup2" \
    sh "$BOOT" --only zsh </dev/null 2>&1)
expect_has 'a missing zsh triggers an install attempt' 'zsh' "$(cat "$FIX/install.log" 2>/dev/null)$out"

printf '\n== the yum path in platform/linux.sh ==\n'
#
# RHEL/CentOS 7 与 Amazon Linux 2 只有 yum。这组直接调 platform 层的两个
# 函数，不经过模块 —— 要验证的就是「DOT_PKG=yum 时包名给对、命令调对」。
#
# 用替身 sudo/yum 把安装变成可观测的记录，不真装东西。

pkgname_under() {
    env DOT_PKG="$1" DOT_LIB_DIR="$DOT_REPO/lib" \
        sh -c ". \"$DOT_REPO/platform/linux.sh\"; dot_platform_pkg_name \"\$1\"" _ "$2" 2>/dev/null
}

# 包名对 dnf 与 yum 必须一致 —— RHEL 族是同一套包名。
# 逐个比对而不是抽查：漏一个的症状是静默走 cargo 编译，不报错。
mismatch=''
for tool in fd bat rg delta eza lazygit starship zoxide atuin gh yq \
    dust procs xh sd tldr duf hyperfine btop htop direnv tmux \
    fzf jq git zsh curl unzip; do
    a=$(pkgname_under dnf "$tool")
    b=$(pkgname_under yum "$tool")
    [ "$a" = "$b" ] || mismatch="$mismatch $tool(dnf=$a,yum=$b)"
done
expect 'every tool maps to the same package name under dnf and yum' '' "$mismatch"

# 抽查两个有实际映射的，确认不是「两边都是空串所以相等」
expect 'fd maps to fd-find under yum' 'fd-find' "$(pkgname_under yum fd)"
expect 'gh maps to github-cli under yum' 'github-cli' "$(pkgname_under yum gh)"
expect 'delta maps to git-delta under yum' 'git-delta' "$(pkgname_under yum delta)"

# 安装命令必须调 yum 而不是 dnf。只有 yum 的机器上调 dnf 会直接失败。
YB="$FIX/yumbox"
mkdir -p "$YB/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/calls.log"\nexit 0\n' "$YB" >"$YB/bin/yum"
printf '#!/bin/sh\nprintf "dnf-was-called %%s\\n" "$*" >>"%s/calls.log"\nexit 0\n' "$YB" >"$YB/bin/dnf"
# 非 root 时 platform 层会走 sudo，替身 sudo 直接转发
printf '#!/bin/sh\nexec "$@"\n' >"$YB/bin/sudo"
chmod +x "$YB/bin/yum" "$YB/bin/dnf" "$YB/bin/sudo"

env DOT_PKG=yum PATH="$YB/bin:$PATH" DOT_LIB_DIR="$DOT_REPO/lib" \
    sh -c ". \"$DOT_REPO/platform/linux.sh\"; dot_platform_pkg_install ripgrep" \
    >/dev/null 2>&1
calls=$(cat "$YB/calls.log" 2>/dev/null || true)
expect_has 'DOT_PKG=yum installs via yum install -y' 'install -y ripgrep' "$calls"
expect_lacks 'DOT_PKG=yum never shells out to dnf' 'dnf-was-called' "$calls"

# 反面：DOT_PKG=dnf 时不该调 yum
: >"$YB/calls.log"
env DOT_PKG=dnf PATH="$YB/bin:$PATH" DOT_LIB_DIR="$DOT_REPO/lib" \
    sh -c ". \"$DOT_REPO/platform/linux.sh\"; dot_platform_pkg_install ripgrep" \
    >/dev/null 2>&1
calls=$(cat "$YB/calls.log" 2>/dev/null || true)
expect_has 'DOT_PKG=dnf still uses dnf' 'dnf-was-called' "$calls"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
