# Windows Terminal —— 现代终端，支持 Nerd Font 与真彩色。
# 旧的 conhost 无法正确显示 starship 的图标与颜色。

$DotModule = @{
    Description = 'Windows Terminal'
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
    Write-DotTip 'set the font to "JetBrainsMono Nerd Font" in Windows Terminal settings'
    return $true
}
