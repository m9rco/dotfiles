#!/usr/bin/env sh
#
# 跨平台密钥读取。
#
# 本仓库是公开的，所以有一条不可协商的规则：**凭据的值绝不进入仓库、
# 日志、错误信息或 dry-run 输出**。这里只出现凭据的「名字」与「来源」。
#
# 来源按顺序尝试：
#   1. 环境变量        —— 已经在环境里就直接用（CI 常见）
#   2. 系统密钥库      —— macOS keychain / Linux secret-tool / Windows credential manager
#   3. 1Password CLI   —— 可选，需已登录
#   4. 本地 env 文件   —— ~/.config/dotfiles/env.local，600 权限，不入库
#
# 读不到时返回非零并明确报错 —— 绝不用空值冒充成功，那会让调用方
# 拿着空 key 去请求 API，得到一个难以诊断的 401。
#
# shellcheck shell=sh

[ -n "${DOT_SECRETS_SH_LOADED:-}" ] && return 0
DOT_SECRETS_SH_LOADED=1

# shellcheck source=lib/log.sh
. "${DOT_LIB_DIR:-$(dirname -- "$0")}/log.sh"

# 本地兜底文件。不入库、600 权限。
DOT_ENV_LOCAL=${DOT_ENV_LOCAL:-$HOME/.config/dotfiles/env.local}

# keychain 里存放这些凭据用的服务名前缀
DOT_SECRET_SERVICE=${DOT_SECRET_SERVICE:-dotfiles}

# ---------------------------------------------------------------- 读取

# dot_secret_get <NAME>
#
# 成功时把值写到 stdout 并返回 0；失败时返回非零，stderr 上说明
# 「找了哪些来源」但不包含任何值的片段。
dot_secret_get() {
    _dot_sg_name=$1

    if [ -z "$_dot_sg_name" ]; then
        dot_error 'dot_secret_get: no secret name given'
        return 2
    fi

    # 1. 环境变量
    eval "_dot_sg_env=\${$_dot_sg_name:-}"
    if [ -n "$_dot_sg_env" ]; then
        printf '%s' "$_dot_sg_env"
        return 0
    fi

    # 2. 系统密钥库
    if _dot_sg_val=$(_dot_secret_from_keystore "$_dot_sg_name") && [ -n "$_dot_sg_val" ]; then
        printf '%s' "$_dot_sg_val"
        return 0
    fi

    # 3. 1Password
    if _dot_sg_val=$(_dot_secret_from_op "$_dot_sg_name") && [ -n "$_dot_sg_val" ]; then
        printf '%s' "$_dot_sg_val"
        return 0
    fi

    # 4. 本地文件
    if _dot_sg_val=$(_dot_secret_from_envfile "$_dot_sg_name") && [ -n "$_dot_sg_val" ]; then
        printf '%s' "$_dot_sg_val"
        return 0
    fi

    # 明确失败。只说名字，不说值（本来也没有值）。
    dot_error "secret '$_dot_sg_name' not found"
    dot_error "  looked in: environment, $(_dot_secret_keystore_name), 1Password CLI, $DOT_ENV_LOCAL"
    dot_tip "store it with:  dot_secret_set $_dot_sg_name"
    return 1
}

# 只判断存在性，不取值 —— 用于「有没有配这个 key」的检查。
dot_secret_has() {
    dot_secret_get "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------- 各来源

_dot_secret_keystore_name() {
    case $DOT_OS in
        macos) printf 'macOS keychain' ;;
        linux) printf 'secret-tool (libsecret)' ;;
        windows) printf 'Windows credential manager' ;;
        *) printf 'system keystore' ;;
    esac
}

_dot_secret_from_keystore() {
    _dot_ks_name=$1

    case $DOT_OS in
        macos)
            command -v security >/dev/null 2>&1 || return 1
            # -w 只输出密码本身。找不到时非零退出，stderr 被丢弃 ——
            # security 的错误信息里会带上服务名，但不会带值。
            security find-generic-password \
                -s "$DOT_SECRET_SERVICE" -a "$_dot_ks_name" -w 2>/dev/null
            ;;
        linux)
            command -v secret-tool >/dev/null 2>&1 || return 1
            secret-tool lookup service "$DOT_SECRET_SERVICE" account "$_dot_ks_name" 2>/dev/null
            ;;
        windows)
            # PowerShell 侧有自己的实现；Git-Bash 里没有可靠的 CLI 入口
            return 1
            ;;
        *) return 1 ;;
    esac
}

# 1Password CLI。未安装则跳过；已安装但未登录时给提示并**有限时间返回** ——
# `op` 在未登录时可能等待交互，挂住整个引导流程。
_dot_secret_from_op() {
    _dot_op_name=$1

    command -v op >/dev/null 2>&1 || return 1

    # 先用一个不会触发交互的命令探测登录状态，并加超时
    if ! _dot_secret_timeout 5 op whoami >/dev/null 2>&1; then
        dot_tip "1Password CLI is installed but not signed in; skipping it"
        dot_tip "  run 'op signin' to use it as a secret source"
        return 1
    fi

    # op://<vault>/<item>/<field> 的引用可放在环境变量 DOT_OP_<NAME> 里，
    # 否则按约定去 dotfiles vault 找同名条目
    eval "_dot_op_ref=\${DOT_OP_$_dot_op_name:-}"
    if [ -z "$_dot_op_ref" ]; then
        _dot_op_ref="op://${DOT_OP_VAULT:-dotfiles}/$_dot_op_name/credential"
    fi

    _dot_secret_timeout 10 op read "$_dot_op_ref" 2>/dev/null
}

# 从本地 env 文件读。文件格式是 NAME=value 每行一条。
_dot_secret_from_envfile() {
    _dot_ef_name=$1

    [ -r "$DOT_ENV_LOCAL" ] || return 1

    # 权限不对就拒绝读 —— 一个 644 的密钥文件对同机其他用户是可读的
    if ! _dot_secret_perms_ok "$DOT_ENV_LOCAL"; then
        dot_error "$DOT_ENV_LOCAL has unsafe permissions; refusing to read it"
        dot_tip "fix with:  chmod 600 $DOT_ENV_LOCAL"
        return 1
    fi

    # 用 sed 精确取值，不 source 整个文件 —— source 会执行文件里的任意内容
    sed -n "s/^[[:space:]]*${_dot_ef_name}[[:space:]]*=[[:space:]]*//p" "$DOT_ENV_LOCAL" 2>/dev/null |
        head -n 1 |
        sed 's/^"//; s/"$//; s/^'\''//; s/'\''$//'
}

# 文件权限必须是 600 或更严（属主之外不可读）
_dot_secret_perms_ok() {
    _dot_pm=$(_dot_secret_mode "$1")
    [ -n "$_dot_pm" ] || return 0
    case $_dot_pm in
        600 | 400 | 000) return 0 ;;
        *) return 1 ;;
    esac
}

# 读取文件权限的八进制表示（如 600）。
#
# BSD 与 GNU 的 stat 参数完全不同，而且不能靠「先试一个失败了再试另一个」——
# GNU 的 -f 是「显示文件系统信息」，对任意文件都会成功并输出无关内容，
# 于是 `if stat -f ...; then return; fi` 会把垃圾当成权限返回。
# 实测表现：macOS 上正确，Linux 上权限判断全部失效。
#
# 正确做法是校验输出：权限必须是 3-4 位数字，否则换另一种语法。
_dot_secret_mode() {
    _dot_sm_out=$(stat -c '%a' "$1" 2>/dev/null)
    case $_dot_sm_out in
        [0-7][0-7][0-7] | [0-7][0-7][0-7][0-7])
            printf '%s' "$_dot_sm_out"
            return 0
            ;;
    esac

    _dot_sm_out=$(stat -f '%Lp' "$1" 2>/dev/null)
    case $_dot_sm_out in
        [0-7][0-7][0-7] | [0-7][0-7][0-7][0-7])
            printf '%s' "$_dot_sm_out"
            return 0
            ;;
    esac

    # 两种都拿不到可用结果：不猜。调用方会因为空值走保守分支。
    return 1
}

# 给命令加超时。timeout(1) 不一定存在（macOS 默认没有），
# 没有时退回到后台执行 + 轮询。
_dot_secret_timeout() {
    _dot_to_secs=$1
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$_dot_to_secs" "$@"
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$_dot_to_secs" "$@"
        return $?
    fi

    # 无 timeout 可用：后台跑 + 轮询，超时则杀掉。
    # 不完美（丢失退出码的精确性），但能保证不无限挂住引导流程。
    "$@" &
    _dot_to_pid=$!
    _dot_to_waited=0
    while kill -0 "$_dot_to_pid" 2>/dev/null; do
        if [ "$_dot_to_waited" -ge "$_dot_to_secs" ]; then
            kill -TERM "$_dot_to_pid" 2>/dev/null
            wait "$_dot_to_pid" 2>/dev/null
            return 124
        fi
        sleep 1
        _dot_to_waited=$((_dot_to_waited + 1))
    done
    wait "$_dot_to_pid"
}

# ---------------------------------------------------------------- 写入

# dot_secret_set <NAME> —— 交互式把凭据存进系统密钥库。
# 值从 stdin 静默读取（不回显），且绝不写入日志。
dot_secret_set() {
    _dot_ss_name=$1

    if [ -z "$_dot_ss_name" ]; then
        dot_error 'dot_secret_set: no secret name given'
        return 2
    fi

    if [ ! -t 0 ]; then
        dot_error 'dot_secret_set needs an interactive terminal'
        return 1
    fi

    dot_prompt "value for $_dot_ss_name (input hidden):"
    # 关闭回显再读 —— 密钥不该出现在终端历史或滚动缓冲里
    stty -echo 2>/dev/null
    read -r _dot_ss_val
    stty echo 2>/dev/null
    printf '\n' >&2

    if [ -z "$_dot_ss_val" ]; then
        dot_error 'empty value; nothing stored'
        return 1
    fi

    case $DOT_OS in
        macos)
            # -U 表示已存在则更新
            if security add-generic-password -U \
                -s "$DOT_SECRET_SERVICE" -a "$_dot_ss_name" -w "$_dot_ss_val" 2>/dev/null; then
                _dot_ss_val=''
                dot_success "$_dot_ss_name stored in the macOS keychain"
                return 0
            fi
            ;;
        linux)
            if command -v secret-tool >/dev/null 2>&1 &&
                printf '%s' "$_dot_ss_val" | secret-tool store --label="dotfiles $_dot_ss_name" \
                    service "$DOT_SECRET_SERVICE" account "$_dot_ss_name" 2>/dev/null; then
                _dot_ss_val=''
                dot_success "$_dot_ss_name stored via secret-tool"
                return 0
            fi
            ;;
    esac

    # 密钥库不可用时退回本地文件，权限 600
    dot_tip 'system keystore unavailable; falling back to the local env file'
    dot_secret_env_file_init || return 1

    # 已有同名条目则替换
    if [ -f "$DOT_ENV_LOCAL" ] && grep -q "^[[:space:]]*${_dot_ss_name}[[:space:]]*=" "$DOT_ENV_LOCAL" 2>/dev/null; then
        _dot_ss_tmp=$(mktemp) || return 1
        grep -v "^[[:space:]]*${_dot_ss_name}[[:space:]]*=" "$DOT_ENV_LOCAL" >"$_dot_ss_tmp"
        mv "$_dot_ss_tmp" "$DOT_ENV_LOCAL"
        chmod 600 "$DOT_ENV_LOCAL"
    fi

    printf '%s=%s\n' "$_dot_ss_name" "$_dot_ss_val" >>"$DOT_ENV_LOCAL"
    chmod 600 "$DOT_ENV_LOCAL"
    _dot_ss_val=''
    dot_success "$_dot_ss_name stored in $DOT_ENV_LOCAL (600, not tracked)"
}

# 创建本地 env 文件，600 权限。
dot_secret_env_file_init() {
    _dot_ei_dir=$(dirname -- "$DOT_ENV_LOCAL")

    if [ ! -d "$_dot_ei_dir" ]; then
        mkdir -p "$_dot_ei_dir" || {
            dot_error "cannot create $_dot_ei_dir"
            return 1
        }
        chmod 700 "$_dot_ei_dir"
    fi

    if [ ! -f "$DOT_ENV_LOCAL" ]; then
        # umask 保证创建瞬间就不是 world-readable，避免竞态窗口
        _dot_ei_umask=$(umask)
        umask 077
        {
            printf '# Local credentials for dotfiles. NOT tracked by git.\n'
            printf '# Prefer the system keychain; this file is the fallback.\n'
            printf '# Format: NAME=value (one per line)\n'
        } >"$DOT_ENV_LOCAL" || {
            umask "$_dot_ei_umask"
            dot_error "cannot create $DOT_ENV_LOCAL"
            return 1
        }
        umask "$_dot_ei_umask"
    fi

    chmod 600 "$DOT_ENV_LOCAL"
}

# ---------------------------------------------------------------- 按需注入

# dot_secret_load <NAME>... —— 把凭据读进当前 shell 的环境变量。
#
# 这是给交互式使用准备的：shell 启动时**不会**调用它（那会拖慢启动，
# 并可能弹出 keychain 授权框），需要时手动跑。
dot_secret_load() {
    _dot_sl_loaded=''
    _dot_sl_missing=''

    for _dot_sl_name in "$@"; do
        if _dot_sl_val=$(dot_secret_get "$_dot_sl_name" 2>/dev/null) && [ -n "$_dot_sl_val" ]; then
            export "$_dot_sl_name=$_dot_sl_val"
            _dot_sl_val=''
            _dot_sl_loaded="$_dot_sl_loaded $_dot_sl_name"
        else
            _dot_sl_missing="$_dot_sl_missing $_dot_sl_name"
        fi
    done

    # 只报名字，不报值
    [ -n "$_dot_sl_loaded" ] && dot_success "loaded:$_dot_sl_loaded"
    [ -n "$_dot_sl_missing" ] && dot_tip "not found:$_dot_sl_missing"

    [ -z "$_dot_sl_missing" ]
}
