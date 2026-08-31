# PowerShell 环境：PowerShell 7 + profile。
#
# Windows 原生没有 zsh（那是 WSL 的事），所以这里是 Unix 侧 zsh 模块的对位物：
# 同样接 starship、同样的现代 CLI 别名、同样的本地覆盖机制。

$DotModule = @{
    Description = 'PowerShell 7 + profile (starship, aliases, PSReadLine)'
    Platforms   = @('windows')
    Tags        = @('core', 'shell')
}

function Install-DotModule {
    # PowerShell 7：引导本身跑在 5.1 上也能装它
    if (-not (Test-DotCommand 'pwsh')) {
        Write-DotInfo 'PowerShell 7 not found; installing'
        if (-not (Install-DotPackage 'pwsh')) {
            Write-DotTip 'continuing with the current PowerShell version'
        }
    }
    else {
        Write-DotSkip 'PowerShell 7 already installed'
    }

    # profile 铺到 5.1 与 7 两个位置 —— 用户可能在任一环境里工作
    $repoProfile = Join-Path $script:DotConfigDir 'powershell\profile.ps1'
    if (-not (Test-Path -LiteralPath $repoProfile)) {
        Write-DotError "profile not found in the repo: $repoProfile"
        return $false
    }

    $ok = $true
    foreach ($dir in @((Get-DotPwsh7ProfileDir), (Get-DotPwsh5ProfileDir))) {
        $target = Join-Path $dir 'profile.ps1'
        if (-not (New-DotLink -Source $repoProfile -Target $target)) { $ok = $false }
    }

    # DOTFILES 需要在 profile 里定位仓库。写进用户环境变量，
    # 这样新开的 shell 都能拿到（不需要重启）。
    if (-not $script:DotDryRun) {
        [Environment]::SetEnvironmentVariable('DOTFILES', $script:DotRoot, 'User')
        $env:DOTFILES = $script:DotRoot
        Write-DotSuccess "DOTFILES set to $script:DotRoot (user environment)"
    }
    else {
        Write-DotInfo "[dry-run] would set the DOTFILES user environment variable"
    }

    return $ok
}
