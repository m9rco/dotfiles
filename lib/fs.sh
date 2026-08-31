#!/usr/bin/env sh
#
# 幂等的文件系统原语。所有模块的写操作都必须经过这里 ——
# 直接 ln/rm/mv 会绕过备份与 dry-run，这是旧脚本最危险的地方：
# 旧 lnif() 直接 `rm -rf "$2"`，会无声吞掉用户已有的真实配置文件。
#
# dot_link 的四种情形：
#   1. DST 已是指向 SRC 的链接      -> 跳过（幂等）
#   2. DST 是真实文件/目录          -> 先备份到 ~/.dotfiles-backup/<ts>/ 再建链接
#   3. DST 是指向他处的符号链接      -> 直接替换（链接本身无内容，无需备份）
#   4. DST 父目录不存在             -> 先创建父目录
#
# shellcheck shell=sh

[ -n "${DOT_FS_SH_LOADED:-}" ] && return 0
DOT_FS_SH_LOADED=1

# shellcheck source=lib/log.sh
. "${DOT_LIB_DIR:-$(dirname -- "$0")}/log.sh"

# 备份根目录。同一次引导内所有备份共用一个时间戳目录，便于整批恢复。
# 时间戳惰性生成 —— 没有实际备份发生时不创建任何目录。
DOT_BACKUP_ROOT=${DOT_BACKUP_ROOT:-$HOME/.dotfiles-backup}
DOT_BACKUP_DIR=''

# 确保 DOT_BACKUP_DIR 已就绪。必须直接赋值而不能走命令替换 ——
# $(...) 会在子 shell 里执行，赋值将丢失，导致每次备份各自生成时间戳
# （跨秒时会散落到不同目录），且 dot_backup_summary 永远看不到它。
_dot_backup_dir_init() {
    [ -n "$DOT_BACKUP_DIR" ] && return 0
    DOT_BACKUP_DIR="$DOT_BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
}

# dry-run 下只打印计划，不落盘。
_dot_would() {
    dot_info "[dry-run] $*"
}

dot_is_dry_run() {
    [ "${DOT_DRY_RUN:-0}" = 1 ]
}

# ---------------------------------------------------------------- 目录

# 幂等创建目录（含父级）。
dot_mkdir() {
    _dot_mkdir_path=$1

    if [ -d "$_dot_mkdir_path" ]; then
        return 0
    fi

    if dot_is_dry_run; then
        _dot_would "mkdir -p $_dot_mkdir_path"
        return 0
    fi

    if ! mkdir -p "$_dot_mkdir_path"; then
        dot_error "failed to create directory: $_dot_mkdir_path"
        return 1
    fi
}

# ---------------------------------------------------------------- 备份

# 把 PATH 移入本次引导的备份目录，保留其相对 $HOME 的路径结构，
# 这样恢复时能一眼看出原位置（~/.config/foo/bar -> backup/.config/foo/bar）。
dot_backup() {
    _dot_bk_path=$1

    _dot_backup_dir_init

    # 计算相对 $HOME 的路径；$HOME 之外的路径按其绝对路径去掉前导 / 存放
    case $_dot_bk_path in
        "$HOME"/*) _dot_bk_rel=${_dot_bk_path#"$HOME"/} ;;
        /*) _dot_bk_rel="_abs${_dot_bk_path}" ;;
        *) _dot_bk_rel=$_dot_bk_path ;;
    esac

    _dot_bk_dest="$DOT_BACKUP_DIR/$_dot_bk_rel"

    if dot_is_dry_run; then
        _dot_would "backup $_dot_bk_path -> $_dot_bk_dest"
        return 0
    fi

    dot_mkdir "$(dirname -- "$_dot_bk_dest")" || return 1

    if ! mv "$_dot_bk_path" "$_dot_bk_dest"; then
        dot_error "failed to back up $_dot_bk_path"
        return 1
    fi

    dot_info "backed up $_dot_bk_path -> $_dot_bk_dest"
}

# ---------------------------------------------------------------- 链接

# dot_link SRC DST —— 幂等地把 DST 建成指向 SRC 的符号链接。
dot_link() {
    _dot_ln_src=$1
    _dot_ln_dst=$2

    if [ ! -e "$_dot_ln_src" ]; then
        dot_error "link source does not exist: $_dot_ln_src"
        return 1
    fi

    # 情形 1：已是指向 SRC 的链接 -> 跳过。
    # 用 -h 判断链接本身（-e 会跟随链接，断链会被误判为不存在）。
    if [ -h "$_dot_ln_dst" ]; then
        _dot_ln_cur=$(readlink "$_dot_ln_dst")
        if [ "$_dot_ln_cur" = "$_dot_ln_src" ]; then
            dot_skip "already linked: $_dot_ln_dst"
            return 0
        fi

        # 情形 3：指向他处的链接 -> 直接替换，无需备份（链接本身无内容）
        if dot_is_dry_run; then
            _dot_would "relink $_dot_ln_dst: $_dot_ln_cur -> $_dot_ln_src"
        else
            if ! rm -f "$_dot_ln_dst"; then
                dot_error "failed to remove existing symlink: $_dot_ln_dst"
                return 1
            fi
            dot_info "replacing symlink $_dot_ln_dst (was -> $_dot_ln_cur)"
        fi

    # 情形 2：真实文件或目录 -> 必须先备份，绝不能无声删除用户内容
    elif [ -e "$_dot_ln_dst" ]; then
        dot_backup "$_dot_ln_dst" || return 1
    fi

    # 情形 4：父目录不存在则创建
    dot_mkdir "$(dirname -- "$_dot_ln_dst")" || return 1

    if dot_is_dry_run; then
        _dot_would "ln -s $_dot_ln_src $_dot_ln_dst"
        return 0
    fi

    if ! ln -s "$_dot_ln_src" "$_dot_ln_dst"; then
        dot_error "failed to link $_dot_ln_dst -> $_dot_ln_src"
        return 1
    fi

    dot_success "linked $_dot_ln_dst -> $_dot_ln_src"
}

# ---------------------------------------------------------------- 写文件

# 幂等写文件：内容相同则不动（避免无意义的 mtime 变更，也让"重复执行零变更"成立）。
# 内容从 stdin 读入。
dot_write() {
    _dot_wr_path=$1
    _dot_wr_mode=${2:-}

    _dot_wr_tmp=$(mktemp) || {
        dot_error "failed to create temp file"
        return 1
    }
    cat >"$_dot_wr_tmp"

    if [ -f "$_dot_wr_path" ] && cmp -s "$_dot_wr_tmp" "$_dot_wr_path"; then
        rm -f "$_dot_wr_tmp"
        dot_skip "unchanged: $_dot_wr_path"
        return 0
    fi

    if dot_is_dry_run; then
        rm -f "$_dot_wr_tmp"
        _dot_would "write $_dot_wr_path"
        return 0
    fi

    # 目标已存在且是用户的真实文件 -> 先备份
    if [ -e "$_dot_wr_path" ] && [ ! -h "$_dot_wr_path" ]; then
        dot_backup "$_dot_wr_path" || {
            rm -f "$_dot_wr_tmp"
            return 1
        }
    fi

    dot_mkdir "$(dirname -- "$_dot_wr_path")" || {
        rm -f "$_dot_wr_tmp"
        return 1
    }

    if ! mv "$_dot_wr_tmp" "$_dot_wr_path"; then
        dot_error "failed to write $_dot_wr_path"
        rm -f "$_dot_wr_tmp"
        return 1
    fi

    # mktemp 的默认权限是 600，非敏感文件需要放宽到常规权限
    if [ -n "$_dot_wr_mode" ]; then
        chmod "$_dot_wr_mode" "$_dot_wr_path"
    else
        chmod 644 "$_dot_wr_path"
    fi

    dot_success "wrote $_dot_wr_path"
}

# 报告本次是否产生了备份，供汇总输出使用。
dot_backup_summary() {
    [ -n "$DOT_BACKUP_DIR" ] && [ -d "$DOT_BACKUP_DIR" ] || return 0
    dot_tip "replaced files were backed up to $DOT_BACKUP_DIR"
}
