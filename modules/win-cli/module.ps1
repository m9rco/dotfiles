# 现代 CLI 工具链（Windows 侧）。
#
# 读的是同一份 config/cli/tools.txt —— 清单跨平台共享，
# 只有「逻辑名 -> 包名」的映射是平台相关的（在 platform/windows.ps1 里）。

$DotModule = @{
    Description = 'Modern CLI tools (ripgrep, fd, bat, eza, fzf, zoxide, delta, ...)'
    Platforms   = @('windows')
    Tags        = @('core', 'cli')
}

function Install-DotModule {
    $manifest = Join-Path $script:DotConfigDir 'cli\tools.txt'
    if (-not (Test-Path -LiteralPath $manifest)) {
        Write-DotError "tool manifest not found: $manifest"
        return $false
    }

    # scoop 是 Windows 侧首选，先确保它在
    if (-not (Test-DotCommand 'scoop') -and -not $script:DotDryRun) {
        Install-DotScoop | Out-Null
    }

    $installed = 0
    $skipped = 0
    $failed = @()
    $failedEssential = @()

    foreach ($line in (Get-Content -LiteralPath $manifest)) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        $parts = $line.Split('|')
        if ($parts.Count -lt 3) {
            Write-DotError "malformed manifest line: $line"
            $failed += $line
            $failedEssential += $line
            continue
        }

        $name = $parts[0].Trim()
        $platforms = $parts[1].Trim()
        $tag = $parts[2].Trim()

        # 未知标签必须报错而不是默默当成 default —— 打错字会让工具
        # 静静地不被安装，那是最难发现的一类问题。
        if ($tag -notin @('essential', 'default', 'optional')) {
            Write-DotError "unknown tag '$tag' for '$name' (want essential/default/optional)"
            $failed += $name
            $failedEssential += $name
            continue
        }

        # 平台筛选
        if ($platforms -ne 'all' -and ($platforms -split '\s+') -notcontains 'windows') {
            Write-DotSkip "${name}: not for windows (manifest says: $platforms)"
            $skipped++
            continue
        }

        # optional 需显式要求
        if ($tag -eq 'optional') {
            $wantVar = 'DOT_WANT_' + ($name.ToUpper() -replace '-', '_')
            $wanted = ([Environment]::GetEnvironmentVariable($wantVar) -eq '1')
            if (-not $wanted) {
                Write-DotSkip "${name}: optional, not requested (set $wantVar=1)"
                $skipped++
                continue
            }
        }

        if (Install-DotPackage $name) {
            $installed++
        }
        else {
            $failed += $name
            if ($tag -eq 'essential') { $failedEssential += $name }
        }
    }

    Write-DotInfo "installed/present: $installed · skipped: $skipped"

    # 与 Unix 侧同一套语义：只有 essential 工具失败才让模块失败。
    # 之前对任何失败都 return $false，而紧随其后的提示却说「profile 会
    # 优雅降级」—— 自相矛盾。
    if ($failed.Count -gt 0) {
        if ($failedEssential.Count -gt 0) {
            Write-DotError "could not install: $($failed -join ' ')"
            Write-DotError "  essential: $($failedEssential -join ' ')"
            Write-DotTip 'the rest degrade gracefully, but essential tools should be fixed'
            return $false
        }

        Write-DotTip "could not install: $($failed -join ' ')"
        Write-DotTip 'none of these are essential — the shell profile degrades gracefully'
    }
    return $true
}
