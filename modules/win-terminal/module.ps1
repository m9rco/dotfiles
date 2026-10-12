# Windows Terminal —— 现代终端，支持 Nerd Font 与真彩色。
# 旧的 conhost 无法正确显示 starship 的图标与颜色。

$DotModule = @{
    Description = 'Windows Terminal + Nerd Font / Catppuccin settings'
    Platforms   = @('windows')
    Tags        = @('core')
    # GUI 应用：无桌面环境时装它没有意义
    NeedsGui    = $true
}

function Install-DotModule {
    if (-not (Install-DotPackage 'windows-terminal')) {
        Write-DotTip 'Windows Terminal is optional; the rest of the setup still works'
        return $true
    }

    # 把字体/配色/默认 profile 写进用户的 settings.json。真源是
    # config/windows-terminal/settings.json，合并逻辑在 platform/windows.ps1。
    # 保守合并（不覆盖用户已设过的值）+ 写前备份。
    $fragment = Join-Path $script:DotConfigDir 'windows-terminal\settings.json'
    $paths = @(Get-DotWindowsTerminalSettingsPaths)

    if ($paths.Count -eq 0) {
        Write-DotSkip 'Windows Terminal settings.json not found; skipping font/color setup'
        Write-DotTip 'if Windows Terminal is installed, set the font to "JetBrainsMono Nerd Font" manually'
        return $true
    }

    foreach ($path in $paths) {
        if (-not (Merge-DotWindowsTerminalSettings -SettingsPath $path -FragmentPath $fragment)) {
            Write-DotTip "could not update $path; set the font to 'JetBrainsMono Nerd Font' manually"
        }
    }

    return $true
}
