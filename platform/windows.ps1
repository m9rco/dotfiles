# Windows 平台适配层。
#
# 把「在 Windows 上怎么做」收敛在这里，模块层不出现平台判断 ——
# 与 platform/macos.sh、platform/linux.sh 同一约定。
#
# 包管理器策略：scoop 优先，winget 兜底。
#   scoop  装 CLI 工具无需管理员、版本新、卸载干净
#   winget 用于 PowerShell 7、Windows Terminal 这类系统级应用
#
# 要求 PowerShell 5.1 起可用 —— 那是 Windows 自带的版本，
# 引导阶段不能假设 PowerShell 7 已经装好。

Set-StrictMode -Version Latest

# ---------------------------------------------------------------- 包名映射

# 逻辑名 -> scoop / winget 的包名。
# 返回 $null 表示该管理器没有这个包，由调用方走下一个方式。
function Get-DotPackageName {
    param(
        [Parameter(Mandatory = $true)][string]$Logical,
        [Parameter(Mandatory = $true)][ValidateSet('scoop', 'winget')][string]$Manager
    )

    # scoop 的包名与逻辑名大多一致；这里只列出不一致的。
    $scoopMap = @{
        'ripgrep'  = 'ripgrep'
        'fd'       = 'fd'
        'bat'      = 'bat'
        'eza'      = 'eza'
        'fzf'      = 'fzf'
        'zoxide'   = 'zoxide'
        'delta'    = 'delta'
        'jq'       = 'jq'
        'yq'       = 'yq'
        'gh'       = 'gh'
        'lazygit'  = 'lazygit'
        'starship' = 'starship'
        'atuin'    = 'atuin'
        'git'      = 'git'
        'gitleaks' = 'gitleaks'
        'ollama'   = 'ollama'
        'btop'     = 'btop'
        'dust'     = 'dust'
        'duf'      = 'duf'
        'procs'    = 'procs'
        'hyperfine' = 'hyperfine'
        'xh'       = 'xh'
        'sd'       = 'sd'
        'tldr'     = 'tealdeer'   # scoop 收的是 Rust 实现，命令仍是 tldr
        'zsh'      = $null   # Windows 原生没有 zsh —— 那是 WSL 的事
        # tmux 与 htop 是 Unix 终端/进程模型上的东西，Windows 原生没有对应物
        # （清单里它们标的是 "macos linux"，走不到这里；列出来是为了让
        # 「刻意不支持」和「忘了加」可区分）。
        'tmux'     = $null
        'htop'     = $null
    }

    # winget 用的是完整的包 ID
    $wingetMap = @{
        'pwsh'             = 'Microsoft.PowerShell'
        'windows-terminal' = 'Microsoft.WindowsTerminal'
        'git'              = 'Git.Git'
        'gh'               = 'GitHub.cli'
        'starship'         = 'Starship.Starship'
        'ripgrep'          = 'BurntSushi.ripgrep.MSVC'
        'fd'               = 'sharkdp.fd'
        'bat'              = 'sharkdp.bat'
        'fzf'              = 'junegunn.fzf'
        'jq'               = 'jqlang.jq'
        'delta'            = 'dandavison.delta'
        'lazygit'          = 'JesseDuffield.lazygit'
        'gitleaks'         = 'gitleaks.gitleaks'
        'ollama'           = 'Ollama.Ollama'
        'hyperfine'        = 'sharkdp.hyperfine'
        'xh'               = 'ducaale.xh'
        # 只列 winget 里确有的 ID。btop/dust/duf/procs/sd/tldr 走 scoop ——
        # 乱猜一个 ID 会让 winget 报 "no package found"，那比直接跳过更难排查。
        'zsh'              = $null
        'tmux'             = $null
        'htop'             = $null
    }

    switch ($Manager) {
        'scoop' {
            if ($scoopMap.ContainsKey($Logical)) { return $scoopMap[$Logical] }
            return $Logical
        }
        'winget' {
            if ($wingetMap.ContainsKey($Logical)) { return $wingetMap[$Logical] }
            return $null
        }
    }
}

# ---------------------------------------------------------------- 包安装

function Test-DotCommand {
    param([Parameter(Mandatory = $true)][string]$Name)
    # -CommandType Application 排除 alias 与 function ——
    # 与 Unix 侧「只认 PATH 里的可执行文件」保持一致的判定
    $null -ne (Get-Command $Name -CommandType Application, Cmdlet -ErrorAction SilentlyContinue)
}

# 安装单个包。先 scoop 后 winget。
function Install-DotPackage {
    param([Parameter(Mandatory = $true)][string]$Logical)

    if (Test-DotCommand $Logical) {
        Write-DotSkip "$Logical already available"
        return $true
    }

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would install $Logical"
        return $true
    }

    # scoop 优先
    if (Test-DotCommand 'scoop') {
        $pkg = Get-DotPackageName -Logical $Logical -Manager 'scoop'
        if ($pkg) {
            Write-DotInfo "installing $Logical via scoop ($pkg)"
            & scoop install $pkg 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-DotSuccess "installed $Logical via scoop"
                return $true
            }
            Write-DotInfo "scoop could not install $Logical; trying winget"
        }
    }

    # winget 兜底
    if (Test-DotCommand 'winget') {
        $pkg = Get-DotPackageName -Logical $Logical -Manager 'winget'
        if ($pkg) {
            Write-DotInfo "installing $Logical via winget ($pkg)"
            # --accept-*-agreements 避免卡在交互式条款确认上。
            # 参数放数组里而不是用反引号续行 —— 后者对解析器敏感
            # （见 test/lint_ps.sh 的 fragile constructs 检查）。
            $wingetArgs = @(
                'install', '--id', $pkg, '--exact', '--silent',
                '--accept-package-agreements', '--accept-source-agreements'
            )
            & winget @wingetArgs 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-DotSuccess "installed $Logical via winget"
                return $true
            }
        }
    }

    Write-DotError "could not install $Logical (tried scoop and winget)"
    return $false
}

# 确保 scoop 存在。它是无需管理员的安装器，是 Windows 侧的首选。
function Install-DotScoop {
    if (Test-DotCommand 'scoop') {
        Write-DotSkip 'scoop already installed'
        return $true
    }

    if ($script:DotDryRun) {
        Write-DotInfo '[dry-run] would install scoop'
        return $true
    }

    Write-DotStep 'Installing scoop'
    try {
        # scoop 要求执行策略至少是 RemoteSigned，且只改当前用户 ——
        # 改机器级策略需要管理员，也影响其他用户
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
        Write-DotSuccess 'scoop installed'
        return $true
    }
    catch {
        Write-DotError "scoop installation failed: $_"
        return $false
    }
}

# ---------------------------------------------------------------- 字体

# 用户级字体目录，无需管理员权限。
# DOT_FONT_DIR 可覆盖 —— 测试必须能把字体装到沙箱。
#
# LOCALAPPDATA 在真实 Windows 上总是存在；但在 macOS/Linux 上跑 pwsh 时
# 它是空的（本地开发时会遇到）。不加保护会让 Join-Path 收到 null 而抛出
# "Cannot bind argument to parameter 'Path'" —— 一个与真实问题无关的错误。
function Get-DotFontDir {
    if ($env:DOT_FONT_DIR) { return $env:DOT_FONT_DIR }
    if (-not $env:LOCALAPPDATA) {
        throw 'LOCALAPPDATA is not set — this module requires real Windows (set DOT_FONT_DIR to test elsewhere)'
    }
    Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
}

# Windows 需要把字体注册到注册表才能被应用枚举到。
# 写 HKCU 而不是 HKLM —— 后者要管理员权限。
function Register-DotFont {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$FaceName
    )

    $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would register font: $FaceName"
        return $true
    }

    try {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        # 值名要带字体类型后缀，值是字体文件的完整路径
        $valueName = "$FaceName (TrueType)"
        $regArgs = @{
            Path         = $regPath
            Name         = $valueName
            Value        = $Path
            PropertyType = 'String'
            Force        = $true
        }
        New-ItemProperty @regArgs | Out-Null
        return $true
    }
    catch {
        Write-DotError "failed to register font ${FaceName}: $_"
        return $false
    }
}

# Windows 没有 fc-cache；注册表写完后通知系统重新加载字体。
function Update-DotFontCache {
    if ($script:DotDryRun) { return $true }
    # 广播 WM_FONTCHANGE 让已运行的程序感知新字体。
    # 失败不致命 —— 重新登录一定会生效。
    try {
        Add-Type -Namespace DotFonts -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int SendMessageTimeout(
    System.IntPtr hWnd, int Msg, System.IntPtr wParam,
    System.IntPtr lParam, int fuFlags, int uTimeout, out System.IntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_FONTCHANGE = 0x001D
        $result = [IntPtr]::Zero
        [DotFonts.Native]::SendMessageTimeout(
            $HWND_BROADCAST, $WM_FONTCHANGE, [IntPtr]::Zero, [IntPtr]::Zero,
            2, 1000, [ref]$result) | Out-Null
    }
    catch {
        Write-DotTip 'could not broadcast WM_FONTCHANGE; new fonts appear after re-login'
    }
    return $true
}

# ---------------------------------------------------------------- PowerShell profile

# profile 的位置取决于跑的是 PowerShell 5.1 还是 7。
# 两者的 profile 路径不同，装到哪个取决于当前会话。
function Get-DotProfilePath {
    # $PROFILE.CurrentUserAllHosts 是 profile.ps1（对所有宿主生效），
    # 比 CurrentUserCurrentHost 更合适 —— 后者只对当前宿主（如 ISE）生效
    $PROFILE.CurrentUserAllHosts
}

# PowerShell 7 的 profile 目录（即使当前跑的是 5.1 也要能算出来），
# 这样在 5.1 下引导时可以顺带把 7 的 profile 也铺好。
function Get-DotPwsh7ProfileDir {
    Join-Path (Get-DotDocumentsDir) 'PowerShell'
}

function Get-DotPwsh5ProfileDir {
    Join-Path (Get-DotDocumentsDir) 'WindowsPowerShell'
}

# 文档目录。DOT_DOCUMENTS_DIR 可覆盖，供测试使用。
# GetFolderPath('MyDocuments') 在非 Windows 上返回空串，不加保护会让
# Join-Path 抛出与真实问题无关的 null 参数错误。
function Get-DotDocumentsDir {
    if ($env:DOT_DOCUMENTS_DIR) { return $env:DOT_DOCUMENTS_DIR }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) {
        throw 'MyDocuments is not resolvable — this module requires real Windows (set DOT_DOCUMENTS_DIR to test elsewhere)'
    }
    return $docs
}

# ---------------------------------------------------------------- Windows Terminal
#
# settings.json 里的字体/配色属于「配置内容」，真源放
# config/windows-terminal/settings.json；这里只放「怎么把那份内容并进用户已有的
# 设置」——与字体、profile 的分层保持一致。

# 现有 Windows Terminal settings.json 的位置。稳定版、预览版、以及非打包安装
# （scoop/zip）都查一遍，只返回实际存在的文件；一个都没有就返回空数组。
function Get-DotWindowsTerminalSettingsPaths {
    $paths = @()
    if (-not $env:LOCALAPPDATA) { return $paths }

    foreach ($pkg in @(
            'Microsoft.WindowsTerminal_8wekyb3d8bbwe',
            'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe')) {
        $candidate = Join-Path $env:LOCALAPPDATA "Packages\$pkg\LocalState\settings.json"
        if (Test-Path -LiteralPath $candidate) { $paths += $candidate }
    }

    $unpackaged = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'
    if (Test-Path -LiteralPath $unpackaged) { $paths += $unpackaged }

    return $paths
}

# 属性是否存在。StrictMode -Version Latest 下访问不存在的属性会抛异常，
# 而 settings.json 是用户文件，字段可有可无（schemes、profiles 都可能缺）。
function Test-DotJsonProperty {
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Object) { return $false }
    # 用索引器而不是 .PSObject.Properties.Name -contains：StrictMode 下对空对象
    # 做属性名枚举会抛「property 'Name' cannot be found」。
    return ($null -ne $Object.PSObject.Properties[$Name])
}

# 去掉 JSONC 注释（// 与 /* */），保留字符串字面量里的内容。
# 逐字符扫描而不是用正则 —— 字符串里的 // 是合法内容，正则会把它们也吃掉。
# 5.1 的 ConvertFrom-Json 不接受注释，而 Windows Terminal 的 settings.json 允许注释。
function Remove-DotJsonComments {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sb = New-Object System.Text.StringBuilder
    $len = $Text.Length
    $i = 0
    $inString = $false
    $escaped = $false

    while ($i -lt $len) {
        $c = $Text[$i]
        $nextChar = [char]0
        if ($i + 1 -lt $len) { $nextChar = $Text[$i + 1] }

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($c -eq '\') {
                $escaped = $true
            }
            elseif ($c -eq '"') {
                $inString = $false
            }
            $i++
            continue
        }

        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }

        # 行注释：跳到行尾，换行本身保留
        if ($c -eq '/' -and $nextChar -eq '/') {
            while ($i -lt $len -and $Text[$i] -ne "`n") { $i++ }
            continue
        }

        # 块注释：跳到闭合的 */
        if ($c -eq '/' -and $nextChar -eq '*') {
            $i += 2
            while ($i -lt $len) {
                if ($Text[$i] -eq '*' -and ($i + 1 -lt $len) -and $Text[$i + 1] -eq '/') { break }
                $i++
            }
            $i += 2
            continue
        }

        [void]$sb.Append($c)
        $i++
    }

    return $sb.ToString()
}

# 解析可能带注释的 JSON。先直接解析，失败再去注释重试。
function ConvertFrom-DotJson {
    param([Parameter(Mandatory = $true)][string]$Text)

    try {
        return ($Text | ConvertFrom-Json)
    }
    catch {
        $stripped = Remove-DotJsonComments -Text $Text
        return ($stripped | ConvertFrom-Json)
    }
}

# 把 config/windows-terminal/settings.json（fragment）并进一个 WT settings.json。
#
# 语义刻意保守，避免与用户已经做过的调整打架：
#   schemes           按 name 去重后追加（同名不覆盖）
#   profiles.defaults 只补缺失的键，用户设过的一律不动
#   defaultProfile    仅当当前还指向旧版 Windows PowerShell 时才迁移到 PowerShell 7
#
# 幂等：无变化则不写、不备份。写前备份 —— 重写会丢注释，原文留在备份里。
function Merge-DotWindowsTerminalSettings {
    param(
        [Parameter(Mandatory = $true)][string]$SettingsPath,
        [Parameter(Mandatory = $true)][string]$FragmentPath
    )

    if (-not (Test-Path -LiteralPath $FragmentPath)) {
        Write-DotError "terminal fragment not found: $FragmentPath"
        return $false
    }

    $raw = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $raw) {
        Write-DotError "cannot read $SettingsPath"
        return $false
    }

    $settings = $null
    try {
        $settings = ConvertFrom-DotJson -Text $raw
    }
    catch {
        Write-DotError "cannot parse ${SettingsPath} as JSON: $_"
        Write-DotTip 'leaving the file untouched'
        return $false
    }

    $fragment = ConvertFrom-DotJson -Text (Get-Content -LiteralPath $FragmentPath -Raw)
    $changed = $false

    # --- schemes ---
    if (Test-DotJsonProperty -Object $fragment -Name 'schemes') {
        if (-not (Test-DotJsonProperty -Object $settings -Name 'schemes')) {
            $settings | Add-Member -NotePropertyName 'schemes' -NotePropertyValue @() -Force
        }
        $existing = @()
        foreach ($s in @($settings.schemes)) {
            if (Test-DotJsonProperty -Object $s -Name 'name') { $existing += $s.name }
        }
        foreach ($scheme in @($fragment.schemes)) {
            if ($existing -contains $scheme.name) {
                Write-DotSkip "color scheme already present: $($scheme.name)"
                continue
            }
            $settings.schemes = @($settings.schemes) + $scheme
            $changed = $true
            Write-DotInfo "adding color scheme: $($scheme.name)"
        }
    }

    # --- profiles.defaults ---
    $fragmentDefaults = $null
    if ((Test-DotJsonProperty -Object $fragment -Name 'profiles') -and
        (Test-DotJsonProperty -Object $fragment.profiles -Name 'defaults')) {
        $fragmentDefaults = $fragment.profiles.defaults
    }
    if ($null -ne $fragmentDefaults) {
        if (-not (Test-DotJsonProperty -Object $settings -Name 'profiles')) {
            $settings | Add-Member -NotePropertyName 'profiles' -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not (Test-DotJsonProperty -Object $settings.profiles -Name 'defaults')) {
            $settings.profiles | Add-Member -NotePropertyName 'defaults' -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        foreach ($prop in $fragmentDefaults.PSObject.Properties) {
            $key = $prop.Name
            if ($null -ne $settings.profiles.defaults.PSObject.Properties[$key]) {
                Write-DotSkip "terminal default already set, keeping it: $key"
                continue
            }
            $settings.profiles.defaults | Add-Member -NotePropertyName $key -NotePropertyValue $prop.Value -Force
            $changed = $true
            Write-DotInfo "setting terminal default: $key"
        }
    }

    # --- defaultProfile：只做「旧版 Windows PowerShell -> PowerShell 7」的迁移 ---
    $legacyWindowsPs = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
    if ((Test-DotJsonProperty -Object $fragment -Name 'defaultProfile') -and
        (Test-DotJsonProperty -Object $settings -Name 'defaultProfile') -and
        $settings.defaultProfile -eq $legacyWindowsPs) {
        $settings.defaultProfile = $fragment.defaultProfile
        $changed = $true
        Write-DotInfo 'default terminal profile: Windows PowerShell -> PowerShell 7'
    }

    if (-not $changed) {
        Write-DotSkip "terminal settings already up to date: $SettingsPath"
        return $true
    }

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would update $SettingsPath"
        return $true
    }

    if (-not (Backup-DotPath $SettingsPath)) { return $false }

    $json = $settings | ConvertTo-Json -Depth 32
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($SettingsPath, $json, $utf8)
        Write-DotSuccess "updated $SettingsPath"
        return $true
    }
    catch {
        Write-DotError "failed to write ${SettingsPath}: $_"
        return $false
    }
}
