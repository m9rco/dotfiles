#!/usr/bin/env sh
#
# lib/secrets.sh 与 modules/secrets 的断言测试。
#
# 重点验证两件事：
#   1. 凭据的值绝不出现在日志、错误信息或 dry-run 输出里（本仓库是公开的）
#   2. 读不到时明确失败，不用空值冒充成功
#
# 全部在沙箱 HOME 里跑，不碰真实 keychain。
#
#   sh test/secrets_test.sh
#   dash test/secrets_test.sh
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BOOT="$DOT_REPO/bootstrap.sh"
SECRET_BIN="$DOT_REPO/bin/dot-secret"

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
        printf 'FAIL %s\n       output must NOT contain: %s\n' "$1" "$2"
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

# 在沙箱里调用 lib/secrets.sh 的函数。
# DOT_OS 设成一个没有密钥库实现的值，好让测试只走「环境变量 / 本地文件」
# 这两条可控路径 —— 真实 keychain 不该被测试写入。
sec() {
    env -i \
        HOME="$FIX/home" \
        PATH="$PATH" \
        DOT_LIB_DIR="$DOT_REPO/lib" \
        DOT_OS="${DOT_TEST_OS:-nosuchos}" \
        DOT_ENV_LOCAL="$FIX/home/.config/dotfiles/env.local" \
        "$@"
}

mkdir -p "$FIX/home/.config/dotfiles"

# 一个足够像真凭据的值，用来验证它不会被打印出来
SECRET_VALUE='sk-verySecretValueThatMustNeverBeLogged1234567890'

# ------------------------------------------------------------------ 读取来源

printf '== reads from the environment ==\n'
out=$(sec MY_KEY="$SECRET_VALUE" sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get MY_KEY' 2>/dev/null)
expect 'value comes back from the env var' "$SECRET_VALUE" "$out"

printf '\n== reads from the local env file ==\n'
printf 'FILE_KEY=%s\n' "$SECRET_VALUE" >"$FIX/home/.config/dotfiles/env.local"
chmod 600 "$FIX/home/.config/dotfiles/env.local"
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get FILE_KEY' 2>/dev/null)
expect 'value comes back from the file' "$SECRET_VALUE" "$out"

printf '\n== quoted values are unquoted ==\n'
printf 'Q1="%s"\nQ2='\''%s'\''\n' "$SECRET_VALUE" "$SECRET_VALUE" >"$FIX/home/.config/dotfiles/env.local"
chmod 600 "$FIX/home/.config/dotfiles/env.local"
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get Q1' 2>/dev/null)
expect 'double-quoted value is stripped' "$SECRET_VALUE" "$out"
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get Q2' 2>/dev/null)
expect 'single-quoted value is stripped' "$SECRET_VALUE" "$out"

printf '\n== the env file is NOT sourced (no code execution) ==\n'
# 如果实现用 source 读文件，这行会执行并留下痕迹
printf 'EVIL=x\n$(touch %s/pwned)\n' "$FIX" >"$FIX/home/.config/dotfiles/env.local"
chmod 600 "$FIX/home/.config/dotfiles/env.local"
sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get EVIL' >/dev/null 2>&1
ok_if 'file contents are parsed, not executed' '[ ! -e "$FIX/pwned" ]'

# ------------------------------------------------------------------ 权限

printf '\n== refuses to read a world-readable secret file ==\n'
printf 'PERM_KEY=%s\n' "$SECRET_VALUE" >"$FIX/home/.config/dotfiles/env.local"
chmod 644 "$FIX/home/.config/dotfiles/env.local"
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get PERM_KEY' 2>&1)
expect_has 'unsafe permissions are reported' 'unsafe permissions' "$out"
expect_lacks 'the value is not printed despite the error' "$SECRET_VALUE" "$out"
rc=$(
    sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get PERM_KEY' >/dev/null 2>&1
    printf '%s' "$?"
)
expect 'unsafe permissions make it fail' 1 "$rc"

printf '\n== a 600 file is accepted ==\n'
chmod 600 "$FIX/home/.config/dotfiles/env.local"
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get PERM_KEY' 2>/dev/null)
expect '600 is readable' "$SECRET_VALUE" "$out"

# ------------------------------------------------------------------ 缺失

printf '\n== a missing secret fails loudly, never silently ==\n'
: >"$FIX/home/.config/dotfiles/env.local"
chmod 600 "$FIX/home/.config/dotfiles/env.local"
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get NO_SUCH_KEY' 2>&1)
rc=$(
    sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get NO_SUCH_KEY' >/dev/null 2>&1
    printf '%s' "$?"
)
expect 'missing secret returns non-zero' 1 "$rc"
expect_has 'the name is reported' 'NO_SUCH_KEY' "$out"
expect_has 'the searched sources are listed' 'looked in' "$out"
stdout_only=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get NO_SUCH_KEY' 2>/dev/null)
expect 'nothing is written to stdout on failure' '' "$stdout_only"

printf '\n== dot_secret_has reflects availability ==\n'
rc=$(
    sec HAVE_IT=x sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_has HAVE_IT' >/dev/null 2>&1
    printf '%s' "$?"
)
expect 'present secret -> 0' 0 "$rc"
rc=$(
    sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_has NOPE' >/dev/null 2>&1
    printf '%s' "$?"
)
expect 'absent secret -> non-zero' 1 "$rc"

# ------------------------------------------------------------------ 不泄露

printf '\n== the value never appears in logs ==\n'
printf 'LOG_KEY=%s\n' "$SECRET_VALUE" >"$FIX/home/.config/dotfiles/env.local"
chmod 600 "$FIX/home/.config/dotfiles/env.local"
# dot_secret_load 打印「加载了哪些」——必须只有名字
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_load LOG_KEY' 2>&1)
expect_has 'load reports the name' 'LOG_KEY' "$out"
expect_lacks 'load never prints the value' "$SECRET_VALUE" "$out"

# 部分缺失时也只报名字
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_load LOG_KEY MISSING_ONE' 2>&1)
expect_has 'missing name is reported' 'MISSING_ONE' "$out"
expect_lacks 'still no value in the output' "$SECRET_VALUE" "$out"

printf '\n== dot_secret_load exports into the environment ==\n'
out=$(sec sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_load LOG_KEY >/dev/null 2>&1; printf "%s" "$LOG_KEY"')
expect 'the variable is set in the caller' "$SECRET_VALUE" "$out"

# ------------------------------------------------------------------ 模块

printf '\n== module creates the env file with mode 600 ==\n'
MB="$FIX/modbox"
mkdir -p "$MB"
out=$(env -i HOME="$MB" PATH="$PATH" DOT_ENV_LOCAL="$MB/.config/dotfiles/env.local" \
    sh "$BOOT" --only secrets 2>&1)
ok_if 'env file was created' '[ -f "$MB/.config/dotfiles/env.local" ]'
mode=$(file_mode "$MB/.config/dotfiles/env.local")
expect 'mode is 600' '600' "$mode"
dirmode=$(file_mode "$MB/.config/dotfiles")
expect 'parent dir is 700' '700' "$dirmode"

printf '\n== module tightens an over-permissive existing file ==\n'
chmod 644 "$MB/.config/dotfiles/env.local"
out=$(env -i HOME="$MB" PATH="$PATH" DOT_ENV_LOCAL="$MB/.config/dotfiles/env.local" \
    sh "$BOOT" --only secrets 2>&1)
mode=$(file_mode "$MB/.config/dotfiles/env.local")
expect 'permissions were tightened to 600' '600' "$mode"
expect_has 'the change is reported' 'tightened' "$out"

printf '\n== ollama is opt-in only ==\n'
out=$(env -i HOME="$MB" PATH="$PATH" DOT_ENV_LOCAL="$MB/.config/dotfiles/env.local" \
    sh "$BOOT" --only secrets 2>&1)
expect_has 'ollama is skipped by default' 'ollama: optional, not requested' "$out"
expect_lacks 'no model weights are mentioned as downloaded' 'pulling' "$out"

printf '\n== dry-run writes nothing ==\n'
DB="$FIX/drybox"
mkdir -p "$DB"
out=$(env -i HOME="$DB" PATH="$PATH" DOT_ENV_LOCAL="$DB/.config/dotfiles/env.local" \
    sh "$BOOT" --dry-run --only secrets 2>&1)
ok_if 'no env file created in dry-run' '[ ! -f "$DB/.config/dotfiles/env.local" ]'
expect_has 'the plan is printed' 'would create' "$out"

# ------------------------------------------------------------------ gitleaks 守卫

printf '\n== the pre-commit guard actually blocks a credential ==\n'
if command -v gitleaks >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    GR="$FIX/guardrepo"
    mkdir -p "$GR"
    (
        cd "$GR" || exit 1
        git init -q .
        git config user.email t@example.com
        git config user.name t
        printf 'clean\n' >ok.txt
        git add ok.txt
        git commit -qm init
    ) >/dev/null 2>&1

    # 装上模块生成的那份 hook（而不是另写一份）——要测的就是它
    env -i HOME="$FIX/hookhome" PATH="$PATH" DOT_ROOT="$GR" \
        sh -c "mkdir -p '$GR/.git/hooks'" 2>/dev/null
    # 从真实仓库里取已安装的 hook；没有就跳过这一段
    if [ -f "$DOT_REPO/.git/hooks/pre-commit" ] &&
        grep -q 'dotfiles-gitleaks-guard' "$DOT_REPO/.git/hooks/pre-commit" 2>/dev/null; then
        cp "$DOT_REPO/.git/hooks/pre-commit" "$GR/.git/hooks/pre-commit"
        chmod +x "$GR/.git/hooks/pre-commit"

        # 私钥是 gitleaks 默认规则里最可靠的一条（AWS 的 EXAMPLE key 被上游豁免）
        printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAxFakeKeyMaterialForTesting1234567890abcdef\n-----END RSA PRIVATE KEY-----\n' \
            >"$GR/leak.pem"
        blocked=no
        (
            cd "$GR" || exit 1
            git add leak.pem
            git commit -m 'should be blocked' >/dev/null 2>&1
        ) || blocked=yes
        expect 'a private key is blocked at commit time' 'yes' "$blocked"

        commits=$(cd "$GR" && git rev-list --count HEAD 2>/dev/null)
        expect 'the leaking commit was not created' '1' "$commits"

        # 干净提交必须仍然通过
        # 干净提交必须仍然通过。
        # 注意要把上一轮暂存的 leak.pem 从索引里彻底移除 —— 只 rm 文件 +
        # git reset 在部分 git 版本下仍会留下已删除文件的暂存记录，
        # 下一次 commit 就把「删除 leak.pem」也带上，而 gitleaks 扫的是
        # 暂存内容，于是又命中同一个密钥。用 git rm --cached 明确处理。
        (
            cd "$GR" || exit 1
            git rm --cached --quiet leak.pem 2>/dev/null || true
            git reset -q
        ) >/dev/null 2>&1
        rm -f "$GR/leak.pem"
        printf 'still clean\n' >"$GR/ok2.txt"
        clean_out=$(
            cd "$GR" || exit 1
            git add ok2.txt
            git commit -m 'clean' 2>&1
        )
        clean_ok=yes
        printf '%s' "$clean_out" | grep -q 'commit blocked' && clean_ok=no
        # 也可能因为别的原因失败（如身份未配置），那同样是问题
        (cd "$GR" && git log --oneline -1 2>/dev/null | grep -q clean) || clean_ok=no
        if [ "$clean_ok" = no ]; then
            printf '       commit output was: %s\n' "$(printf '%s' "$clean_out" | head -3)"
        fi
        expect 'a clean commit still succeeds' 'yes' "$clean_ok"
    else
        printf 'skip (guard hook not installed in this working copy)\n'
    fi

    printf '\n== this repository itself is clean ==\n'
    # 必须显式传 --config：gitleaks 只在**当前工作目录**下找 .gitleaks.toml，
    # 从别处扫描时配置不生效，本文件里那个故意造的假私钥就会被判为泄露。
    # 只扫被 git 跟踪的内容。`gitleaks dir` 会扫工作区里的一切，
    # 包括 CI checkout 后产生的临时文件与本机的未跟踪目录 ——
    # 那些不是「仓库内容」，把它们算进来会让这条断言随环境波动。
    _gl_report="$FIX/gitleaks-report.json"
    # 命令名随 gitleaks 版本变化（8.28 起 detect/protect -> dir/git）。
    # runner 镜像上的版本可能比本机旧，两代都要能跑。
    if gitleaks git --help >/dev/null 2>&1; then
        set -- git "$DOT_REPO"
    else
        set -- detect --source "$DOT_REPO"
    fi
    if gitleaks "$@" --config "$DOT_REPO/.gitleaks.toml" \
        --redact --no-banner --report-format json --report-path "$_gl_report" \
        >/dev/null 2>&1; then
        _pass=$((_pass + 1))
        printf 'ok   no credentials found in the repository history\n'
    else
        _fail=$((_fail + 1))
        printf 'FAIL gitleaks found credentials in this repository\n'
        # 报出位置便于诊断（--redact 保证不打印值本身）
        if [ -f "$_gl_report" ] && command -v python3 >/dev/null 2>&1; then
            python3 -c "
import json, sys
try:
    for f in json.load(open('$_gl_report'))[:5]:
        print('       %s:%s  rule=%s' % (f.get('File'), f.get('StartLine'), f.get('RuleID')))
except Exception:
    pass
"
        fi
    fi
else
    printf 'skip (gitleaks or git not available)\n'
fi

# ------------------------------------------------------------------ 静态保证

# ------------------------------------------------------------------ 1Password
#
# spec 要求三种情形都不能出问题：已登录能读、未登录不挂起、未安装能回退。
# 用替身 op 覆盖前两种（真实 op 需要账号），第三种是本机的实际状态。

printf '\n== 1Password CLI as an optional source ==\n'

OPBIN="$FIX/opbin"
mkdir -p "$OPBIN"
for t in sh printf sed grep head cat command timeout; do
    if p=$(command -v "$t" 2>/dev/null); then ln -sf "$p" "$OPBIN/$t" 2>/dev/null || true; fi
done

# 替身 op：已登录，read 返回一个值
cat >"$OPBIN/op" <<'OPSCRIPT'
#!/bin/sh
case $1 in
    whoami) exit 0 ;;
    read) printf 'value-from-1password\n'; exit 0 ;;
esac
exit 1
OPSCRIPT
chmod +x "$OPBIN/op"

out=$(env -i HOME="$FIX/ophome" PATH="$OPBIN:$PATH" \
    DOT_LIB_DIR="$DOT_REPO/lib" DOT_OS=nosuchos \
    DOT_ENV_LOCAL="$FIX/ophome/env.local" \
    sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get OP_KEY' 2>/dev/null)
expect 'a signed-in 1Password returns the value' 'value-from-1password' "$out"

# 替身 op：未登录（whoami 失败）——必须提示并回退，且不挂住
cat >"$OPBIN/op" <<'OPSCRIPT'
#!/bin/sh
case $1 in
    whoami) printf 'not signed in\n' >&2; exit 1 ;;
    read) printf 'should not be reached\n'; exit 0 ;;
esac
exit 1
OPSCRIPT
chmod +x "$OPBIN/op"

out=$(env -i HOME="$FIX/ophome" PATH="$OPBIN:$PATH" \
    DOT_LIB_DIR="$DOT_REPO/lib" DOT_OS=nosuchos \
    DOT_ENV_LOCAL="$FIX/ophome/env.local" \
    sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get OP_KEY' 2>&1)
expect_has 'not-signed-in is reported' 'not signed in' "$out"
expect_has 'it says how to fix it' 'op signin' "$out"
expect_lacks 'the read is not attempted when signed out' 'should not be reached' "$out"

# 未登录时必须在有限时间内返回。给足余量（超时是 5 秒）但要能抓住「永久挂住」。
start=$(date +%s)
env -i HOME="$FIX/ophome" PATH="$OPBIN:$PATH" \
    DOT_LIB_DIR="$DOT_REPO/lib" DOT_OS=nosuchos \
    DOT_ENV_LOCAL="$FIX/ophome/env.local" \
    sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get OP_KEY' >/dev/null 2>&1
elapsed=$(($(date +%s) - start))
if [ "$elapsed" -lt 20 ]; then
    _pass=$((_pass + 1))
    printf 'ok   signed-out 1Password returns within a bounded time (%ss)\n' "$elapsed"
else
    _fail=$((_fail + 1))
    printf 'FAIL signed-out 1Password took %ss — it must not hang\n' "$elapsed"
fi

# op 完全不存在时，回退到其他来源且不报错
mkdir -p "$FIX/noop"
for t in sh printf sed grep head cat command; do
    if p=$(command -v "$t" 2>/dev/null); then ln -sf "$p" "$FIX/noop/$t" 2>/dev/null || true; fi
done
mkdir -p "$FIX/ophome"
printf 'FALLBACK_KEY=from-file\n' >"$FIX/ophome/env.local"
chmod 600 "$FIX/ophome/env.local"
out=$(env -i HOME="$FIX/ophome" PATH="$FIX/noop" \
    DOT_LIB_DIR="$DOT_REPO/lib" DOT_OS=nosuchos \
    DOT_ENV_LOCAL="$FIX/ophome/env.local" \
    sh -c '. "$DOT_LIB_DIR/secrets.sh"; dot_secret_get FALLBACK_KEY' 2>/dev/null)
expect 'falls back to the local file when op is absent' 'from-file' "$out"

printf '\n== the shell fragment does not read secrets at startup ==\n'
FRAG="$DOT_REPO/config/zsh/zshrc.d/50-secrets.zsh"
ok_if 'fragment exists' '[ -f "$FRAG" ]'
# 片段里不得有顶层的取值调用 —— 只允许定义函数
ok_if 'no top-level secret read in the fragment' \
    '! grep -vE "^[[:space:]]*#" "$FRAG" | grep -qE "^[^[:space:]].*dot_secret_(get|load)[[:space:]]+[A-Z]"'
ok_if 'the secrets lib is not sourced at fragment load time' \
    '! grep -qE "^[[:space:]]*(source|\\.)[[:space:]].*secrets\\.sh" "$FRAG"'

printf '\n== the gitleaks config exists and covers the repo ==\n'
ok_if '.gitleaks.toml exists' '[ -f "$DOT_REPO/.gitleaks.toml" ]'
ok_if 'default rules are inherited' 'grep -q "useDefault = true" "$DOT_REPO/.gitleaks.toml"'
# 「config/ 是否被豁免」不能用 grep 判断 —— 配置里的注释也会提到它。
# 下面的 canary 用行为验证这一点，比文本匹配可靠。

# 豁免规则必须窄：一条 canary 验证「豁免没有把真实配置目录也放过」。
# 没有这条断言，一个过宽的 allowlist 会让整个守卫形同虚设而无人察觉。
printf '\n== the allowlist does not over-reach (canary) ==\n'
if command -v gitleaks >/dev/null 2>&1; then
    CANARY="$DOT_REPO/config/.gitleaks-canary.pem"
    printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAxCanaryMustBeDetected1234567890abcdefgh\n-----END RSA PRIVATE KEY-----\n' \
        >"$CANARY"
    canary_caught=no
    gitleaks dir "$DOT_REPO" --config "$DOT_REPO/.gitleaks.toml" \
        --redact --no-banner >/dev/null 2>&1 || canary_caught=yes
    rm -f "$CANARY"
    expect 'a real key under config/ is still detected' 'yes' "$canary_caught"
else
    printf 'skip (gitleaks not available)\n'
fi

printf '\n---------------------------------\n'
printf 'passed: %s  failed: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ] || exit 1
