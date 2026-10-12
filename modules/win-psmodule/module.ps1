# PowerShell 模块（PSGallery）。
#
# win-cli 装的是 scoop 包；PowerShell 侧的模块（PSFzf、Terminal-Icons）没有
# 任何模块负责 —— 而 config/powershell/profile.ps1 已经引用了它们。缺了不报错，
# 只是模糊补全与文件图标静默失效，属于「比装不上更难发现」的那类空白。
#
# 全部非必需：装不上时 profile 会优雅降级，不该让整台机器的引导失败。
# 与 win-cli「只有 essential 失败才致命」的语义一致。

$DotModule = @{
    Description = 'PowerShell Gallery modules used by the profile (PSFzf, Terminal-Icons)'
    Platforms   = @('windows')
    Tags        = @('core', 'shell')
}

function Install-DotModule {
    # 模块名列表放在函数里而不是脚本级的 $script: —— 模块文件是被 runner
    # 点源进子作用域的，$script: 指向的未必是这个文件所在的作用域。
    $modules = @('PSFzf', 'Terminal-Icons')
    $failed = @()

    # 先确保能非交互地访问 PSGallery。5.1 上首次装模块会提示安装 NuGet
    # provider 并询问是否信任仓库 —— 无人值守/CI 下那会直接挂住。
    if (-not $script:DotDryRun) {
        Initialize-DotPsRepository
    }

    foreach ($name in $modules) {
        if (Get-Module -ListAvailable -Name $name) {
            Write-DotSkip "$name already available"
            continue
        }

        if ($script:DotDryRun) {
            Write-DotInfo "[dry-run] would install PowerShell module $name"
            continue
        }

        Write-DotInfo "installing PowerShell module $name"
        try {
            $installArgs = @{
                Name               = $name
                Scope              = 'CurrentUser'
                Force              = $true
                AllowClobber       = $true
                SkipPublisherCheck = $true
                ErrorAction        = 'Stop'
            }
            Install-Module @installArgs
            Write-DotSuccess "installed $name"
        }
        catch {
            Write-DotError "could not install ${name}: $_"
            $failed += $name
        }
    }

    if ($failed.Count -gt 0) {
        Write-DotTip "optional modules not installed (the profile degrades without them): $($failed -join ' ')"
    }

    # 非必需，永远返回成功。
    return $true
}

# 让 PSGallery 可非交互访问。这里任何一步失败都不致命 —— 真正的失败会在
# Install-Module 处体现，那里的错误信息更贴近问题本身。
function Initialize-DotPsRepository {
    try {
        # 旧版 .NET 默认可能不启用 TLS 1.2，PSGallery 只收 TLS 1.2+
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($repo -and $repo.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Verbose "PSGallery preparation skipped: $_"
    }
}
