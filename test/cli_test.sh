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
#
# 还得放一个替身 brew：DOT_OS=macos 会让探测认定包管理器是 brew，
# 而 brew 不存在时引导会真的去装 Homebrew —— 在 Linux 容器里那会失败并
# 中断，于是清单一条都没处理（实测 Rocky 9）。macOS 上恰好不会，
# 因为 brew 已经在了。这个用例只想测平台筛选，不该触发包管理器安装。
# 不能用 DOT_BREW_PREFIX 环境变量 —— 探测函数开头会把它清空。
printf '#!/bin/sh\nprintf "/opt/homebrew\\n"\n' >"$FIX/bin/brew"
chmod +x "$FIX/bin/brew"
MANIFEST="everywhere|all|default||all platforms
thisplatform|macos|default||only for the pinned platform
otherplatform|windows|default||not for the pinned platform"
out=$(DOT_OS=macos runcli "$MANIFEST")
expect 'only entries for the current platform install' 'everywhere thisplatform' "$(installed_log)"
expect_has 'skipped entry states the platform' 'not for macos' "$out"
rm -f "$FIX/bin/brew"

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

printf '\n== only essential failures make the module exit non-zero ==\n'
#
# 之前任何默认工具装不上都让模块失败，而紧随的提示却说「这些工具可选、
# shell 会优雅降级」—— 自相矛盾。在包源贫乏的发行版上这个矛盾很致命：
# RHEL/CentOS 7 的仓库里没有 eza/lazygit/gh/yq，引导于是永远非零退出，
# 即使 zsh、git、字体、密钥全都装好了。
mkdir -p "$FIX/cfg/cli"

# default 失败：只告警，退出码 0
printf '%s\n' "alwaysfails|all|default||fails" >"$FIX/cfg/cli/tools.txt"
: >"$FIX/install.log"
out=$(DOT_CONFIG_DIR="$FIX/cfg" DOT_PLATFORM_DIR="$FIX/platform" \
    DOT_TEST_LOG="$FIX/install.log" PATH="$FIX/bin:/usr/bin:/bin" \
    sh "$BOOT" --only modern-cli 2>&1)
rc=$?
expect 'a non-essential failure still exits 0' 0 "$rc"
expect_has 'the failed tool is still named' 'alwaysfails' "$out"
expect_has 'it says the tool was not essential' 'none of these are essential' "$out"

# essential 失败：模块失败，退出码非零
printf '%s\n' "alwaysfails|all|essential||fails" >"$FIX/cfg/cli/tools.txt"
: >"$FIX/install.log"
out=$(DOT_CONFIG_DIR="$FIX/cfg" DOT_PLATFORM_DIR="$FIX/platform" \
    DOT_TEST_LOG="$FIX/install.log" PATH="$FIX/bin:/usr/bin:/bin" \
    sh "$BOOT" --only modern-cli 2>&1)
rc=$?
expect 'an essential failure exits non-zero' 1 "$rc"
expect_has 'the essential failure is called out as such' 'essential:' "$out"

# 打错的标签必须报错而不是默默不装 —— 静默漂移最难发现
printf '%s\n' "typo|all|defualt||typo in tag" >"$FIX/cfg/cli/tools.txt"
out=$(DOT_CONFIG_DIR="$FIX/cfg" DOT_PLATFORM_DIR="$FIX/platform" \
    DOT_TEST_LOG="$FIX/install.log" PATH="$FIX/bin:/usr/bin:/bin" \
    sh "$BOOT" --only modern-cli 2>&1)
rc=$?
expect 'a misspelled tag exits non-zero' 1 "$rc"
expect_has 'the misspelled tag is named' 'defualt' "$out"

printf '\n== not in the repos: falls back ==\n'
# norepo 的包名映射返回空，应直接走回退链而不调用包管理器
MANIFEST="norepo|all|default|cargo:norepo-crate|not in repos"
out=$(runcli "$MANIFEST")
expect 'package manager is not called for it' '' "$(installed_log)"
expect_has 'fallback is attempted or reported' 'norepo' "$out"

# ------------------------------------------------------------------ github 回退
#
# 预编译二进制回退。这组用例一次网络都不发：替身 curl/wget 只记录被调用
# 的事实，够用来断言「该调的时候调了、不该调的时候没调」。
# 真实的下载-解包-落地在 test/release_test.sh 里用本地 fixture server 验。

printf '\n== the github fallback ==\n'

NETLOG="$FIX/net.log"
# 替身 curl/wget：记录调用后失败。失败是有意的 —— 这组只关心「有没有
# 发起网络请求」，成功路径由 release_test.sh 覆盖。
for _n in curl wget; do
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nexit 1\n' "$NETLOG" >"$FIX/bin/$_n"
    chmod +x "$FIX/bin/$_n"
done

net_called() { [ -s "$NETLOG" ] && printf 'yes' || printf ''; }

# 最重要的一条：包管理器能装成时绝不能碰网络。
# 这是「github 回退不会抢走仓库里本来有的包」的回归保护。
: >"$NETLOG"
MANIFEST="fzf|all|default|github:junegunn/fzf|has a package and a fallback"
out=$(runcli "$MANIFEST")
expect 'the package manager installs it' 'fzf' "$(installed_log)"
expect 'no network when the package manager succeeds' '' "$(net_called)"

# 包管理器没有这个包时才轮到 github
: >"$NETLOG"
MANIFEST="norepo|all|default|github:foo/norepo|not in repos"
out=$(runcli "$MANIFEST")
expect_has 'a missing recipe says it was not attempted' 'not attempted' "$out"
# 「未尝试」不能被说成「已尝试」—— spec 明确要求区分
expect_lacks 'a missing recipe does not claim it tried' 'tried github' "$out"

# dry-run 一次网络都不能发。放这条是因为计划消息很容易被后人「优化」成
# 真去查一下最新版本 —— 那就违反了 dry-run 零副作用的契约。
: >"$NETLOG"
MANIFEST="fzf|all|default|github:junegunn/fzf|dry run"
out=$(runcli "$MANIFEST" --dry-run)
expect 'dry-run makes no network calls' '' "$(net_called)"
expect_has 'dry-run still prints a plan' 'would install' "$out"

rm -f "$FIX/bin/curl" "$FIX/bin/wget"

# 既没 curl 也没 wget 时要说清缺什么，而不是含糊失败
MANIFEST="norepo|all|default|github:junegunn/fzf|no downloader"
out=$(env PATH="$FIX/nodl:/usr/bin:/bin" sh -c '
    mkdir -p "$1/nodl"
    for t in sh printf grep sed cat mktemp rm mkdir chmod find ls date dirname \
        basename tr cut head env uname id ln readlink mv cp wc od dd sort uniq \
        stty tar gzip; do
        p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$1/nodl/$t" 2>/dev/null
    done
    # 替身包管理器。这条用例测的是「没有下载器」，不该依赖真实包管理器 ——
    # 而 PATH 被收窄成只有 $nodl 后，探测找不到任何包管理器就会直接报
    # "no supported package manager found" 并退出，断言永远拿不到该看的输出。
    # 之前这里是给真实的 apt-get 做符号链接，于是只在 Debian 族成立：
    # RHEL 上没有 apt-get，链接建不起来，这条用例就红（CI 的 Rocky 9 job
    # 实测如此）。同 $ZBIN 与 $NOZSH 两处已有的替身，写死一个假的。
    printf "#!/bin/sh\nexit 0\n" >"$1/nodl/apt-get"
    chmod +x "$1/nodl/apt-get"
    mkdir -p "$1/cfg/cli"
    printf "%s\n" "$2" >"$1/cfg/cli/tools.txt"
    : >"$1/install.log"
    DOT_CONFIG_DIR="$1/cfg" DOT_PLATFORM_DIR="$1/platform" \
        DOT_TEST_LOG="$1/install.log" PATH="$1/nodl" \
        sh "$3" --only modern-cli 2>&1
' _ "$FIX" "$MANIFEST" "$BOOT")
expect_has 'no curl/wget is reported as not attempted' 'not attempted' "$out"

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
        essential | default | optional) ;;
        *) bad="$bad $n(tag=$t)" ;;
    esac
    # 每个工具都该有说明 —— 半年后回头看清单要能想起为什么装它
    [ -n "$d" ] || bad="$bad $n(no-desc)"
done <"$REAL"
expect 'every real entry has platforms, a valid tag and a description' '' "$bad"

# atuin 必须是 optional —— 它会接管 Ctrl-R 并改变历史行为
atuin_tag=$(grep '^atuin|' "$REAL" | cut -d'|' -f3)
expect 'atuin stays optional' 'optional' "$atuin_tag"

# 默认安装的工具应该正好是设计里确定的 14 个：12 个现代 CLI 工具，加上
# direnv 与 tmux —— 这两个是 zshrc.d 的片段已经引用的，不装它们
# 对应功能会静默失效。改这个数字前请确认新增的确实该默认装。
#
# essential 与 default 都是默认安装，区别只在装不上时是否致命，
# 所以这里两者都数。
installed_by_default=$(grep -vE '^\s*#|^\s*$' "$REAL" | cut -d'|' -f3 |
    grep -cE '^(essential|default)$')
expect 'the default set has 14 tools' '14' "$(printf '%s' "$installed_by_default" | tr -d ' ')"

# starship 必须是 essential —— 它是 prompt，缺了外观立刻退化，
# 而且它是 zsh 与 PowerShell 共用同一份配置的那个点。
starship_tag=$(grep '^starship|' "$REAL" | cut -d'|' -f3)
expect 'starship is essential' 'essential' "$starship_tag"

# 配置片段引用了却没人安装的工具是最难发现的一类问题 —— 装不上会报错，
# 而「压根没进清单」只是功能静默消失。这里把两处钉在一起。
for referenced in direnv tmux; do
    ok_if "$referenced is in the manifest (referenced by zshrc.d)" \
        "grep -q '^$referenced|' '$REAL'"
done

# ---------------------------------------------------------------- github 配方
#
# 清单里的 github:owner/repo 与 lib/release.sh 的配方表是两处会漂移的地方。
# 双向钉住，照 test/lint.sh 对 dnf/yum 包名的做法。

printf '\n== the manifest and the recipe table agree ==\n'

# spec 里有空格会被 word-split 成两条垃圾 spec，两条都落到「unknown
# fallback spec」—— 那不致命，于是工具静默地不装。所以形状要严格。
#
# 只看真实条目的第 4 列：注释里也会出现 "github:"（解释这个语法本身），
# 拿整个文件 grep 会把说明文字当成 spec。
badshape=''
while IFS='|' read -r n _ _ fb _; do
    case $n in '' | \#*) continue ;; esac
    for tok in $fb; do
        case $tok in
            github:*)
                case $tok in
                    github:[A-Za-z0-9_.-]*/[A-Za-z0-9_.-]*) ;;
                    *) badshape="$badshape $tok" ;;
                esac
                ;;
        esac
    done
done <"$REAL"
expect 'every github: spec is owner/repo with no spaces' '' "$badshape"

# 清单声明了 github: 的工具，配方表必须认得 —— 否则运行时才发现「没有配方」
missing=''
grep -E '\|github:' "$REAL" | cut -d'|' -f1 >"$FIX/ghtools"
while read -r tool; do
    [ -n "$tool" ] || continue
    for combo in linux/x86_64 linux/arm64 macos/x86_64 macos/arm64; do
        got=$(env DOT_LIB_DIR="$DOT_REPO/lib" \
            DOT_OS="${combo%%/*}" DOT_ARCH="${combo#*/}" \
            sh -c ". \"$DOT_REPO/lib/release.sh\"; _dot_release_recipe \"\$1\" && printf '%s' \"\$_dot_rr_asset\"" \
            _ "$tool" 2>/dev/null)
        [ -n "$got" ] || missing="$missing $tool($combo)"
    done
done <"$FIX/ghtools"
expect 'every github: tool has an asset for all four os/arch combos' '' "$missing"

# 反向：配方表里的工具也该真的在清单里声明了 github:，否则是死代码
orphan=''
for tool in fzf lazygit gh jq yq direnv; do
    grep -qE "^$tool\|.*\|github:" "$REAL" || orphan="$orphan $tool"
done
expect 'every recipe in the table is wired in the manifest' '' "$orphan"

# 这 6 个的回退列不能再被清空 —— 那正是本次改动要修的问题
for wired in fzf lazygit gh jq yq direnv; do
    fb=$(grep "^$wired|" "$REAL" | cut -d'|' -f4)
    expect_has "$wired still declares a fallback" 'github:' "$fb"
done

# tmux/htop 的空回退是刻意的结论，不是遗漏。空着 + 注释在位，两者都钉住，
# 否则「查过没有」与「忘了填」在半年后无法区分。
for blank in tmux htop; do
    fb=$(grep "^$blank|" "$REAL" | cut -d'|' -f4)
    expect "$blank deliberately has no fallback" '' "$fb"
done
ok_if 'the manifest explains why tmux/htop have none' \
    "grep -q '从不发布预编译二进制' '$REAL'"

# 预编译二进制必须排在源码编译之前（spec：预编译优先）。
# 推广原先只针对 starship 的那条断言 —— 任何同时声明两者的工具都适用。
badorder=''
while IFS='|' read -r n _ _ fb _; do
    case $n in '' | \#*) continue ;; esac
    case $fb in
        *cargo:*)
            case $fb in
                # cargo 之前还有别的方式时，那些必须先出现
                *github:*cargo:* | *script:*cargo:*) ;;
                *cargo:*github:* | *cargo:*script:*) badorder="$badorder $n" ;;
                *) ;;
            esac
            ;;
    esac
done <"$REAL"
expect 'prebuilt routes come before cargo everywhere' '' "$badorder"

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
for t in sh printf grep sed cat command mktemp rm mkdir chmod find ls date dirname basename tr cut head env uname id ln readlink mv cp wc od dd sort uniq stty; do
    if p=$(command -v "$t" 2>/dev/null); then ln -sf "$p" "$ZBIN/$t" 2>/dev/null || true; fi
done
# 替身 zsh 与 chsh
printf '#!/bin/sh\nexit 0\n' >"$ZBIN/zsh"
chmod +x "$ZBIN/zsh"
# 替身包管理器。这组用例测的是 chsh 行为，不该依赖真实包管理器 ——
# 而 PATH 被收窄成只有 $ZBIN 后，Linux 上的探测找不到任何包管理器就会
# 直接报 "no supported package manager found" 并退出，三条断言全红。
# macOS 上恰好不会：那里 DOT_PKG 直接设为 brew 且只标记 missing、不退出。
# 实测 Rocky 9 容器就是这么红的，而 debian 容器碰巧过了。
printf '#!/bin/sh\nexit 0\n' >"$ZBIN/apt-get"
chmod +x "$ZBIN/apt-get"
# 替身 chsh 记录调用后按 DOT_TEST_CHSH_RC 退出（默认 0）。
# 可控的退出码是为了覆盖「chsh 失败」——那在真实环境里很常见：容器里 PAM
# 要密码，LDAP/SSSD 管的账户根本不允许改。
cat >"$ZBIN/chsh" <<'CHSH'
#!/bin/sh
printf 'chsh %s\n' "$*" >>"$DOT_TEST_CHSH_LOG"
exit "${DOT_TEST_CHSH_RC:-0}"
CHSH
chmod +x "$ZBIN/chsh"

run_zsh_module() {
    : >"$FIX/chsh.log"
    mkdir -p "$FIX/zhome"
    # $3 起是额外的环境变量赋值（如 DOT_SET_DEFAULT_SHELL=1）。
    # DOT_CONTAINER_PROBE_FILES 指向不存在的路径：否则在容器里跑测试时
    # /.dockerenv 恒存在，「非 headless」那几条用例永远进不到该走的分支。
    _zm_shell=${1:-/bin/bash}
    _zm_ci=${2:-}
    # 参数可能只给了 1 个（set -u 下 $2 会 unbound，所以上面用 ${2:-}）。
    # shift 的个数也要跟着算，否则 shift 2 在只有 1 个参数时报错。
    if [ $# -gt 2 ]; then
        shift 2
    else
        shift $#
    fi
    env -i HOME="$FIX/zhome" PATH="$ZBIN" \
        SHELL="$_zm_shell" \
        DOT_TEST_CHSH_LOG="$FIX/chsh.log" \
        DOT_BACKUP_ROOT="$FIX/zbackup" \
        DOT_CONTAINER_PROBE_FILES=/nonexistent-container-marker \
        ${_zm_ci:+CI=1} \
        "$@" \
        sh "$BOOT" --only zsh </dev/null 2>&1
}

# 无人值守（CI=1，且 run_zsh_module 已 </dev/null）下绝不能调 chsh
out=$(run_zsh_module /bin/bash headless)
expect_has 'unattended run explains why it skips chsh' 'not changing the default shell' "$out"
expect 'unattended run never calls chsh' '' "$(cat "$FIX/chsh.log" 2>/dev/null)"

# 已是 zsh 时跳过，且给出提示
out=$(run_zsh_module /usr/bin/zsh headless)
expect_has 'already-zsh is reported as already in place' 'already the default shell' "$out"
expect 'already-zsh never calls chsh' '' "$(cat "$FIX/chsh.log" 2>/dev/null)"

# ---------------------------------------------------------------- 无 tty 的确认
#
# 这几条针对一个真实的 bug：确认逻辑无条件 `read`，而 stdin 不是 tty 时
# read 立刻拿到 EOF，空答案落进 [y/N] 的默认分支 —— 于是屏幕上先印出
# 问题、紧接着自己回答「不改」。用户看到一个从没等他输入的提问，
# 结论是「安装没把 zsh 设成默认 shell」。
# `curl … | sh` 与 `./bootstrap.sh </dev/null` 都会走到这条路上。
#
# 注意这里的 run_zsh_module 已经 </dev/null，正是要测的情形。

# 非 headless、无 tty：不能假装问过
out=$(run_zsh_module /bin/bash)
rc=$?
expect_has 'no-tty run says it could not ask' 'no terminal available to ask' "$out"
expect 'no-tty run never calls chsh' '' "$(cat "$FIX/chsh.log" 2>/dev/null)"
# 关键断言：不能印出一个它根本没能力等待回答的问题
expect_lacks 'no-tty run does not print an unanswerable question' '\[y/N\]' "$out"

# 而且必须活着走完 —— 这条防的是探测本身把进程杀掉。
#
# 探测控制终端曾写成 `{ : </dev/tty; } 2>/dev/null`：`:` 是 special builtin，
# POSIX 规定它的重定向失败时非交互式 shell 必须直接退出，而 `{ }` 不隔离
# 那个退出。于是在 dash（Debian/Ubuntu 的 /bin/sh）下整个 bootstrap.sh 死在
# 这一行，输出只剩一句没有原因的 "zsh failed"，omz 再被依赖级联跳过 ——
# 用户看到的是「Linux 上补全和默认 shell 都没装成」。
# macOS 的 /bin/sh 是 bash 3.2、不遵守这条规定，所以本机永远复现不出来。
# test/lint.sh 的可移植性小节静态地挡住这个形态，这里动态地兜住后果。
expect 'no-tty run still exits 0 (the tty probe must not kill the script)' 0 "$rc"
expect_has 'no-tty run reaches the summary' 'succeeded' "$out"
expect_lacks 'no-tty run does not report a bare unexplained failure' 'zsh failed' "$out"

# 显式开关：无人值守也能改（容器镜像构建、Ansible 需要这条路）
out=$(run_zsh_module /bin/bash '' DOT_SET_DEFAULT_SHELL=1)
expect_has 'the opt-in explains itself' 'DOT_SET_DEFAULT_SHELL=1' "$out"
expect_has 'the opt-in calls chsh' 'chsh -s' "$(cat "$FIX/chsh.log" 2>/dev/null)"

# 开关必须能越过无人值守判定 —— 否则容器/CI 里永远设不了默认 shell
out=$(run_zsh_module /bin/bash headless DOT_SET_DEFAULT_SHELL=1)
expect_has 'the opt-in overrides the unattended check' 'chsh -s' "$(cat "$FIX/chsh.log" 2>/dev/null)"

# 但无人值守下没有开关时仍然绝不能改
out=$(run_zsh_module /bin/bash headless)
expect 'unattended without the opt-in still never calls chsh' '' "$(cat "$FIX/chsh.log" 2>/dev/null)"
expect_has 'the skip mentions the opt-in' 'DOT_SET_DEFAULT_SHELL=1' "$out"

# ---------------------------------------------------------------- SSH 仍然要问
#
# lib/detect.sh 把任何 SSH_* 都判成 headless，可 SSH 进一台新机器做初始配置
# 恰恰是最想改默认 shell 的场合，而且那里有活人守着终端。若以 DOT_HEADLESS
# 为判据，Linux 服务器上默认 shell 永远不会被改 —— 除非用户事先知道
# DOT_SET_DEFAULT_SHELL=1，而那是个只有读过源码才找得到的开关。
#
# 判据因此是「问得到人吗」而不是「是不是 headless」。这里只能验证「SSH 不再
# 单独构成跳过的理由」：测试进程没有 tty，所以仍会走到「问不到人」那条路，
# 但措辞必须是「没法问」而不是「headless 所以不改」。
out=$(run_zsh_module /bin/bash '' SSH_CONNECTION='10.0.0.1 22 10.0.0.2 22')
expect_has 'SSH is not by itself a reason to skip' 'no terminal available to ask' "$out"
expect_lacks 'SSH does not report a headless skip' 'headless environment' "$out"
expect 'SSH without a terminal still never calls chsh' '' "$(cat "$FIX/chsh.log" 2>/dev/null)"

# ---------------------------------------------------------------- chsh 失败
#
# chsh 失败不能让模块失败：到那一步 zsh 已装好、配置已链接，唯一没做到的是
# 换默认 shell。而 omz 声明了 MODULE_REQUIRES="zsh"，模块失败会让它被依赖
# 级联跳过 —— 用一个失败的 chsh 换掉整套插件与联想补全，完全不成比例。
# 真实环境里 chsh 失败很常见：容器里 PAM 要密码，LDAP/SSSD 账户不允许改。
out=$(run_zsh_module /bin/bash '' DOT_SET_DEFAULT_SHELL=1 DOT_TEST_CHSH_RC=1)
rc=$?
expect 'a failing chsh does not fail the module' 0 "$rc"
expect_has 'the chsh failure is reported' 'chsh failed' "$out"
expect_has 'it says how to finish the job by hand' "chsh -s" "$out"
expect_has 'it says the rest of the module is in place' 'everything else in this module is in place' "$out"

# zsh 缺失时应尝试安装。用一个没有 zsh 的 PATH。
NOZSH="$FIX/nozsh"
mkdir -p "$NOZSH"
for t in sh printf grep sed cat command mktemp rm mkdir chmod find ls date dirname basename tr cut head env uname id ln readlink mv cp wc od dd sort uniq stty; do
    if p=$(command -v "$t" 2>/dev/null); then ln -sf "$p" "$NOZSH/$t" 2>/dev/null || true; fi
done
# 替身包管理器，理由同上面的 $ZBIN —— PATH 只有替身目录时，
# Linux 上找不到包管理器会直接退出，这条断言就永远拿不到输出。
printf '#!/bin/sh\nexit 0\n' >"$NOZSH/apt-get"
chmod +x "$NOZSH/apt-get"
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

# 以下包名全部在真实容器里查证过（Rocky 9 + EPEL 9、Fedora、Alpine），
# 不是按命名习惯推测的。上一版这里三条都是错的：
#   gh     -> 写成 github-cli，而 Fedora 与 Rocky 都叫 gh，
#             那个名字两边都不存在，dnf 报 No match 后走回退、
#             而 gh 没声明回退，直接失败
#   yq     -> 返回空串走回退，可 EPEL 明明有，且 yq 也没声明回退
#   direnv -> 当成各发行版都同名收录，但 RHEL 族 base 与 EPEL 都没有
expect 'gh is named gh on RHEL-family, not github-cli' 'gh' "$(pkgname_under dnf gh)"
expect 'gh is github-cli on Alpine' 'github-cli' "$(pkgname_under apk gh)"
expect 'yq comes from EPEL on RHEL-family' 'yq' "$(pkgname_under yum yq)"
expect 'direnv is absent from RHEL-family repos' '' "$(pkgname_under yum direnv)"
expect 'direnv is available elsewhere' 'direnv' "$(pkgname_under apt direnv)"

# 抽查两个有实际映射的，确认不是「两边都是空串所以相等」
expect 'fd maps to fd-find under yum' 'fd-find' "$(pkgname_under yum fd)"
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

printf '\n== EPEL is enabled on RHEL-family before installing ==\n'
#
# RHEL/CentOS 的 base 仓库里没有 ripgrep/fd-find/bat/zoxide/git-delta/
# direnv/duf —— 它们都在 EPEL 里。不启用 EPEL 的话默认集 14 个有 7 个
# 从仓库装不到，全部退化成源码编译（CentOS 7 上是几十分钟且很可能编不过）。
#
# 这组是变异测试逼出来的：EPEL 逻辑写完后把它整段删掉，测试竟然全过 ——
# 这次改动最重要的部分毫无断言覆盖。
EB="$FIX/epelbox"
mkdir -p "$EB/bin"
cat >"$EB/bin/yum" <<'YUMSTUB'
#!/bin/sh
echo "yum $*" >>"$EPEL_LOG"
case "$1" in
    repolist)
        [ -f "$EPEL_MARK" ] && { echo '!epel/x86_64 EPEL'; exit 0; }
        echo 'base/7/x86_64 CentOS-7 - Base'
        exit 0
        ;;
    install)
        [ "$3" = epel-release ] && { touch "$EPEL_MARK"; exit 0; }
        case $3 in
            ripgrep | fd-find | bat | zoxide | git-delta | direnv | duf)
                [ -f "$EPEL_MARK" ] && exit 0
                exit 1
                ;;
            git | zsh | jq | fzf | tmux | curl | unzip) exit 0 ;;
        esac
        exit 1
        ;;
esac
exit 1
YUMSTUB
cp "$EB/bin/yum" "$EB/bin/dnf"
printf '#!/bin/sh\nexec "$@"\n' >"$EB/bin/sudo"
chmod +x "$EB/bin/yum" "$EB/bin/dnf" "$EB/bin/sudo"

# 每次都用干净的 log 与 mark 跑一次安装，回显调用记录
run_epel() {
    rm -f "$EB/mark"
    : >"$EB/log"
    env EPEL_LOG="$EB/log" EPEL_MARK="$EB/mark" \
        DOT_PKG="$1" DOT_DISTRO="$2" DOT_LIB_DIR="$DOT_REPO/lib" \
        PATH="$EB/bin:/usr/bin:/bin" \
        sh -c ". \"$DOT_REPO/platform/linux.sh\"; dot_platform_pkg_install ripgrep" \
        >/dev/null 2>&1
    cat "$EB/log" 2>/dev/null || true
}

log=$(run_epel yum rhel)
expect_has 'yum on rhel installs epel-release first' 'install -y epel-release' "$log"
expect_has 'the real package is installed after EPEL' 'install -y ripgrep' "$log"

log=$(run_epel dnf rhel)
expect_has 'dnf on rhel also enables EPEL' 'epel-release' "$log"

# Fedora 自带这些包，不该去装 EPEL
log=$(run_epel dnf fedora)
expect_lacks 'fedora does not need EPEL' 'epel-release' "$log"

# 已启用时不重复装
: >"$EB/log"
touch "$EB/mark"
env EPEL_LOG="$EB/log" EPEL_MARK="$EB/mark" \
    DOT_PKG=yum DOT_DISTRO=rhel DOT_LIB_DIR="$DOT_REPO/lib" \
    PATH="$EB/bin:/usr/bin:/bin" \
    sh -c ". \"$DOT_REPO/platform/linux.sh\"; dot_platform_pkg_install ripgrep" \
    >/dev/null 2>&1
expect_lacks 'an already-enabled EPEL is not reinstalled' 'epel-release' \
    "$(cat "$EB/log" 2>/dev/null)"

# DOT_NO_EPEL=1 必须真的关掉（离线环境、或公司镜像已自带这些包）
rm -f "$EB/mark"
: >"$EB/log"
env EPEL_LOG="$EB/log" EPEL_MARK="$EB/mark" DOT_NO_EPEL=1 \
    DOT_PKG=yum DOT_DISTRO=rhel DOT_LIB_DIR="$DOT_REPO/lib" \
    PATH="$EB/bin:/usr/bin:/bin" \
    sh -c ". \"$DOT_REPO/platform/linux.sh\"; dot_platform_pkg_install ripgrep" \
    >/dev/null 2>&1
expect_lacks 'DOT_NO_EPEL=1 skips EPEL entirely' 'epel-release' \
    "$(cat "$EB/log" 2>/dev/null)"

# dry-run 必须预告 EPEL，且在此之前不调用包管理器哪怕一次。
#
# 这条是手工测出来的 bug 变成的断言：最初 repolist 那个「已启用吗」的查询
# 排在 dry-run 判断之前，于是 --dry-run 下包管理器仍被调用了一次。
# repolist 虽然只读，但它读元数据缓存、可能触发网络，而 dry-run 的契约
# 是零调用。顺带：dry-run 分支原本写在平台层的安装函数里，而 pkg.sh 的
# dry-run 在更早就短路返回了 —— 那段代码根本不可达，等于没写。
rm -f "$EB/mark"
: >"$EB/log"
dry_out=$(env EPEL_LOG="$EB/log" EPEL_MARK="$EB/mark" DOT_DRY_RUN=1 \
    DOT_PKG=yum DOT_DISTRO=rhel DOT_LIB_DIR="$DOT_REPO/lib" \
    PATH="$EB/bin:/usr/bin:/bin" \
    sh -c ". \"$DOT_REPO/platform/linux.sh\"; dot_platform_prepare_repos" 2>&1)
expect_has 'dry-run previews the EPEL change' 'would enable EPEL' "$dry_out"
expect 'dry-run calls the package manager zero times' '' \
    "$(cat "$EB/log" 2>/dev/null)"

# 走完整引导也要满足同一条契约（上面测的是平台层函数，这里测端到端）。
#
# 注意用 DOT_DISTRO_OVERRIDE 而不是 DOT_DISTRO —— 端到端会跑 dot_detect，
# 它按 os-release 重新探测并覆盖 DOT_DISTRO，于是直接传 DOT_DISTRO=rhel
# 会变成 unknown、EPEL 分支被跳过（第一次就是这么写错的）。
# 平台层用例不跑 dot_detect，所以那里传 DOT_DISTRO 是有效的。
: >"$EB/log"
rm -f "$EB/mark"
mkdir -p "$EB/cfg/cli" "$EB/home"
printf '%s\n' 'ripgrep|all|default||test' >"$EB/cfg/cli/tools.txt"
boot_dry=$(env EPEL_LOG="$EB/log" EPEL_MARK="$EB/mark" \
    DOT_OS=linux DOT_DISTRO_OVERRIDE=rhel DOT_PKG_OVERRIDE=yum \
    DOT_CONFIG_DIR="$EB/cfg" HOME="$EB/home" \
    PATH="$EB/bin:/usr/bin:/bin" \
    sh "$BOOT" --dry-run --only modern-cli 2>&1)
expect 'a dry-run bootstrap never invokes the package manager' '' \
    "$(cat "$EB/log" 2>/dev/null)"
# 也必须真的把 EPEL 计划打出来 —— 否则「零调用」可以靠压根不走这段来满足，
# 而那样用户就看不到这个会改系统仓库的动作了。
expect_has 'a dry-run bootstrap still previews the EPEL change' \
    'would enable EPEL' "$boot_dry"

printf '\n== starship has a route that does not require compiling ==\n'
# starship 是 essential，而它在任何 RHEL 仓库里都没有。只声明 cargo 回退
# 会让 CentOS 7 那种机器要么装 600MB 工具链现场编译、要么引导直接失败。
# 官方 install.sh 拉的是预编译二进制，所以必须排在 cargo 之前。
starship_fb=$(grep '^starship|' "$REAL" | cut -d'|' -f4)
expect_has 'starship declares the official script fallback' 'script:' "$starship_fb"
case $starship_fb in
    script:*cargo:*)
        _pass=$((_pass + 1))
        printf 'ok   the script fallback comes before cargo\n'
        ;;
    *)
        _fail=$((_fail + 1))
        printf 'FAIL script fallback must come before cargo (got: %s)\n' "$starship_fb"
        ;;
esac

printf '\n== tools installed outside PATH are called out ==\n'
#
# 官方脚本把二进制装到 ~/.local/bin。引导进程对 PATH 的修改不会传给用户
# 当前的 shell，所以装完立刻 `command -v starship` 会找不到 —— 用户会以为
# 装失败了。新 shell 没问题（10-path.zsh 里有 ~/.local/bin），
# 但必须说清楚。CI 上就是这条差别让容器 job 红了一次。
SB="$FIX/scriptbox"
mkdir -p "$SB/bin" "$SB/home" "$SB/cfg/cli"
cp -r "$DOT_REPO/config/"* "$SB/cfg/" 2>/dev/null || true
printf '%s\n' \
    'starship|all|essential|script:https://example.invalid/install.sh|prompt' \
    >"$SB/cfg/cli/tools.txt"
printf '#!/bin/sh\nexit 1\n' >"$SB/bin/apt-get"
printf '#!/bin/sh\nexec "$@"\n' >"$SB/bin/sudo"
# 替身 curl：回显一段把二进制写进 --bin-dir 的脚本
cat >"$SB/bin/curl" <<'CURLSTUB'
#!/bin/sh
for a in "$@"; do
    case $a in
        *install.sh*)
            printf '%s\n' 'd=$HOME/.local/bin; mkdir -p "$d"; printf "#!/bin/sh\nexit 0\n" > "$d/starship"; chmod +x "$d/starship"'
            exit 0
            ;;
    esac
done
exit 1
CURLSTUB
chmod +x "$SB/bin/apt-get" "$SB/bin/sudo" "$SB/bin/curl"

sb_out=$(env DOT_OS=linux DOT_PKG_OVERRIDE=apt DOT_DISTRO_OVERRIDE=debian \
    DOT_CONFIG_DIR="$SB/cfg" HOME="$SB/home" DOT_NO_RUSTUP=1 \
    PATH="$SB/bin:/usr/bin:/bin" \
    sh "$BOOT" --only modern-cli 2>&1)
ok_if 'the script fallback puts the binary in ~/.local/bin' \
    "[ -x '$SB/home/.local/bin/starship' ]"
expect_has 'the run says a new shell is needed for PATH' 'open a new shell' "$sb_out"
expect_has 'the run names the directory it used' '.local/bin' "$sb_out"

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
