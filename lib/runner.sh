#!/usr/bin/env sh
#
# 模块运行器：发现、校验、排序、过滤、执行、汇总。
#
# 模块清单的唯一来源是文件系统（modules/*/module.sh）—— 不存在中心清单。
# 旧 install.sh 每加一个任务要改三处（函数、usage() 文案、case 分支），
# 结果 usage() 里写着 zsh_rc 而 case 分支实际是 zsh_omz，两处已经漂移。
#
# POSIX sh 没有数组，模块状态用空格分隔的字符串累积。模块名限制为
# [A-Za-z0-9_-]，因此不会有空格歧义。
#
# shellcheck shell=sh

[ -n "${DOT_RUNNER_SH_LOADED:-}" ] && return 0
DOT_RUNNER_SH_LOADED=1

_dot_runner_lib=${DOT_LIB_DIR:-$(dirname -- "$0")}
# shellcheck source=lib/log.sh
. "$_dot_runner_lib/log.sh"
# shellcheck source=lib/fs.sh
. "$_dot_runner_lib/fs.sh"
# 下载原语。pkg.sh 经由 release.sh 也会 source 它，但 fonts 模块直接用
# 这些函数，不该依赖「另一个 lib 恰好把它带进来」这种间接关系。
# shellcheck source=lib/download.sh
. "$_dot_runner_lib/download.sh"
# shellcheck source=lib/pkg.sh
. "$_dot_runner_lib/pkg.sh"

DOT_MODULES_DIR=${DOT_MODULES_DIR:-$_dot_runner_lib/../modules}

# 发现到的全部模块名
DOT_ALL_MODULES=''
# 执行结果分类
DOT_RUN_OK=''
DOT_RUN_FAILED=''
DOT_RUN_SKIPPED=''

# ---------------------------------------------------------------- 发现与校验

# 单引号包裹，内部单引号转义 —— 使值能安全地被 eval。
_dot_q() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# 在子 shell 中读取模块元数据并回显为可 eval 的赋值，
# 使模块文件里的变量与函数不污染 runner 自身的命名空间。
_dot_module_meta() {
    _dot_mm_name=$1
    _dot_mm_file="$DOT_MODULES_DIR/$_dot_mm_name/module.sh"

    (
        MODULE_DESC=''
        MODULE_PLATFORMS=''
        MODULE_TAGS=''
        MODULE_REQUIRES=''
        MODULE_NEEDS_GUI=''
        # shellcheck disable=SC1090
        . "$_dot_mm_file" || exit 1

        # install() 必须存在且必须是 shell 函数。
        # 不能只用 `command -v install` —— /usr/bin/install 是标准工具，
        # 它的存在会让缺少 install() 的模块通过校验。函数的 command -v 输出
        # 是裸名字，外部命令则是路径，据此区分（sh/dash/bash 行为一致）。
        if [ "$(command -v install 2>/dev/null)" != install ]; then
            printf 'MODULE_INVALID="missing install() function"\n'
            exit 0
        fi

        for _f in DESC PLATFORMS TAGS; do
            eval "_v=\$MODULE_$_f"
            if [ -z "$_v" ]; then
                printf 'MODULE_INVALID="missing MODULE_%s"\n' "$_f"
                exit 0
            fi
        done

        printf 'MODULE_DESC=%s\n' "$(_dot_q "$MODULE_DESC")"
        printf 'MODULE_PLATFORMS=%s\n' "$(_dot_q "$MODULE_PLATFORMS")"
        printf 'MODULE_TAGS=%s\n' "$(_dot_q "$MODULE_TAGS")"
        printf 'MODULE_REQUIRES=%s\n' "$(_dot_q "$MODULE_REQUIRES")"
        printf 'MODULE_NEEDS_GUI=%s\n' "$(_dot_q "$MODULE_NEEDS_GUI")"
        printf 'MODULE_INVALID=""\n'
    )
}

# 扫描 modules/ 发现全部模块。任一模块不合规即报错终止 ——
# 不合规的模块意味着安装逻辑有笔误，静默跳过会让用户以为装了其实没装。
dot_runner_discover() {
    DOT_ALL_MODULES=''
    _dot_disc_bad=0

    if [ ! -d "$DOT_MODULES_DIR" ]; then
        dot_error "modules directory not found: $DOT_MODULES_DIR"
        return 1
    fi

    for _dot_disc_path in "$DOT_MODULES_DIR"/*/module.sh; do
        # glob 未匹配时字面量保留，跳过
        [ -f "$_dot_disc_path" ] || continue

        _dot_disc_dir=$(dirname -- "$_dot_disc_path")
        _dot_disc_name=$(basename -- "$_dot_disc_dir")

        # 模块名限制为 [A-Za-z0-9_-]，保证空格分隔的名单不产生歧义
        case $_dot_disc_name in
            *[!A-Za-z0-9_-]*)
                dot_error "invalid module name '$_dot_disc_name' (allowed: A-Za-z0-9_-)"
                _dot_disc_bad=1
                continue
                ;;
        esac

        _dot_disc_meta=$(_dot_module_meta "$_dot_disc_name") || {
            dot_error "module '$_dot_disc_name': failed to load module.sh"
            _dot_disc_bad=1
            continue
        }

        eval "$_dot_disc_meta"

        if [ -n "$MODULE_INVALID" ]; then
            dot_error "module '$_dot_disc_name': $MODULE_INVALID"
            _dot_disc_bad=1
            continue
        fi

        # 元数据缓存到以模块名命名的变量里（POSIX sh 无关联数组，用 eval 模拟）
        _dot_disc_key=$(printf '%s' "$_dot_disc_name" | tr '-' '_')
        eval "DOT_M_${_dot_disc_key}_DESC=\$MODULE_DESC"
        eval "DOT_M_${_dot_disc_key}_PLATFORMS=\$MODULE_PLATFORMS"
        eval "DOT_M_${_dot_disc_key}_TAGS=\$MODULE_TAGS"
        eval "DOT_M_${_dot_disc_key}_REQUIRES=\$MODULE_REQUIRES"
        eval "DOT_M_${_dot_disc_key}_NEEDS_GUI=\$MODULE_NEEDS_GUI"

        DOT_ALL_MODULES="$DOT_ALL_MODULES $_dot_disc_name"
    done

    DOT_ALL_MODULES=$(printf '%s' "$DOT_ALL_MODULES" | sed 's/^ *//')

    [ "$_dot_disc_bad" = 0 ] || return 1
}

# 读取已发现模块的某个元数据字段
dot_module_get() {
    _dot_get_key=$(printf '%s' "$1" | tr '-' '_')
    eval "printf '%s' \"\${DOT_M_${_dot_get_key}_$2:-}\""
}

dot_module_exists() {
    for _dot_ex in $DOT_ALL_MODULES; do
        [ "$_dot_ex" = "$1" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------- 适用性过滤

# 模块是否适用于当前平台与环境。不适用时通过 DOT_SKIP_REASON 说明原因 ——
# 每次跳过都必须有原因，否则用户无法判断是预期行为还是故障。
dot_module_applicable() {
    _dot_ap_name=$1
    DOT_SKIP_REASON=''

    _dot_ap_platforms=$(dot_module_get "$_dot_ap_name" PLATFORMS)
    _dot_ap_match=0
    for _dot_ap_p in $_dot_ap_platforms; do
        [ "$_dot_ap_p" = "$DOT_OS" ] && _dot_ap_match=1 && break
    done
    if [ "$_dot_ap_match" = 0 ]; then
        DOT_SKIP_REASON="platform not supported (needs: $_dot_ap_platforms, have: $DOT_OS)"
        return 1
    fi

    if [ "$(dot_module_get "$_dot_ap_name" NEEDS_GUI)" = 1 ] && [ "$DOT_HEADLESS" = 1 ]; then
        DOT_SKIP_REASON='requires a graphical environment (headless: SSH/CI/container)'
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------- 依赖拓扑排序

# 深度优先访问，输出拓扑序。用状态变量实现环检测：
#   visiting = 在当前递归路径上（再次遇到即成环）
#   done     = 已输出
#
# 这是唯一的递归函数，因此必须用 local —— 否则内层调用会覆写外层的
# _dot_v_name/_dot_v_key，导致回到外层后把内层的模块名重复写入拓扑序
# （实测表现为 base 被输出三次而 mid/leaf 丢失）。
# local 不在 POSIX 中，但所有真实使用的 sh 都支持，见 lib/README.md。
_dot_ts_order=''
_dot_ts_error=''

# shellcheck disable=SC3043
_dot_ts_visit() {
    local _dot_v_name="$1"
    local _dot_v_path="$2"
    local _dot_v_key
    local _dot_v_state
    local _dot_v_dep

    # 把当前节点接到访问路径上，错误信息里就能看到完整的依赖链
    if [ -n "$_dot_v_path" ]; then
        _dot_v_path="$_dot_v_path -> $_dot_v_name"
    else
        _dot_v_path=$_dot_v_name
    fi

    _dot_v_key=$(printf '%s' "$_dot_v_name" | tr '-' '_')
    eval "_dot_v_state=\${DOT_TS_${_dot_v_key}:-}"

    if [ "$_dot_v_state" = "done" ]; then
        return 0
    fi
    if [ "$_dot_v_state" = "visiting" ]; then
        _dot_ts_error="circular dependency: $_dot_v_path"
        return 1
    fi

    if ! dot_module_exists "$_dot_v_name"; then
        _dot_ts_error="unknown dependency '$_dot_v_name' (required via $_dot_v_path)"
        return 1
    fi

    eval "DOT_TS_${_dot_v_key}=visiting"

    for _dot_v_dep in $(dot_module_get "$_dot_v_name" REQUIRES); do
        _dot_ts_visit "$_dot_v_dep" "$_dot_v_path" || return 1
    done

    eval "DOT_TS_${_dot_v_key}=done"
    _dot_ts_order="$_dot_ts_order $_dot_v_name"
}

# 对给定模块名列表做拓扑排序，结果回显。检测到环或未知依赖时报错并返回非零。
dot_runner_sort() {
    _dot_ts_order=''
    _dot_ts_error=''

    # 清理上一次排序的状态
    for _dot_s_m in $DOT_ALL_MODULES; do
        eval "DOT_TS_$(printf '%s' "$_dot_s_m" | tr '-' '_')=''"
    done

    for _dot_s_m in "$@"; do
        # 根节点路径为空，_dot_ts_visit 会把当前节点追加进去
        _dot_ts_visit "$_dot_s_m" "" || {
            dot_error "$_dot_ts_error"
            return 1
        }
    done

    printf '%s' "$(printf '%s' "$_dot_ts_order" | sed 's/^ *//')"
}

# ---------------------------------------------------------------- 执行

_dot_in_list() {
    _dot_il_needle=$1
    shift
    # 参数是空格分隔的模块名列表，需要分词，所以用 $* 而非 "$@"；
    # 模块名限制为 [A-Za-z0-9_-]，不含空格，因此分词是安全的。
    # shellcheck disable=SC2048,SC2086
    for _dot_il in $*; do
        [ "$_dot_il" = "$_dot_il_needle" ] && return 0
    done
    return 1
}

# 执行单个模块。在子 shell 中运行，使模块内的变量与 install() 定义
# 不泄漏到下一个模块（否则前一个模块的 install() 会被后一个复用）。
_dot_run_one() {
    _dot_ro_name=$1

    (
        # shellcheck disable=SC1090
        . "$DOT_MODULES_DIR/$_dot_ro_name/module.sh"
        install
    )
}

# dot_runner_run <module>...
# 按给定顺序（应已拓扑排序）执行模块，处理跳过与失败传导。
dot_runner_run() {
    DOT_RUN_OK=''
    DOT_RUN_FAILED=''
    DOT_RUN_SKIPPED=''

    for _dot_rr_name in "$@"; do
        # 依赖失败则跳过下游 —— 在依赖缺失的前提下执行只会产生更难诊断的次生错误
        _dot_rr_depfail=''
        for _dot_rr_dep in $(dot_module_get "$_dot_rr_name" REQUIRES); do
            if _dot_in_list "$_dot_rr_dep" "$DOT_RUN_FAILED $DOT_RUN_SKIPPED"; then
                _dot_rr_depfail=$_dot_rr_dep
                break
            fi
        done
        if [ -n "$_dot_rr_depfail" ]; then
            dot_skip "$_dot_rr_name: skipped (dependency failed: $_dot_rr_depfail)"
            DOT_RUN_SKIPPED="$DOT_RUN_SKIPPED $_dot_rr_name"
            continue
        fi

        if ! dot_module_applicable "$_dot_rr_name"; then
            dot_skip "$_dot_rr_name: $DOT_SKIP_REASON"
            DOT_RUN_SKIPPED="$DOT_RUN_SKIPPED $_dot_rr_name"
            continue
        fi

        dot_step "$_dot_rr_name — $(dot_module_get "$_dot_rr_name" DESC)"

        if _dot_run_one "$_dot_rr_name"; then
            DOT_RUN_OK="$DOT_RUN_OK $_dot_rr_name"
        else
            dot_error "$_dot_rr_name failed"
            DOT_RUN_FAILED="$DOT_RUN_FAILED $_dot_rr_name"
        fi
    done
}

# 输出汇总。有失败则返回非零，供 bootstrap.sh 决定退出码。
dot_runner_summary() {
    dot_step 'Summary'

    _dot_sum_n_ok=0
    _dot_sum_n_fail=0
    _dot_sum_n_skip=0
    for _dot_sum_m in $DOT_RUN_OK; do _dot_sum_n_ok=$((_dot_sum_n_ok + 1)); done
    for _dot_sum_m in $DOT_RUN_FAILED; do _dot_sum_n_fail=$((_dot_sum_n_fail + 1)); done
    for _dot_sum_m in $DOT_RUN_SKIPPED; do _dot_sum_n_skip=$((_dot_sum_n_skip + 1)); done

    [ "$_dot_sum_n_ok" -gt 0 ] && dot_success "succeeded ($_dot_sum_n_ok):$DOT_RUN_OK"
    [ "$_dot_sum_n_skip" -gt 0 ] && dot_skip "skipped ($_dot_sum_n_skip):$DOT_RUN_SKIPPED"
    [ "$_dot_sum_n_fail" -gt 0 ] && dot_error "failed ($_dot_sum_n_fail):$DOT_RUN_FAILED"

    dot_backup_summary

    if [ "$_dot_sum_n_fail" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------- 清单输出

# --list 的实现。零副作用。
dot_runner_list() {
    printf '%-16s %-10s %-22s %s\n' MODULE TAGS PLATFORMS STATUS
    printf '%-16s %-10s %-22s %s\n' '------' '----' '---------' '------'

    for _dot_ls_m in $DOT_ALL_MODULES; do
        if dot_module_applicable "$_dot_ls_m"; then
            _dot_ls_status='applicable'
        else
            _dot_ls_status="skip: $DOT_SKIP_REASON"
        fi
        printf '%-16s %-10s %-22s %s\n' \
            "$_dot_ls_m" \
            "$(dot_module_get "$_dot_ls_m" TAGS)" \
            "$(dot_module_get "$_dot_ls_m" PLATFORMS)" \
            "$_dot_ls_status"
        printf '                 %s\n' "$(dot_module_get "$_dot_ls_m" DESC)"
    done
}

# --help 中可用标签的部分，由发现结果动态生成（不硬编码）
dot_runner_tags() {
    for _dot_tg_m in $DOT_ALL_MODULES; do
        for _dot_tg_t in $(dot_module_get "$_dot_tg_m" TAGS); do
            printf '%s\n' "$_dot_tg_t"
        done
    done | sort -u | tr '\n' ' ' | sed 's/ $//'
}
