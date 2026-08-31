# PowerShell 侧的共享函数：日志、平台探测、幂等文件操作。
#
# 与 lib/log.sh + lib/detect.sh + lib/fs.sh 对应，语义保持一致 ——
# 尤其是 dot_link 的四种情形与备份行为，那是两侧都不能妥协的部分。
#
# 必须能在 PowerShell 5.1 下工作：不用 ?? 运算符、不用 ternary、
# 不用 5.1 之后才有的 cmdlet。

Set-StrictMode -Version Latest

# ---------------------------------------------------------------- 日志
#
# 非终端时禁用颜色（重定向、CI）。与 Unix 侧同一判定思路。

$script:DotUseColor = $true
if ($env:NO_COLOR -or $env:DOT_NO_COLOR -or -not [Environment]::UserInteractive) {
    $script:DotUseColor = $false
}

function Write-DotLine {
    param([string]$Prefix, [string]$Message, [string]$Color)
    if ($script:DotUseColor -and $Color) {
        Write-Host "$Prefix " -NoNewline -ForegroundColor $Color
        Write-Host $Message -ForegroundColor $Color
    }
    else {
        Write-Host "$Prefix $Message"
    }
}

function Write-DotStep { param([string]$Message) Write-Host ''; Write-DotLine '==>' $Message 'Yellow' }
function Write-DotInfo { param([string]$Message) Write-DotLine '  ->' $Message 'Cyan' }
function Write-DotSuccess { param([string]$Message) Write-DotLine '  ok' $Message 'Green' }
function Write-DotError { param([string]$Message) Write-DotLine '  !!' $Message 'Red' }
function Write-DotTip { param([string]$Message) Write-DotLine '  ..' $Message 'Magenta' }
function Write-DotSkip { param([string]$Message) Write-DotLine '  --' $Message 'DarkGray' }

# ---------------------------------------------------------------- 平台探测
#
# 输出与 Unix 侧同名的 DOT_* 变量，使模块两侧看到同一套契约。
# 探测零副作用 —— -Info 可以安全调用。

function Invoke-DotDetect {
    $script:DotOS = 'windows'

    # 架构。PROCESSOR_ARCHITECTURE 只在 Windows 上存在 ——
    # 在 macOS/Linux 上跑 pwsh 时它是空的，那时用 .NET 的运行时架构，
    # 否则会把 arm64 机器误报成 x86_64（本地测试时就会看到）。
    $archRaw = $env:PROCESSOR_ARCHITECTURE
    if (-not $archRaw) {
        $archRaw = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    }
    switch -Regex ($archRaw) {
        '^(AMD64|X64)$' { $script:DotArch = 'x86_64' }
        '^ARM64$' { $script:DotArch = 'arm64' }
        '^(x86|X86)$' { $script:DotArch = 'x86' }
        default { $script:DotArch = 'x86_64' }
    }

    # 包管理器：scoop 优先，winget 兜底。都没有则标记为待安装。
    $script:DotPkgMissing = $false
    if (Test-DotCommand 'scoop') {
        $script:DotPkg = 'scoop'
    }
    elseif (Test-DotCommand 'winget') {
        $script:DotPkg = 'winget'
    }
    else {
        $script:DotPkg = 'scoop'
        $script:DotPkgMissing = $true
    }

    # Windows 原生不是 WSL。（WSL 里跑的是 bootstrap.sh，DOT_WSL 由那边判定。）
    $script:DotWSL = 0

    # headless：CI，或没有交互式桌面。
    # Windows 上没有 SSH_CONNECTION 那样统一的信号，主要看 CI。
    if ($env:CI -or -not [Environment]::UserInteractive) {
        $script:DotHeadless = 1
    }
    else {
        $script:DotHeadless = 0
    }

    # PowerShell 版本：决定 profile 路径与部分能力
    $script:DotPSVersion = $PSVersionTable.PSVersion.ToString()
    $script:DotPSMajor = $PSVersionTable.PSVersion.Major

    # 供子进程使用
    $env:DOT_OS = $script:DotOS
    $env:DOT_ARCH = $script:DotArch
    $env:DOT_PKG = $script:DotPkg
    $env:DOT_WSL = $script:DotWSL
    $env:DOT_HEADLESS = $script:DotHeadless
}

# 打印探测结果。零副作用，供 -Info 与 CI 验证使用。
# 输出格式与 Unix 侧的 dot_detect_info 对齐，便于同一套 CI 断言复用。
function Show-DotDetect {
    $pkgNote = ''
    if ($script:DotPkgMissing) { $pkgNote = ' (not installed yet)' }

    Write-Output ('DOT_OS           {0}' -f $script:DotOS)
    Write-Output ('DOT_ARCH         {0}' -f $script:DotArch)
    Write-Output ('DOT_DISTRO       {0}' -f '(n/a)')
    Write-Output ('DOT_PKG          {0}{1}' -f $script:DotPkg, $pkgNote)
    Write-Output ('DOT_WSL          {0}' -f $script:DotWSL)
    Write-Output ('DOT_HEADLESS     {0}' -f $script:DotHeadless)
    Write-Output ('DOT_PS_VERSION   {0}' -f $script:DotPSVersion)
}

# ---------------------------------------------------------------- 文件操作
#
# 与 lib/fs.sh 的 dot_link 完全同语义：
#   1. 已是指向 SRC 的链接      -> 跳过
#   2. 真实文件/目录            -> 先备份再建链接
#   3. 指向他处的链接           -> 直接替换（链接本身无内容）
#   4. 父目录不存在             -> 先创建

# 家目录。
#
# 不能直接用 $HOME —— 它在 PowerShell 里是只读变量，测试无法覆盖它
# （实测报 "Cannot overwrite variable HOME because it is read-only"）。
# 用 DOT_HOME 作为可覆盖入口，否则取平台的用户目录：
# Windows 上是 USERPROFILE，非 Windows 上 pwsh 会设置 HOME。
function Get-DotHome {
    if ($env:DOT_HOME) { return $env:DOT_HOME }
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    return [Environment]::GetFolderPath('UserProfile')
}

$script:DotBackupRoot = if ($env:DOT_BACKUP_ROOT) {
    $env:DOT_BACKUP_ROOT
}
else {
    Join-Path (Get-DotHome) '.dotfiles-backup'
}
$script:DotBackupDir = $null

function Get-DotBackupDir {
    if (-not $script:DotBackupDir) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:DotBackupDir = Join-Path $script:DotBackupRoot $stamp
    }
    $script:DotBackupDir
}

function New-DotDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) { return $true }

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would create directory $Path"
        return $true
    }

    try {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $true
    }
    catch {
        Write-DotError "failed to create ${Path}: $_"
        return $false
    }
}

# 把 Path 移进本次引导的备份目录，保留相对家目录的路径结构。
function Backup-DotPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $backupDir = Get-DotBackupDir
    # 变量名不能叫 $home —— PowerShell 变量名大小写不敏感，
    # 会撞上只读的 $HOME 而赋值失败
    $userHome = Get-DotHome

    # 计算相对家目录的路径
    if ($Path.StartsWith($userHome, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $Path.Substring($userHome.Length).TrimStart('\', '/')
    }
    else {
        # 家目录之外的路径：去掉盘符与前导分隔符，否则 Join-Path 会得到
        # 一个仍然是绝对路径的字符串，备份就落到了原地而不是备份目录里
        $rel = '_abs\' + ($Path -replace '^[A-Za-z]:', '' -replace '^[\\/]+', '')
    }
    $dest = Join-Path $backupDir $rel

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would back up $Path -> $dest"
        return $true
    }

    $destParent = Split-Path -Parent $dest
    if (-not (New-DotDirectory $destParent)) { return $false }

    try {
        Move-Item -LiteralPath $Path -Destination $dest -Force
        Write-DotInfo "backed up $Path -> $dest"
        return $true
    }
    catch {
        Write-DotError "failed to back up ${Path}: $_"
        return $false
    }
}

# 目标是否是符号链接。
# 5.1 没有 -PathType Link，用 Attributes 判断 ReparsePoint。
function Test-DotSymlink {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-DotSymlinkTarget {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    # PowerShell 5.1 用 .Target，7 也兼容
    if ($item.PSObject.Properties.Name -contains 'Target' -and $item.Target) {
        if ($item.Target -is [array]) { return $item.Target[0] }
        return $item.Target
    }
    return $null
}

# New-DotLink SRC DST —— 幂等地把 DST 建成指向 SRC 的符号链接。
#
# Windows 上创建符号链接默认需要管理员或开发者模式。检测失败时退回
# 硬链接（文件）或目录联接（目录）—— 两者都不需要提权，
# 对配置文件而言效果等价。
function New-DotLink {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-DotError "link source does not exist: $Source"
        return $false
    }

    $sourceIsDir = Test-Path -LiteralPath $Source -PathType Container

    # 情形 1 / 3：目标已是链接
    if (Test-DotSymlink $Target) {
        $current = Get-DotSymlinkTarget $Target
        if ($current -and ($current.TrimEnd('\', '/') -eq $Source.TrimEnd('\', '/'))) {
            Write-DotSkip "already linked: $Target"
            return $true
        }
        if ($script:DotDryRun) {
            Write-DotInfo "[dry-run] would relink $Target ($current -> $Source)"
        }
        else {
            try {
                # 目录联接不能用 Remove-Item -Recurse（会删目标内容），
                # 对 reparse point 要用 -Force 但不递归
                Remove-Item -LiteralPath $Target -Force -ErrorAction Stop
                Write-DotInfo "replacing link $Target (was -> $current)"
            }
            catch {
                Write-DotError "failed to remove existing link ${Target}: $_"
                return $false
            }
        }
    }
    # 情形 2：真实文件或目录 -> 必须先备份
    elseif (Test-Path -LiteralPath $Target) {
        if (-not (Backup-DotPath $Target)) { return $false }
    }

    # 情形 4：父目录
    $parent = Split-Path -Parent $Target
    if ($parent -and -not (New-DotDirectory $parent)) { return $false }

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would link $Target -> $Source"
        return $true
    }

    # 先试符号链接
    try {
        New-Item -ItemType SymbolicLink -Path $Target -Value $Source -Force -ErrorAction Stop | Out-Null
        Write-DotSuccess "linked $Target -> $Source"
        return $true
    }
    catch {
        Write-DotTip 'symlink creation failed (needs admin or Developer Mode); falling back'
    }

    # 退回：目录用 Junction，文件用 HardLink。都不需要提权。
    try {
        if ($sourceIsDir) {
            New-Item -ItemType Junction -Path $Target -Value $Source -Force -ErrorAction Stop | Out-Null
            Write-DotSuccess "junction $Target -> $Source"
        }
        else {
            New-Item -ItemType HardLink -Path $Target -Value $Source -Force -ErrorAction Stop | Out-Null
            Write-DotSuccess "hardlink $Target -> $Source"
        }
        return $true
    }
    catch {
        Write-DotError "could not link $Target -> ${Source}: $_"
        Write-DotTip 'enable Developer Mode in Windows Settings to allow symlinks'
        return $false
    }
}

# 幂等写文件：内容相同则不动。
function Set-DotFileContent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existing = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        if ($null -ne $existing -and $existing -eq $Content) {
            Write-DotSkip "unchanged: $Path"
            return $true
        }
    }

    if ($script:DotDryRun) {
        Write-DotInfo "[dry-run] would write $Path"
        return $true
    }

    # 已存在且不是链接 -> 先备份
    if ((Test-Path -LiteralPath $Path) -and -not (Test-DotSymlink $Path)) {
        if (-not (Backup-DotPath $Path)) { return $false }
    }

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (New-DotDirectory $parent)) { return $false }

    try {
        # 用 UTF8 无 BOM：带 BOM 会让部分工具解析失败
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($Path, $Content, $utf8)
        Write-DotSuccess "wrote $Path"
        return $true
    }
    catch {
        Write-DotError "failed to write ${Path}: $_"
        return $false
    }
}

function Show-DotBackupSummary {
    if ($script:DotBackupDir -and (Test-Path -LiteralPath $script:DotBackupDir)) {
        Write-DotTip "replaced files were backed up to $script:DotBackupDir"
    }
}
