#!/usr/bin/env sh
#
# 静态检查：shellcheck（POSIX sh 方言）+ shfmt 格式检查。
# CI 与本地共用这一个入口，保证两边判定一致。
#
#   sh test/lint.sh          # 检查
#   sh test/lint.sh --fix    # 顺手把格式修好
#
# legacy/ 与 private/ 是归档内容，不参与检查 —— 它们是历史原样保留，
# 按新规范去改反而破坏"归档即原样"的前提。
#
# shellcheck shell=sh

set -u

DOT_REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DOT_REPO" || exit 1

DOT_FIX=0
[ "${1:-}" = --fix ] && DOT_FIX=1

# 受检文件清单。显式列出而非全仓扫描，避免把归档内容卷进来。
dot_lint_files() {
    printf '%s\n' bootstrap.sh
    for f in lib/*.sh platform/*.sh test/*.sh modules/*/module.sh bin/*; do
        [ -f "$f" ] || continue
        # utils.sh 是旧安装脚本的遗留副本，将在迁移收尾时删除（tasks 10.6）
        [ "$f" = lib/utils.sh ] && continue
        printf '%s\n' "$f"
    done
}

# bin/ 下的脚本与生产脚本一样严格，但两条例外：
#   SC1091  动态 source lib/*.sh（路径来自变量），shellcheck 无法静态跟随
#   SC2016  给用户看的命令示例里含 $ 与反引号，必须单引号原样输出
DOT_LINT_BIN_EXCLUDE='SC1091,SC2016'

_rc=0

# ---------------------------------------------------------------- shellcheck

if command -v shellcheck >/dev/null 2>&1; then
    printf '== shellcheck ==\n'

    # 生产脚本：全量规则（bin/ 与 test/ 各有自己的放宽项，分开跑）
    # shellcheck disable=SC2046
    if shellcheck $(dot_lint_files | grep -vE '^(test|bin)/'); then
        printf 'shellcheck (scripts): clean\n'
    else
        printf 'shellcheck (scripts): FAILED\n'
        _rc=1
    fi

    # bin/ 下的用户命令
    _bin_files=$(dot_lint_files | grep '^bin/')
    if [ -n "$_bin_files" ]; then
        # 需要分词把文件列表展开成多个参数，故不加引号
        # shellcheck disable=SC2046,SC2086
        if shellcheck -e "$DOT_LINT_BIN_EXCLUDE" $_bin_files; then
            printf 'shellcheck (bin): clean\n'
        else
            printf 'shellcheck (bin): FAILED\n'
            _rc=1
        fi
    fi

    # 测试脚本额外放宽几条 —— 这些都是测试有意采用的写法，不是缺陷：
    #   SC2016       ok_if 接收延迟求值的条件字符串，必须单引号防止提前展开
    #   SC2012       用 ls 快照目录内容是最直接的写法，沙箱内文件名可控
    #   SC1091       动态 source lib/*.sh（路径来自变量），shellcheck 无法静态跟随
    #   SC2030/2031  用例故意在子 shell 中运行以隔离状态，计数通过记分文件带回
    #   SC1007       `CI= SSH_TTY= cmd` 是有意把变量置空后执行，不是笔误
    # shellcheck disable=SC2046
    if shellcheck -e SC2016,SC2012,SC1091,SC2030,SC2031,SC1007 $(dot_lint_files | grep '^test/'); then
        printf 'shellcheck (tests): clean\n'
    else
        printf 'shellcheck (tests): FAILED\n'
        _rc=1
    fi
else
    printf 'shellcheck: not installed, skipping (install it to run this check)\n'
fi

# ---------------------------------------------------------------- shfmt

if command -v shfmt >/dev/null 2>&1; then
    printf '\n== shfmt ==\n'
    if [ "$DOT_FIX" = 1 ]; then
        # shellcheck disable=SC2046
        shfmt -ln posix -i 4 -ci -w $(dot_lint_files)
        printf 'shfmt: formatted\n'
    else
        # shellcheck disable=SC2046
        if shfmt -ln posix -i 4 -ci -d $(dot_lint_files); then
            printf 'shfmt: clean\n'
        else
            printf 'shfmt: FAILED (run "sh test/lint.sh --fix")\n'
            _rc=1
        fi
    fi
else
    printf '\nshfmt: not installed, skipping\n'
fi

# ---------------------------------------------------------------- 项目约定

printf '\n== project conventions ==\n'

# 模块不得自己探测平台 —— 平台判断必须收敛在 lib/detect.sh 与 platform/。
# 否则每个模块各判一次，Apple Silicon 那类问题就会重现在每个模块里。
if grep -nE '(^|[^_[:alnum:]])uname([^_[:alnum:]]|$)|/etc/os-release' modules/*/module.sh 2>/dev/null; then
    printf 'FAILED: modules must not probe the platform directly; use DOT_* from lib/detect.sh\n'
    _rc=1
else
    printf 'modules do not probe the platform directly: ok\n'
fi

# GitHub Actions 的 YAML 必须可解析。一个缺冒号的笔误会让整个 workflow
# 静默不运行 —— 实测就踩到过（`steps` 少了冒号）。
if [ -d .github/workflows ]; then
    _yaml_rc=0
    if command -v yq >/dev/null 2>&1; then
        for _wf in .github/workflows/*.yml .github/workflows/*.yaml; do
            [ -f "$_wf" ] || continue
            if ! yq '.' "$_wf" >/dev/null 2>&1; then
                printf 'FAILED: %s is not valid YAML\n' "$_wf"
                yq '.' "$_wf" 2>&1 | head -3
                _yaml_rc=1
            fi
            # jobs 段必须存在且非空，否则 workflow 什么都不做
            if [ "$(yq '.jobs | length' "$_wf" 2>/dev/null)" = "0" ]; then
                printf 'FAILED: %s defines no jobs\n' "$_wf"
                _yaml_rc=1
            fi
        done
        [ "$_yaml_rc" = 0 ] && printf 'workflow YAML parses and defines jobs: ok\n'
        [ "$_yaml_rc" = 0 ] || _rc=1
    else
        printf 'workflow YAML: yq not installed, skipping\n'
    fi
fi

# CI 引用的脚本必须真的存在 —— workflow 里写错路径要等到 CI 跑起来才发现
if [ -f .github/workflows/ci.yml ]; then
    _missing_ref=''
    for _ref in test/lint.sh test/run_all.sh bootstrap.sh; do
        grep -q "$_ref" .github/workflows/ci.yml 2>/dev/null || continue
        [ -f "$_ref" ] || _missing_ref="$_missing_ref $_ref"
    done
    if [ -n "$_missing_ref" ]; then
        printf 'FAILED: ci.yml references missing files:%s\n' "$_missing_ref"
        _rc=1
    else
        printf 'ci.yml references only existing scripts: ok\n'
    fi
fi

# 下面两项只查真正会生效的配置内容。
# 注释不算违规 —— 说明"为什么禁用某域名"必然要写出那个域名，
# 把它判成违规是自我矛盾的；同理注释里出现路径也不影响运行时行为。
dot_config_files() {
    [ -d config ] || return 0
    find config -type f ! -name '*.md' 2>/dev/null
}

# 去掉行首注释与整行注释后再匹配
dot_config_code() {
    _cf=$(dot_config_files)
    [ -n "$_cf" ] || return 0
    printf '%s\n' "$_cf" | while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        # 保留文件名与行号，便于报错定位；剔除注释行
        grep -nv '^[[:space:]]*#' "$_f" 2>/dev/null | sed "s|^|$_f:|"
    done
}

_code=$(dot_config_code)

# 已下线的镜像域名不得出现在生效配置里（legacy/ 是归档，不查）
if [ -n "$_code" ] && printf '%s\n' "$_code" | grep 'npm\.taobao\.org'; then
    printf 'FAILED: dead mirror domain found in config/\n'
    _rc=1
else
    printf 'no dead mirror domains in config/: ok\n'
fi

# 配置里不得出现硬编码的**用户**主目录，必须用 $HOME —— 否则换机器/换用户名即失效。
# /home/linuxbrew 是 Linuxbrew 的固定系统位置，不是某个用户的主目录，需排除。
if [ -n "$_code" ] && printf '%s\n' "$_code" |
    grep -E '/(Users|home)/[A-Za-z0-9_.-]+' |
    grep -vE '/home/linuxbrew'; then
    printf 'FAILED: hardcoded home directory path found in config/ (use $HOME)\n'
    _rc=1
else
    printf 'no hardcoded home paths in config/: ok\n'
fi

# ---------------------------------------------------------------- 公开仓库安全

# 这个仓库是公开的，凭据形状的字符串一旦提交就等于永久泄露。
# gitleaks 是主防线（pre-commit + CI），这里做一道快速的补充检查 ——
# 即使机器上没装 gitleaks 也能拦住最明显的错误。
_cred_hits=$(grep -rInE \
    'sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{20,}|gho_[a-zA-Z0-9]{20,}|nvapi-[a-zA-Z0-9]{20,}|xoxb-[0-9]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----' \
    config/ lib/ modules/ platform/ bin/ bootstrap.sh 2>/dev/null || true)
if [ -n "$_cred_hits" ]; then
    printf 'FAILED: credential-shaped string found (this repo is public!)\n'
    # 只报位置，不回显命中的内容
    printf '%s\n' "$_cred_hits" | cut -d: -f1,2 | sed 's/^/  /'
    _rc=1
else
    printf 'no credential-shaped strings in tracked scripts/config: ok\n'
fi

# 凭据不得出现在会被 link 到 $HOME 的 shell 配置里。
# 常见错误：为了方便直接在 zshrc 片段里 export API key。
if [ -d config ] && grep -rInE '^[[:space:]]*export[[:space:]]+[A-Z_]*(API_KEY|TOKEN|SECRET|PASSWORD)[[:space:]]*=[[:space:]]*["'\'']?[A-Za-z0-9]' config/ 2>/dev/null; then
    printf 'FAILED: a credential appears to be assigned a literal value in config/\n'
    _rc=1
else
    printf 'no literal credential assignments in config/: ok\n'
fi

# 本地覆盖文件绝不能被仓库管理 —— 它们按设计是不入库的
_tracked_local=''
if [ -d .git ] && command -v git >/dev/null 2>&1; then
    for _pat in 'env.local' '.zshrc.local' '.gitconfig.local' 'settings.local.json'; do
        if git ls-files --error-unmatch "*$_pat" >/dev/null 2>&1; then
            _tracked_local="$_tracked_local $_pat"
        fi
    done
fi
if [ -n "$_tracked_local" ]; then
    printf 'FAILED: local override files must never be tracked:%s\n' "$_tracked_local"
    _rc=1
else
    printf 'local override files are not tracked: ok\n'
fi

# openspec CLI 为每个 AI 工具各生成一份等价的 skill 定义。它们必须逐字节相同 ——
# 否则同一个 /opsx:* 工作流在 Copilot 与 Claude Code 里行为不同，而这种漂移
# 不报错：重新生成时只更新一侧就会发生，用户只会觉得「另一个工具怪怪的」。
_skill_drift=''
for _d in .github/skills/*/; do
    [ -d "$_d" ] || continue
    _name=${_d#.github/skills/}
    _name=${_name%/}
    _mirror=".claude/skills/$_name/SKILL.md"
    if [ ! -f "$_mirror" ]; then
        _skill_drift="$_skill_drift missing:$_mirror"
    elif ! cmp -s "$_d/SKILL.md" "$_mirror"; then
        _skill_drift="$_skill_drift differs:$_name"
    fi
done
if [ -n "$_skill_drift" ]; then
    printf 'FAILED: openspec skill copies drifted between AI tools:%s\n' "$_skill_drift"
    printf '  regenerate both sides with the openspec CLI\n'
    _rc=1
else
    printf 'openspec skill copies are identical across AI tools: ok\n'
fi

# ---------------------------------------------------------------- 包名映射完整性

# RHEL 族的包名对 dnf 与 yum 多数是同一套，所以包名映射表里 dnf 分支通常都要
# 同时列上 yum。漏一个不会报错 —— dot_platform_pkg_name 返回空串，pkg.sh
# 当作「仓库里没这个包」转去走 cargo 回退，于是在只有 yum 的机器上
# （RHEL/CentOS 7、Amazon Linux 2）本可 yum 直装的工具变成现场编译，
# 慢几十倍且可能因缺 toolchain 失败。症状与「包确实不存在」无法区分。
#
# 但「包名一致」不等于「可用性一致」：github-cli 在 Fedora 仓库里有，
# 而 RHEL/CentOS 的 base 与 EPEL 都没有。这类情形是正当例外，用
# `# yum-differs:` 注释显式标注 —— 要求写注释而不是默许，
# 是为了区分「想清楚了」和「忘了加」。
#
# 只查 dot_platform_pkg_name 函数体：dot_platform_pkg_install 里的
# `dnf)` 分支是安装命令，必须与 yum 分开（命令名不同），不适用此规则。
if [ -f platform/linux.sh ]; then
    _pkgname_body=$(sed -n '/^dot_platform_pkg_name()/,/^}/p' platform/linux.sh)
    # 剔除被 yum-differs 标注的行：注释出现在分支行之前，所以先把
    # 标注行与紧随其后的分支行一起去掉。
    _bare_dnf=$(printf '%s\n' "$_pkgname_body" |
        grep -v '^[[:space:]]*#' |
        grep 'dnf' | grep -v 'yum' || true)
    # 有 yum-differs 标注时，允许的例外数就是标注数
    _exceptions=$(printf '%s\n' "$_pkgname_body" | grep -c 'yum-differs:' || true)
    _bare_count=$(printf '%s' "$_bare_dnf" | grep -c . || true)
    if [ "$_bare_count" -gt "$_exceptions" ]; then
        printf 'FAILED: dot_platform_pkg_name has %s dnf branch(es) missing yum but only %s marked as intentional:\n' \
            "$_bare_count" "$_exceptions"
        printf '%s\n' "$_bare_dnf" | sed 's/^/  /'
        printf '  RHEL-family package names are usually identical for dnf and yum — list both,\n'
        printf '  or yum-only machines silently fall back to compiling from source.\n'
        printf '  If the package genuinely differs in availability, add a "# yum-differs:" comment.\n'
        _rc=1
    else
        printf 'every dnf package-name branch covers yum or is marked yum-differs: ok\n'
    fi
fi

# ---------------------------------------------------------------- 可移植性

# 引导代码不得依赖 diffutils（cmp / diff）。它不是必装包 ——
# rockylinux:9 的最小镜像里两个都没有，而 debian:stable-slim 里恰好有 cmp，
# 所以这类依赖能在 debian 容器 job 里一路绿灯。
#
# 后果完全静默：cmp 缺失时 `cmp -s a b` 返回非零，被当成「内容不同」，
# 于是 dot_write 每次都重写文件 —— 幂等性在整个 RHEL 族上失效，零错误输出。
# lib/fs.sh 的 _dot_same_content 是替代方案。
#
# 只查引导会执行的代码；test/lint.sh 自己可以用 cmp（它只在 lint job 跑，
# 那里必然有 diffutils）。
_diffutils_dep=$(grep -nE '(^|[^_[:alnum:]-])(cmp|diff)[[:space:]]+-' \
    lib/*.sh modules/*/module.sh platform/*.sh bin/* bootstrap.sh 2>/dev/null |
    grep -v '^[^:]*:[0-9]*:[[:space:]]*#' || true)
if [ -n "$_diffutils_dep" ]; then
    printf 'FAILED: bootstrap code must not depend on diffutils (cmp/diff):\n'
    printf '%s\n' "$_diffutils_dep" | sed 's/^/  /'
    printf '  they are absent from minimal RHEL images; use _dot_same_content instead\n'
    _rc=1
else
    printf 'no diffutils dependency in bootstrap code: ok\n'
fi

printf '\n'
if [ "$_rc" = 0 ]; then
    printf 'lint: all checks passed\n'
else
    printf 'lint: FAILED\n'
fi
exit "$_rc"
