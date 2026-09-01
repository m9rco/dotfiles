# PowerShell profile。Windows 侧与 config/zsh/ 的对位物。
#
# 与 zsh 侧共享同一份 config/starship.toml —— 那是三平台 prompt 一致的关键。
#
# 本机专属配置放 profile.local.ps1（不入库），在本文件末尾加载。

# ---------------------------------------------------------------- 仓库定位

# DOTFILES 由 win-shell 模块写进用户环境变量。
# 没有时从本文件位置反推（profile 是指向仓库的链接）。
if (-not $env:DOTFILES) {
    $link = Get-Item -LiteralPath $PROFILE.CurrentUserAllHosts -Force -ErrorAction SilentlyContinue
    if ($link -and $link.Target) {
        $target = if ($link.Target -is [array]) { $link.Target[0] } else { $link.Target }
        # config/powershell/profile.ps1 -> 上溯三层是仓库根
        $env:DOTFILES = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $target))
    }
}

# ---------------------------------------------------------------- 环境

$env:EDITOR = if ($env:EDITOR) { $env:EDITOR } else { 'code --wait' }

# UTF-8。Windows 控制台默认是本地代码页，中文与图标都会乱码。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------- PSReadLine
#
# 前缀历史搜索：输入几个字符后按上下键，只在匹配的历史里翻 ——
# 这是 zsh 侧 history-substring-search 的对位功能。

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine

    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # 行内预测（PSReadLine 2.1+）。旧版本没有这些参数，失败就跳过。
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    }
    catch {
        # PSReadLine 太旧，没有预测功能。这是可接受的降级，不是错误 ——
        # 显式写一句 Write-Verbose 而不是留空 catch，好让意图可见。
        Write-Verbose "PSReadLine prediction unavailable: $_"
    }

    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    # Ctrl-D 退出，与 Unix 习惯一致
    Set-PSReadLineKeyHandler -Key 'Ctrl+d' -Function DeleteCharOrExit
}

# ---------------------------------------------------------------- starship
#
# prompt 的真源是仓库里的 starship.toml。
# starship 缺失时不做任何事，用 PowerShell 默认 prompt。

if (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue) {
    if ($env:DOTFILES) {
        $env:STARSHIP_CONFIG = Join-Path $env:DOTFILES 'config\starship.toml'
    }
    Invoke-Expression (&starship init powershell)
}

# ---------------------------------------------------------------- 工具集成
#
# 每个都先查命令是否存在 —— 缺失的工具既不报错也不拖慢启动。

# zoxide：智能目录跳转，命令名 z（与 zsh 侧一致）
if (Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell --cmd z) -join "`n" })
}

# fzf：用 fd 作为文件来源
if (Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue) {
    if (Get-Command fd -CommandType Application -ErrorAction SilentlyContinue) {
        $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
    }
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border --info=inline'

    # PSFzf 提供 Ctrl-T / Ctrl-R 绑定；没装就只有 fzf 命令本身可用
    if (Get-Module -ListAvailable -Name PSFzf) {
        Import-Module PSFzf
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    }
}

# bat：作为 help 的 pager
if (Get-Command bat -CommandType Application -ErrorAction SilentlyContinue) {
    $env:BAT_THEME = if ($env:BAT_THEME) { $env:BAT_THEME } else { 'ansi' }
}

# ---------------------------------------------------------------- 别名
#
# 与 zsh 侧语义一致。PowerShell 的 ls 是 Get-ChildItem 的别名，
# 要用 Remove-Item alias: 才能覆盖。

if (Get-Command eza -CommandType Application -ErrorAction SilentlyContinue) {
    Remove-Item alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --group-directories-first @args }
    function ll { eza -l --group-directories-first --git @args }
    function la { eza -la --group-directories-first --git @args }
    function lt { eza --tree --level=2 @args }
}

# 不覆盖 cat —— 它会被管道大量使用，换成 bat 会引入分页与颜色
if (Get-Command bat -CommandType Application -ErrorAction SilentlyContinue) {
    function bcat { bat @args }
    function catp { bat --plain @args }
}

if (Get-Command rg -CommandType Application -ErrorAction SilentlyContinue) {
    function rgh { rg --hidden --no-ignore @args }
}

if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
    function gs { git status --short --branch @args }
    function gd { git diff @args }
    function gds { git diff --staged @args }
    function gl { git log --oneline --graph --decorate -20 @args }
}

if (Get-Command lazygit -CommandType Application -ErrorAction SilentlyContinue) {
    function lg { lazygit @args }
}

# 目录导航。PowerShell 里 .. 已可用，但 ... 需要定义。
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

function dotfiles { if ($env:DOTFILES) { Set-Location $env:DOTFILES } }

# ---------------------------------------------------------------- 本机覆盖
#
# 不入库。放工作项目路径、私有别名、单机环境变量。
# 必须最后加载才能覆盖前面的设置。

$localProfile = Join-Path (Split-Path -Parent $PROFILE.CurrentUserAllHosts) 'profile.local.ps1'
if (Test-Path -LiteralPath $localProfile) {
    . $localProfile
}
