<#
.SYNOPSIS
    AI 时代的 dotfiles —— Windows 原生引导入口。

.DESCRIPTION
    与 bootstrap.sh 行为对齐：自动探测平台、发现模块、拓扑排序、
    幂等执行、支持预演。macOS / Linux / WSL 请用 bootstrap.sh。

    要求 PowerShell 5.1 起 —— 那是 Windows 自带的版本。引导会安装
    PowerShell 7，但引导本身不能依赖它。

.EXAMPLE
    .\bootstrap.ps1 -DryRun
    预演，不做任何改动。

.EXAMPLE
    .\bootstrap.ps1 -Only zsh,git
    只装指定模块（依赖会被自动带上）。
#>

[CmdletBinding()]
param(
    # 只打印将要执行的操作，不改任何东西
    [switch]$DryRun,

    # 只装这些模块（连同它们的依赖）
    [string[]]$Only,

    # 装除这些模块之外的全部
    [string[]]$Skip,

    # 只装带此标签的模块
    [string]$Tag,

    # 列出全部模块及其是否适用于本机
    [switch]$List,

    # 打印平台探测结果
    [switch]$Info,

    # 用法
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 路径

$script:DotRoot = $PSScriptRoot
$script:DotLibDir = Join-Path $DotRoot 'lib'
$script:DotPlatformDir = Join-Path $DotRoot 'platform'
# 允许预设，供测试用替身目录 —— 与 Unix 侧同一约定
$script:DotModulesDir = if ($env:DOT_MODULES_DIR) { $env:DOT_MODULES_DIR } else { Join-Path $DotRoot 'modules' }
$script:DotConfigDir = if ($env:DOT_CONFIG_DIR) { $env:DOT_CONFIG_DIR } else { Join-Path $DotRoot 'config' }
$script:DotDryRun = [bool]$DryRun

$env:DOT_ROOT = $DotRoot
$env:DOT_CONFIG_DIR = $DotConfigDir

# 加载库。platform 层要在 lib 之后 —— 它用到 lib 里的日志函数。
. (Join-Path $DotLibDir 'windows.ps1')
. (Join-Path $DotPlatformDir 'windows.ps1')

# ---------------------------------------------------------------- 用法

function Show-DotUsage {
    $tags = (Get-DotAllTags) -join ' '
    @"
Usage: .\bootstrap.ps1 [options]

Sets up this machine from the dotfiles in $DotRoot.
For macOS / Linux / WSL use ./bootstrap.sh instead.

Options:
  -DryRun            Show what would happen without changing anything
  -Only <a,b>        Install only these modules (dependencies come along)
  -Skip <a,b>        Install everything except these modules
  -Tag <tag>         Install only modules carrying this tag
  -List              List all modules and whether they apply here
  -Info              Print platform detection results
  -Help              Show this help

Available tags: $tags

Run '.\bootstrap.ps1 -List' for the module list — it is generated from
modules\ on disk, so it is always current.
"@
}

# ---------------------------------------------------------------- 模块发现
#
# 与 Unix 侧同一契约：扫描 modules/*/module.ps1，元数据放在文件顶部的
# 一个 hashtable 里。Windows 侧用 .ps1 而不是 .sh —— 同一个目录下可以
# 两者并存，各自的引导只认自己那种。

function Get-DotModules {
    $modules = @{}

    if (-not (Test-Path -LiteralPath $DotModulesDir -PathType Container)) {
        Write-DotError "modules directory not found: $DotModulesDir"
        return $null
    }

    $bad = $false

    foreach ($dir in (Get-ChildItem -LiteralPath $DotModulesDir -Directory)) {
        $name = $dir.Name
        $file = Join-Path $dir.FullName 'module.ps1'
        if (-not (Test-Path -LiteralPath $file)) { continue }

        # 模块名限制为 [A-Za-z0-9_-]，与 Unix 侧一致
        if ($name -notmatch '^[A-Za-z0-9_-]+$') {
            Write-DotError "invalid module name '$name' (allowed: A-Za-z0-9_-)"
            $bad = $true
            continue
        }

        # 在子作用域里点源加载并把结果作为对象返回 ——
        # 比往父作用域 Set-Variable 更可靠，也不会污染 runner 自身的命名空间。
        #
        # 注意：不要把 if/else 表达式内联写进 [pscustomobject]@{} 的字面量里。
        # PowerShell 7.5 接受那种写法，7.6 的解析器拒绝（报 MissingEndCurlyBrace，
        # 且错误位置指向整个函数而非真正出问题的那一行）。拆成普通语句最稳。
        $probe = $null
        try {
            $probe = & {
                . $file

                $metaValue = $null
                if (Get-Variable -Name 'DotModule' -Scope Local -ErrorAction SilentlyContinue) {
                    $metaValue = $DotModule
                }

                # 不用反引号续行 —— 它在嵌套 scriptblock 里对解析器很敏感，
                # PowerShell 7.6 会报 MissingEndCurlyBrace 且错误位置指向整个
                # 函数（与真正出问题的行相差 40 行）。拆成两句最稳。
                $installCmd = Get-Command -Name 'Install-DotModule' -CommandType Function -ErrorAction SilentlyContinue
                $hasInstall = [bool]$installCmd

                [pscustomobject]@{
                    Meta       = $metaValue
                    HasInstall = $hasInstall
                }
            }
        }
        catch {
            Write-DotError "module '$name': failed to load module.ps1 — $_"
            $bad = $true
            continue
        }

        if (-not $probe -or -not $probe.Meta) {
            Write-DotError "module '$name': missing the `$DotModule metadata hashtable"
            $bad = $true
            continue
        }

        $meta = $probe.Meta
        $missing = @()
        foreach ($key in @('Description', 'Platforms', 'Tags')) {
            if (-not $meta.ContainsKey($key) -or -not $meta[$key]) { $missing += $key }
        }
        if ($missing.Count -gt 0) {
            Write-DotError "module '$name': missing $($missing -join ', ') in `$DotModule"
            $bad = $true
            continue
        }

        if (-not $probe.HasInstall) {
            Write-DotError "module '$name': missing the Install-DotModule function"
            $bad = $true
            continue
        }

        # 同上：if/else 不内联进 hashtable 字面量
        $requires = @()
        if ($meta.ContainsKey('Requires')) { $requires = @($meta['Requires']) }
        $needsGui = $false
        if ($meta.ContainsKey('NeedsGui')) { $needsGui = [bool]$meta['NeedsGui'] }

        $modules[$name] = @{
            Name        = $name
            File        = $file
            Description = $meta['Description']
            Platforms   = @($meta['Platforms'])
            Tags        = @($meta['Tags'])
            Requires    = $requires
            NeedsGui    = $needsGui
        }
    }

    if ($bad) { return $null }
    return $modules
}

function Get-DotAllTags {
    if (-not $script:DotAllModules) { return @() }
    $tags = @()
    foreach ($m in $script:DotAllModules.Values) { $tags += $m.Tags }
    return ($tags | Sort-Object -Unique)
}

# ---------------------------------------------------------------- 适用性

$script:DotSkipReason = ''

function Test-DotModuleApplicable {
    param([Parameter(Mandatory = $true)][hashtable]$Module)

    $script:DotSkipReason = ''

    if ($Module.Platforms -notcontains $script:DotOS) {
        $script:DotSkipReason = "platform not supported (needs: $($Module.Platforms -join ' '), have: $script:DotOS)"
        return $false
    }
    if ($Module.NeedsGui -and $script:DotHeadless -eq 1) {
        $script:DotSkipReason = 'requires a graphical environment (headless: CI/non-interactive)'
        return $false
    }
    return $true
}

# ---------------------------------------------------------------- 拓扑排序

function Get-DotSortedModules {
    param([Parameter(Mandatory = $true)][string[]]$Names)

    $state = @{}
    $order = New-Object System.Collections.Generic.List[string]

    # 递归访问。用局部变量而非脚本级 —— 与 Unix 侧那个 local 的教训相同：
    # 递归里共享变量会让外层的值被内层覆写，拓扑序会错乱。
    function Visit {
        param([string]$Name, [string]$Path)

        $chain = if ($Path) { "$Path -> $Name" } else { $Name }

        if ($state.ContainsKey($Name)) {
            if ($state[$Name] -eq 'done') { return $true }
            if ($state[$Name] -eq 'visiting') {
                $script:DotSortError = "circular dependency: $chain"
                return $false
            }
        }

        if (-not $script:DotAllModules.ContainsKey($Name)) {
            $script:DotSortError = "unknown dependency '$Name' (required via $chain)"
            return $false
        }

        $state[$Name] = 'visiting'
        foreach ($dep in $script:DotAllModules[$Name].Requires) {
            if (-not (Visit -Name $dep -Path $chain)) { return $false }
        }
        $state[$Name] = 'done'
        $order.Add($Name)
        return $true
    }

    $script:DotSortError = $null
    foreach ($n in $Names) {
        if (-not (Visit -Name $n -Path '')) {
            Write-DotError $script:DotSortError
            return $null
        }
    }
    return $order.ToArray()
}

# ---------------------------------------------------------------- 执行

function Invoke-DotModules {
    param([Parameter(Mandatory = $true)][string[]]$Names)

    $ok = @()
    $failed = @()
    $skipped = @()

    foreach ($name in $Names) {
        $module = $script:DotAllModules[$name]

        # 依赖失败则跳过下游
        $depFailed = $null
        foreach ($dep in $module.Requires) {
            if ($failed -contains $dep -or $skipped -contains $dep) { $depFailed = $dep; break }
        }
        if ($depFailed) {
            Write-DotSkip "${name}: skipped (dependency failed: $depFailed)"
            $skipped += $name
            continue
        }

        if (-not (Test-DotModuleApplicable $module)) {
            Write-DotSkip "${name}: $script:DotSkipReason"
            $skipped += $name
            continue
        }

        Write-DotStep "$name — $($module.Description)"

        # 在子作用域里执行，模块的函数与变量不泄漏到下一个模块
        $result = $false
        try {
            $result = & {
                . $module.File
                Install-DotModule
            }
            # 模块用 return $false 或抛异常表示失败
            if ($null -eq $result) { $result = $true }
        }
        catch {
            Write-DotError "${name}: $_"
            $result = $false
        }

        if ($result -eq $false) {
            Write-DotError "$name failed"
            $failed += $name
        }
        else {
            $ok += $name
        }
    }

    Write-DotStep 'Summary'
    if ($ok.Count -gt 0) { Write-DotSuccess "succeeded ($($ok.Count)): $($ok -join ' ')" }
    if ($skipped.Count -gt 0) { Write-DotSkip "skipped ($($skipped.Count)): $($skipped -join ' ')" }
    if ($failed.Count -gt 0) { Write-DotError "failed ($($failed.Count)): $($failed -join ' ')" }

    Show-DotBackupSummary

    return ($failed.Count -eq 0)
}

# ---------------------------------------------------------------- 清单

function Show-DotModuleList {
    $fmt = '{0,-18} {1,-12} {2,-24} {3}'
    Write-Output ($fmt -f 'MODULE', 'TAGS', 'PLATFORMS', 'STATUS')
    Write-Output ($fmt -f '------', '----', '---------', '------')

    foreach ($name in ($script:DotAllModules.Keys | Sort-Object)) {
        $m = $script:DotAllModules[$name]
        if (Test-DotModuleApplicable $m) { $status = 'applicable' }
        else { $status = "skip: $script:DotSkipReason" }
        Write-Output ($fmt -f $name, ($m.Tags -join ','), ($m.Platforms -join ' '), $status)
        Write-Output ('                   {0}' -f $m.Description)
    }
}

# ---------------------------------------------------------------- 主流程

Invoke-DotDetect

$script:DotAllModules = Get-DotModules
if ($null -eq $script:DotAllModules) { exit 1 }

if ($Help) { Show-DotUsage; exit 0 }
if ($Info) { Show-DotDetect; exit 0 }
if ($List) { Show-DotModuleList; exit 0 }

# 未知模块名必须报错而非静默忽略
foreach ($n in @($Only) + @($Skip)) {
    if ($n -and -not $script:DotAllModules.ContainsKey($n)) {
        Write-DotError "unknown module: $n"
        Write-DotError "run '.\bootstrap.ps1 -List' to see available modules"
        exit 1
    }
}

# 选择模块
$selected = @()
if ($Only) {
    $selected = @($Only)
}
else {
    foreach ($name in $script:DotAllModules.Keys) {
        $m = $script:DotAllModules[$name]
        if ($Tag) {
            if ($m.Tags -contains $Tag) { $selected += $name }
        }
        elseif ($m.Tags -contains 'core') {
            $selected += $name
        }
    }
}

if ($Skip) {
    $selected = $selected | Where-Object { $Skip -notcontains $_ }
}

if (-not $selected -or $selected.Count -eq 0) {
    Write-DotError 'no modules selected'
    if ($Tag) {
        Write-DotError "no module carries tag '$Tag' (available: $((Get-DotAllTags) -join ' '))"
    }
    exit 1
}

$ordered = Get-DotSortedModules -Names $selected
if ($null -eq $ordered) { exit 1 }

if ($script:DotDryRun) { Write-DotTip 'dry run — nothing will be modified' }

$wslNote = ''
if ($script:DotHeadless -eq 1) { $wslNote = ' · headless' }
Write-DotInfo "platform: $script:DotOS/$script:DotArch · pkg: $script:DotPkg · PowerShell $script:DotPSVersion$wslNote"

if (Invoke-DotModules -Names $ordered) { exit 0 } else { exit 1 }
