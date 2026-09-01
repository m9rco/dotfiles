#!/usr/bin/env sh
#
# PowerShell 侧的静态检查：语法解析 + PSScriptAnalyzer。
#
# 与 test/lint.sh 分开是因为它需要 pwsh —— 没有 pwsh 的机器上
# 应该跳过而不是失败。
#
#   sh test/lint_ps.sh
#
# shellcheck shell=sh

set -u

DOT_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DOT_ROOT" || exit 1

# pwsh 可能在 PATH 里，也可能是本地解压的（macOS 上装 cask 需要 sudo）
PWSH=''
for cand in pwsh "$HOME/.local/pwsh/pwsh" /usr/local/bin/pwsh; do
    if command -v "$cand" >/dev/null 2>&1 || [ -x "$cand" ]; then
        PWSH=$cand
        break
    fi
done

if [ -z "$PWSH" ]; then
    printf 'pwsh not installed; skipping PowerShell checks\n'
    printf '  (CI runs them on windows-latest; install PowerShell to run them locally)\n'
    exit 0
fi

printf 'using: %s (%s)\n\n' "$PWSH" "$("$PWSH" --version 2>/dev/null)"

_rc=0

# ---------------------------------------------------------------- 语法

printf '== syntax ==\n'
for f in bootstrap.ps1 lib/windows.ps1 platform/windows.ps1 \
    config/powershell/profile.ps1 modules/*/module.ps1; do
    [ -f "$f" ] || continue
    # 传相对路径并让 PowerShell 在仓库根解析 —— 不能拼 $DOT_ROOT：
    # 在 Git-Bash（Windows CI）下它是 /d/a/repo 这种 POSIX 形式，
    # PowerShell 会把它当成 D:\d\a\repo 而找不到文件。
    out=$("$PWSH" -NoProfile -Command "
        Set-Location -LiteralPath (Resolve-Path '.')
        \$e = \$null
        \$full = (Resolve-Path -LiteralPath '$f').Path
        [System.Management.Automation.Language.Parser]::ParseFile(\$full, [ref]\$null, [ref]\$e) | Out-Null
        if (\$e) { \$e | ForEach-Object { Write-Output \"L\$(\$_.Extent.StartLineNumber): \$(\$_.Message)\" } }
    " 2>&1)
    if [ -n "$out" ]; then
        printf 'FAILED %s\n' "$f"
        printf '%s\n' "$out" | sed 's/^/  /'
        _rc=1
    else
        printf 'ok     %s\n' "$f"
    fi
done

# ---------------------------------------------------------------- 脆弱写法
#
# 本机的 PowerShell 版本可能比 CI runner 旧，有些写法在本机解析通过、
# 在新版被拒（实测两次：内联 if 进 hashtable 字面量、嵌套 scriptblock 里的
# 反引号续行，都报 MissingEndCurlyBrace 且错误位置指向整个函数）。
# 与其每次靠 CI 发现，不如直接禁掉这些写法。

printf '\n== fragile constructs ==\n'

_frag=0

# 含非 ASCII 的 .ps1 必须带 UTF-8 BOM，否则 PowerShell 5.1 读成乱码
for _f in bootstrap.ps1 lib/*.ps1 platform/*.ps1 modules/*/module.ps1 \
    config/powershell/*.ps1; do
    [ -f "$_f" ] || continue
    # 有非 ASCII 字节吗？
    if LC_ALL=C grep -q '[^ -~	]' "$_f" 2>/dev/null; then
        # 前三字节必须是 EF BB BF
        if [ "$(dd if="$_f" bs=3 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" != efbbbf ]; then
            printf 'FAILED: %s has non-ASCII content but no UTF-8 BOM\n' "$_f"
            printf '        PowerShell 5.1 will misparse it (MissingEndCurlyBrace)\n'
            _frag=1
        fi
    fi
done

# 反引号续行：对解析器敏感，且行尾多一个空格就静默失效
if grep -nE '`$' bootstrap.ps1 lib/*.ps1 platform/*.ps1 modules/*/module.ps1 \
    config/powershell/*.ps1 2>/dev/null; then
    printf 'FAILED: backtick line continuation found — split into separate statements\n'
    _frag=1
fi

# if/else 表达式内联进 hashtable 字面量
if grep -nE '^\s+[A-Za-z_]+\s*=\s*if \(' bootstrap.ps1 lib/*.ps1 platform/*.ps1 \
    modules/*/module.ps1 config/powershell/*.ps1 2>/dev/null; then
    printf 'FAILED: inline if/else inside a hashtable literal — assign before the literal\n'
    _frag=1
fi

if [ "$_frag" = 0 ]; then
    printf 'no fragile constructs\n'
else
    _rc=1
fi

# ---------------------------------------------------------------- 可执行性
#
# ParseFile 只做语法解析，能通过不代表能运行 —— 实测有一处内联 if 写进
# hashtable 字面量，PowerShell 7.5 的解析器接受、7.6 拒绝，只有真正
# 加载脚本才会暴露。这里对每个库文件做一次实际点源加载。

printf '\n== loadable (dot-source, not just parse) ==\n'
for f in lib/windows.ps1 platform/windows.ps1; do
    [ -f "$f" ] || continue
    out=$("$PWSH" -NoProfile -Command "
        \$ErrorActionPreference = 'Stop'
        try { . './$f'; Write-Output 'OK' }
        catch { Write-Output \"LOAD ERROR: \$_\" }
    " 2>&1)
    case $out in
        *OK*) printf 'ok     %s loads\n' "$f" ;;
        *)
            printf 'FAILED %s does not load\n' "$f"
            printf '%s\n' "$out" | sed 's/^/  /'
            _rc=1
            ;;
    esac
done

# bootstrap.ps1 的函数定义必须能被解析并进入作用域。
# -Help 已经覆盖了主流程，这里额外确认模块发现函数本身可调用。
out=$("$PWSH" -NoProfile -Command "
    \$ErrorActionPreference = 'Stop'
    try {
        \$null = & ./bootstrap.ps1 -List
        Write-Output 'OK'
    } catch { Write-Output \"RUN ERROR: \$_\" }
" 2>&1)
case $out in
    *OK*) printf 'ok     bootstrap.ps1 -List runs end to end\n' ;;
    *)
        printf 'FAILED bootstrap.ps1 -List does not run\n'
        printf '%s\n' "$out" | sed 's/^/  /'
        _rc=1
        ;;
esac

# ---------------------------------------------------------------- PSScriptAnalyzer

printf '\n== PSScriptAnalyzer ==\n'

# 排除的规则，每条都有理由 —— 不是「太吵所以关掉」：
#
#   PSAvoidUsingWriteHost           引导程序的输出就是给人看的终端文本，
#                                   不是可管道的对象。Write-Output 会污染
#                                   函数的返回值（PowerShell 里返回值是
#                                   所有未捕获的输出）。
#   PSAvoidUsingInvokeExpression    starship / zoxide 的官方初始化方式就是
#                                   eval 它们生成的代码，没有替代写法。
#   PSUseShouldProcessForStateChangingFunctions
#                                   -WhatIf/-Confirm 是 cmdlet 的约定；
#                                   我们用 -DryRun 统一两侧的语义，
#                                   混用两套会让行为更难预测。
#   PSUseSingularNouns              Get-DotModules 返回多个模块，复数是对的。
# 注意：PSUseBOMForUnicodeEncodedFile **不能**豁免。
# 我最初以此为「带 BOM 会干扰 Unix 侧工具」而关掉它，那个判断是错的：
# PowerShell 5.1 对无 BOM 的 UTF-8 按系统代码页解析，含中文注释的文件
# 会被拆成乱码字节，花括号匹配随之失效 —— CI 上表现为
# MissingEndCurlyBrace 且错误位置指向整个函数。
# 现代 git 与编辑器处理 BOM 没有问题，而 5.1 兼容是硬要求。
#   PSUseDeclaredVarsMoreThanAssignments
#                                   $DotModule 是模块契约，由 runner 读取，
#                                   在模块文件内部看起来「未使用」。
EXCLUDE='PSAvoidUsingWriteHost,PSAvoidUsingInvokeExpression,PSUseShouldProcessForStateChangingFunctions,PSUseSingularNouns,PSUseDeclaredVarsMoreThanAssignments'

has_analyzer=$("$PWSH" -NoProfile -Command "
    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { 'yes' } else { 'no' }
" 2>/dev/null | tr -d '\r')

if [ "$has_analyzer" != yes ]; then
    printf 'PSScriptAnalyzer not installed; skipping\n'
    printf '  install with: %s -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"\n' "$PWSH"
else
    out=$("$PWSH" -NoProfile -Command "
        Import-Module PSScriptAnalyzer
        \$files = @('bootstrap.ps1','lib/windows.ps1','platform/windows.ps1','config/powershell/profile.ps1')
        \$files += (Get-ChildItem -Path 'modules' -Filter 'module.ps1' -Recurse |
                    ForEach-Object { \$_.FullName })
        \$all = @()
        foreach (\$f in \$files) {
            if (-not (Test-Path \$f)) { continue }
            \$all += Invoke-ScriptAnalyzer -Path \$f -Severity Error,Warning \
                -ExcludeRule ('$EXCLUDE' -split ',') -ErrorAction SilentlyContinue
        }
        foreach (\$r in \$all) {
            Write-Output \"\$(\$r.ScriptName):\$(\$r.Line) [\$(\$r.Severity)] \$(\$r.RuleName) — \$(\$r.Message)\"
        }
    " 2>&1)

    if [ -n "$out" ]; then
        printf 'FAILED:\n'
        printf '%s\n' "$out" | sed 's/^/  /'
        _rc=1
    else
        printf 'clean\n'
    fi
fi

# ---------------------------------------------------------------- 行为冒烟

printf '\n== smoke (-Info / -List / -Help must be side-effect free) ==\n'

for arg in -Info -List -Help; do
    if "$PWSH" -NoProfile -File ./bootstrap.ps1 "$arg" >/dev/null 2>&1; then
        printf 'ok     bootstrap.ps1 %s\n' "$arg"
    else
        printf 'FAILED bootstrap.ps1 %s\n' "$arg"
        _rc=1
    fi
done

# -Info 的输出必须含全部探测键，与 Unix 侧的 --info 对齐
for key in DOT_OS DOT_ARCH DOT_PKG DOT_WSL DOT_HEADLESS; do
    if "$PWSH" -NoProfile -File ./bootstrap.ps1 -Info 2>/dev/null | grep -q "^$key "; then
        printf 'ok     -Info reports %s\n' "$key"
    else
        printf 'FAILED -Info is missing %s\n' "$key"
        _rc=1
    fi
done

# 未知模块必须非零退出
if "$PWSH" -NoProfile -File ./bootstrap.ps1 -Only definitely-not-a-module >/dev/null 2>&1; then
    printf 'FAILED unknown module should exit non-zero\n'
    _rc=1
else
    printf 'ok     unknown module exits non-zero\n'
fi

printf '\n'
if [ "$_rc" = 0 ]; then
    printf 'lint_ps: all checks passed\n'
else
    printf 'lint_ps: FAILED\n'
fi
exit "$_rc"
