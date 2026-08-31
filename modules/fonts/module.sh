#!/usr/bin/env sh
#
# Nerd Fonts 安装。
#
# 从发布包下载并解压，不 clone 字体源码仓库 —— 旧脚本为了拿几个 TTF
# 而 git clone 整个 adobe-fonts/source-code-pro（含全部历史与格式），
# 慢且浪费。
#
# 字体清单在 config/fonts/fonts.txt，新增字体不用改这里。
#
# shellcheck shell=sh

MODULE_DESC="Nerd Fonts (JetBrainsMono + Maple Mono NF)"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="core fonts"
# 无图形环境时装字体没有意义（SSH/CI/容器），由 runner 统一跳过
MODULE_NEEDS_GUI="1"

install() {
    _dot_f_manifest="$DOT_CONFIG_DIR/fonts/fonts.txt"

    if [ ! -f "$_dot_f_manifest" ]; then
        dot_error "font manifest not found: $_dot_f_manifest"
        return 1
    fi

    # 平台适配层必须已加载。缺了它 dot_platform_font_dir 会是
    # "command not found" —— 那只在 stderr 留一行，字体目录变成空串，
    # 模块却照样报成功。显式检查把这种情况变成明确的失败。
    if ! command -v dot_platform_font_dir >/dev/null 2>&1; then
        dot_error 'platform adapter not loaded (dot_platform_font_dir missing)'
        return 1
    fi

    # WSL 里装字体是无效的 —— 字体由 Windows 宿主机的终端渲染，
    # 装进 WSL 的 Linux 文件系统不会被 Windows Terminal 看到。
    if [ "$DOT_WSL" = 1 ]; then
        dot_skip 'running under WSL; fonts must be installed on the Windows host'
        dot_tip 'run bootstrap.ps1 on Windows to install fonts there'
        return 0
    fi

    _dot_f_dir=$(dot_platform_font_dir)
    if [ -z "$_dot_f_dir" ]; then
        dot_error 'platform did not report a font directory'
        return 1
    fi
    dot_info "font directory: $_dot_f_dir"

    _dot_f_total=0
    _dot_f_ok=0
    _dot_f_failed=''

    # 清单先读进变量，再用 here-doc 喂给循环 —— 直接 `done < manifest`
    # 会让循环体里的命令（curl/unzip 等）从同一个 stdin 读取并吃掉剩余行，
    # 导致清单只处理了前几项就静默结束。同 modules/modern-cli 的说明。
    _dot_f_lines=$(cat "$_dot_f_manifest")

    while IFS='|' read -r _dot_f_name _dot_f_url _dot_f_prefix _dot_f_filter; do
        case $_dot_f_name in
            '' | \#*) continue ;;
        esac
        if [ -z "$_dot_f_url" ] || [ -z "$_dot_f_prefix" ]; then
            dot_error "malformed manifest line for '$_dot_f_name' (need name|url|prefix)"
            _dot_f_failed="$_dot_f_failed $_dot_f_name"
            continue
        fi

        _dot_f_total=$((_dot_f_total + 1))

        if _dot_font_install_one "$_dot_f_name" "$_dot_f_url" "$_dot_f_prefix" \
            "$_dot_f_dir" "${_dot_f_filter:-}"; then
            _dot_f_ok=$((_dot_f_ok + 1))
        else
            # 单个字体失败不阻断其余 —— 一个 URL 挂了不该让整个字体模块失败
            _dot_f_failed="$_dot_f_failed $_dot_f_name"
        fi
    done <<EOF
$_dot_f_lines
EOF

    if [ -n "$_dot_f_failed" ]; then
        dot_error "failed fonts:$_dot_f_failed"
        # 全部失败与部分失败都返回非零（见函数末尾），这里只是把
        # 「一个都没装上」这种更严重的情形单独说清楚
        if [ "$_dot_f_ok" = 0 ]; then
            dot_error 'no font could be installed'
        else
            dot_info "$_dot_f_ok of $_dot_f_total fonts installed"
        fi
    fi

    # 有新字体落地才需要刷新缓存
    if [ "$_dot_f_ok" -gt 0 ]; then
        dot_platform_font_refresh
    fi

    _dot_font_terminal_hint

    # 有任何字体失败就返回非零。部分成功仍然是「不完整」的状态：
    # 用户请求装两个字体只装上一个，退出码报成功会让失败被忽略
    # （尤其在 CI 与无人值守的场景）。汇总里已经列出了具体哪个失败。
    if [ -n "$_dot_f_failed" ]; then
        return 1
    fi
}

# ---------------------------------------------------------------- 单个字体

_dot_font_install_one() {
    _dot_fi_name=$1
    _dot_fi_url=$2
    _dot_fi_prefix=$3
    _dot_fi_dir=$4
    _dot_fi_filter=${5:-}

    # 幂等：目标目录里已有该前缀的字体文件就跳过，不下载不复制
    if _dot_font_present "$_dot_fi_dir" "$_dot_fi_prefix"; then
        dot_skip "$_dot_fi_name already installed"
        return 0
    fi

    if dot_is_dry_run; then
        dot_info "[dry-run] would download $_dot_fi_name and install into $_dot_fi_dir"
        return 0
    fi

    dot_info "downloading $_dot_fi_name"

    _dot_fi_tmp=$(mktemp -d) || {
        dot_error "$_dot_fi_name: cannot create temp dir"
        return 1
    }
    _dot_fi_zip="$_dot_fi_tmp/font.zip"

    if ! _dot_font_download "$_dot_fi_url" "$_dot_fi_zip"; then
        dot_error "$_dot_fi_name: download failed ($_dot_fi_url)"
        rm -rf "$_dot_fi_tmp"
        return 1
    fi

    # 解压前必须校验归档有效 —— 下载可能拿到 HTML 错误页而非 zip，
    # 直接解压会产生难以诊断的错误，或把垃圾写进字体目录
    if ! _dot_font_verify_zip "$_dot_fi_zip"; then
        dot_error "$_dot_fi_name: downloaded file is not a valid zip archive"
        dot_error "  (got $(_dot_font_describe "$_dot_fi_zip"))"
        rm -rf "$_dot_fi_tmp"
        return 1
    fi

    if ! _dot_font_unzip "$_dot_fi_zip" "$_dot_fi_tmp/extracted"; then
        dot_error "$_dot_fi_name: extraction failed"
        rm -rf "$_dot_fi_tmp"
        return 1
    fi

    # 只装 ttf/otf。Nerd Fonts 的包里还有 readme、license 与 Windows 兼容版本，
    # 不需要全部拷进字体目录。
    _dot_fi_count=$(_dot_font_copy "$_dot_fi_tmp/extracted" "$_dot_fi_dir" "$_dot_fi_filter")

    rm -rf "$_dot_fi_tmp"

    if [ "$_dot_fi_count" = 0 ]; then
        dot_error "$_dot_fi_name: archive contained no font files"
        return 1
    fi

    dot_success "$_dot_fi_name installed ($_dot_fi_count files)"
}

# 目标目录里是否已有该前缀的字体
_dot_font_present() {
    [ -d "$1" ] || return 1
    # -maxdepth 1 —— 只看字体目录本身，不递归（某些系统下字体目录很大）
    [ -n "$(find "$1" -maxdepth 1 -name "$2*" \( -name '*.ttf' -o -name '*.otf' \) 2>/dev/null | head -n 1)" ]
}

_dot_font_download() {
    _dot_dl_url=$1
    _dot_dl_out=$2

    if command -v curl >/dev/null 2>&1; then
        # -L 跟随重定向（latest/download 一定会重定向）
        # -f 让 HTTP 错误码变成非零退出，否则错误页会被当成正常内容保存
        curl -fsSL --retry 2 --connect-timeout 20 -o "$_dot_dl_out" "$_dot_dl_url" </dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=20 -O "$_dot_dl_out" "$_dot_dl_url"
    else
        dot_error 'neither curl nor wget is available'
        return 1
    fi
}

# zip 的魔数是 PK\x03\x04。用 unzip -t 更彻底，但 unzip 不一定装了，
# 所以先看魔数，有 unzip 时再做完整性测试。
_dot_font_verify_zip() {
    _dot_vz=$1

    [ -s "$_dot_vz" ] || return 1

    _dot_vz_magic=$(dd if="$_dot_vz" bs=2 count=1 2>/dev/null | od -An -c | tr -d ' \n')
    case $_dot_vz_magic in
        PK*) ;;
        *) return 1 ;;
    esac

    if command -v unzip >/dev/null 2>&1; then
        unzip -tqq "$_dot_vz" >/dev/null 2>&1 || return 1
    fi
}

# 出错时说明拿到的是什么，便于诊断（常见情形：代理返回 HTML 登录页）
_dot_font_describe() {
    if command -v file >/dev/null 2>&1; then
        file -b "$1" 2>/dev/null | head -c 80
    else
        printf '%s bytes' "$(wc -c <"$1" | tr -d ' ')"
    fi
}

_dot_font_unzip() {
    _dot_uz_zip=$1
    _dot_uz_dst=$2

    mkdir -p "$_dot_uz_dst" || return 1

    if command -v unzip >/dev/null 2>&1; then
        unzip -qo "$_dot_uz_zip" -d "$_dot_uz_dst" >/dev/null 2>&1
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$_dot_uz_zip" -C "$_dot_uz_dst" >/dev/null 2>&1
    elif command -v python3 >/dev/null 2>&1; then
        # 兜底：最小容器里可能既没 unzip 也没 bsdtar，但通常有 python3
        python3 -c "
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
" "$_dot_uz_zip" "$_dot_uz_dst" >/dev/null 2>&1
    else
        dot_error 'no extraction tool available (need unzip, bsdtar or python3)'
        return 1
    fi
}

# 复制字体文件，回显复制了多少个。
# Nerd Fonts 的包里同时有普通版与 "Windows Compatible" 版，后者只是文件名
# 更短（老软件的限制），装一套就够 —— 两套都装会让字体菜单里出现重复项。
_dot_font_copy() {
    _dot_fc_src=$1
    _dot_fc_dst=$2
    _dot_fc_filter=${3:-}
    _dot_fc_n=0

    dot_mkdir "$_dot_fc_dst" >/dev/null 2>&1 || return 0

    # 有变体过滤时只取匹配的文件名，否则取包里全部字体。
    # 文件名可能含空格，所以用行分隔的列表文件 + while read。
    if [ -n "$_dot_fc_filter" ]; then
        find "$_dot_fc_src" -type f \( -name '*.ttf' -o -name '*.otf' \) \
            -name "${_dot_fc_filter}*" \
            ! -name '*Windows Compatible*' -print >"$_dot_fc_src/.fontlist" 2>/dev/null
    else
        find "$_dot_fc_src" -type f \( -name '*.ttf' -o -name '*.otf' \) \
            ! -name '*Windows Compatible*' -print >"$_dot_fc_src/.fontlist" 2>/dev/null
    fi

    while IFS= read -r _dot_fc_file; do
        [ -f "$_dot_fc_file" ] || continue
        if cp -f "$_dot_fc_file" "$_dot_fc_dst/" 2>/dev/null; then
            _dot_fc_n=$((_dot_fc_n + 1))
        fi
    done <"$_dot_fc_src/.fontlist"

    printf '%s' "$_dot_fc_n"
}

# ---------------------------------------------------------------- 终端指向

# 终端的字体设置多数无法可靠地用配置文件改（iTerm2 是 plist，Terminal.app
# 是私有格式，Windows Terminal 是 JSON 但路径随安装方式变）。
# 与其做不可靠的自动修改，不如明确告诉用户该设什么。
_dot_font_terminal_hint() {
    dot_tip 'set your terminal font to "JetBrainsMono Nerd Font" (or "Maple Mono NF" for CJK)'

    if [ "$DOT_OS" = macos ]; then
        dot_tip '  iTerm2: Settings > Profiles > Text > Font'
        dot_tip '  Terminal.app: Settings > Profiles > Text > Change...'
    fi
}
