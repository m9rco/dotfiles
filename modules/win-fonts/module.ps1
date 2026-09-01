# Nerd Fonts（Windows 侧）。
#
# 读同一份 config/fonts/fonts.txt。Windows 与 Unix 的差别在于：
# 字体文件落地后还要写用户注册表才能被应用枚举到（写 HKCU 免提权）。

$DotModule = @{
    Description = 'Nerd Fonts (JetBrainsMono + Maple Mono NF)'
    Platforms   = @('windows')
    Tags        = @('core', 'fonts')
    NeedsGui    = $true
}

function Install-DotModule {
    $manifest = Join-Path $script:DotConfigDir 'fonts\fonts.txt'
    if (-not (Test-Path -LiteralPath $manifest)) {
        Write-DotError "font manifest not found: $manifest"
        return $false
    }

    $fontDir = Get-DotFontDir
    Write-DotInfo "font directory: $fontDir"

    $ok = 0
    $failed = @()

    foreach ($line in (Get-Content -LiteralPath $manifest)) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        $parts = $line.Split('|')
        if ($parts.Count -lt 3) {
            Write-DotError "malformed manifest line: $line"
            $failed += $line
            continue
        }

        $name = $parts[0].Trim()
        $url = $parts[1].Trim()
        $prefix = $parts[2].Trim()
        $filter = if ($parts.Count -ge 4) { $parts[3].Trim() } else { '' }

        if (Install-DotFontFromUrl -Name $name -Url $url -Prefix $prefix -Filter $filter -FontDir $fontDir) {
            $ok++
        }
        else {
            $failed += $name
        }
    }

    if ($ok -gt 0) { Update-DotFontCache | Out-Null }

    Write-DotTip 'set your terminal font to "JetBrainsMono Nerd Font" (or "Maple Mono NF" for CJK)'

    if ($failed.Count -gt 0) {
        Write-DotError "failed fonts: $($failed -join ' ')"
        # 与 Unix 侧一致：部分失败也返回非零，避免缺字体被忽略
        return $false
    }
    return $true
}

function Install-DotFontFromUrl {
    param(
        [string]$Name, [string]$Url, [string]$Prefix,
        [string]$Filter, [string]$FontDir
    )

    # 幂等：目标目录里已有该前缀的字体就跳过
    if (Test-Path -LiteralPath $FontDir) {
        $existing = Get-ChildItem -LiteralPath $FontDir -Filter "$Prefix*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.ttf', '.otf') }
        if ($existing) {
            Write-DotSkip "$Name already installed"
            return $true
        }
    }

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would download $Name and install into $FontDir"
        return $true
    }

    Write-DotInfo "downloading $Name"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dotfont-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'font.zip'

    try {
        # TLS 1.2 必须显式启用 —— PowerShell 5.1 默认可能仍是 TLS 1.0，
        # GitHub 已不接受，表现为难以理解的连接失败
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-DotError "${Name}: download failed — $_"
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # 解压前校验是有效归档 —— 下载可能拿到 HTML 错误页
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $extract = Join-Path $tmp 'extracted'
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
    }
    catch {
        Write-DotError "${Name}: downloaded file is not a valid zip archive"
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    if (-not (New-DotDirectory $FontDir)) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # 只装 ttf/otf，排除 Windows Compatible 变体（文件名短的重复版本）
    $fonts = Get-ChildItem -LiteralPath $extract -Recurse -File |
        Where-Object { $_.Extension -in @('.ttf', '.otf') } |
        Where-Object { $_.Name -notlike '*Windows Compatible*' }

    if ($Filter) {
        $fonts = $fonts | Where-Object { $_.Name -like "$Filter*" }
    }

    $count = 0
    foreach ($f in $fonts) {
        $dest = Join-Path $FontDir $f.Name
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        # 注册表里的 face name 用不带扩展名的文件名
        Register-DotFont -Path $dest -FaceName ([IO.Path]::GetFileNameWithoutExtension($f.Name)) | Out-Null
        $count++
    }

    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

    if ($count -eq 0) {
        Write-DotError "${Name}: archive contained no matching font files"
        return $false
    }

    Write-DotSuccess "$Name installed ($count files)"
    return $true
}
