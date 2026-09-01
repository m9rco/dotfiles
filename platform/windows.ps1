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
