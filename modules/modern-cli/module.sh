#!/usr/bin/env sh
#
# 现代 CLI 工具链的安装。
#
# 清单在 config/cli/tools.txt，平台包名映射在 platform/*.sh —— 本模块
# 只负责读清单、按标签筛选、调用安装抽象、汇总结果。
#
# shellcheck shell=sh

MODULE_DESC="Modern CLI tools (ripgrep, fd, bat, eza, fzf, zoxide, delta, ...)"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="core cli"

install() {
    _dot_cli_manifest="$DOT_CONFIG_DIR/cli/tools.txt"

    if [ ! -f "$_dot_cli_manifest" ]; then
        dot_error "tool manifest not found: $_dot_cli_manifest"
        return 1
    fi

    if ! command -v dot_platform_pkg_name >/dev/null 2>&1; then
        dot_error 'platform adapter not loaded (dot_platform_pkg_name missing)'
        return 1
    fi

    _dot_cli_ok=0
    _dot_cli_skipped=0
    _dot_cli_failed=''
    _dot_cli_failed_essential=''

    # 仓库准备（RHEL 族的 EPEL）要在循环之前做一次，而不是每装一个包都判一次。
    # 放在这里而不是平台层的安装函数里，是为了让 dry-run 也能预告 ——
    # 启用 EPEL 会改系统仓库配置，属于用户该提前知道的副作用。
    dot_pkg_prepare_repos

    # 清单先读进变量，再用 here-doc 喂给循环。
    #
    # 不能直接 `while read ... done < manifest` —— brew / apt 这类命令会
    # 从 stdin 读取，而循环的 stdin 就是清单文件，于是它们把剩下的清单行
    # 吃掉，循环提前结束。实测：12 个工具只装了前 3 个就「成功」退出。
    # 每个安装调用再显式 </dev/null，双重保险。
    _dot_cli_lines=$(cat "$_dot_cli_manifest")

    while IFS='|' read -r _dot_cli_name _dot_cli_plat _dot_cli_tag _dot_cli_fb _dot_cli_desc; do
        case $_dot_cli_name in
            '' | \#*) continue ;;
        esac

        if [ -z "$_dot_cli_plat" ] || [ -z "$_dot_cli_tag" ]; then
            dot_error "malformed manifest line for '$_dot_cli_name' (need name|platforms|tag|fallback|desc)"
            _dot_cli_failed="$_dot_cli_failed $_dot_cli_name"
            _dot_cli_failed_essential="$_dot_cli_failed_essential $_dot_cli_name"
            continue
        fi

        # 未知标签必须报错而不是默默当成 default —— 打错字（"defualt"）
        # 会让工具静静地不被安装，那是最难发现的一类问题。
        case $_dot_cli_tag in
            essential | default | optional) ;;
            *)
                dot_error "unknown tag '$_dot_cli_tag' for '$_dot_cli_name' (want essential/default/optional)"
                _dot_cli_failed="$_dot_cli_failed $_dot_cli_name"
                _dot_cli_failed_essential="$_dot_cli_failed_essential $_dot_cli_name"
                continue
                ;;
        esac

        # 平台筛选。all 是三平台的简写。
        if [ "$_dot_cli_plat" != all ] && ! _dot_cli_in "$DOT_OS" "$_dot_cli_plat"; then
            dot_skip "$_dot_cli_name: not for $DOT_OS (manifest says: $_dot_cli_plat)"
            _dot_cli_skipped=$((_dot_cli_skipped + 1))
            continue
        fi

        # 标签筛选：optional 的工具需要显式要求才装
        if [ "$_dot_cli_tag" = optional ] && ! _dot_cli_wanted "$_dot_cli_name"; then
            dot_skip "$_dot_cli_name: optional, not requested"
            _dot_cli_skipped=$((_dot_cli_skipped + 1))
            continue
        fi

        # shellcheck disable=SC2086
        if dot_pkg_install "$_dot_cli_name" $_dot_cli_fb </dev/null; then
            _dot_cli_ok=$((_dot_cli_ok + 1))
        else
            # 单个工具装不上不中断其余 —— 一个仓库缺包不该让整条工具链失败
            _dot_cli_failed="$_dot_cli_failed $_dot_cli_name"
            [ "$_dot_cli_tag" = essential ] &&
                _dot_cli_failed_essential="$_dot_cli_failed_essential $_dot_cli_name"
        fi
    done <<EOF
$_dot_cli_lines
EOF

    dot_info "installed/present: $_dot_cli_ok · skipped: $_dot_cli_skipped"

    _dot_cli_stale_check

    # 装不上的工具分两类看待。
    #
    # 之前这里对任何失败都 return 1，而紧随其后的提示却说「这些工具对其余
    # 部分是可选的、shell 配置会优雅降级」—— 自相矛盾：既然可选，为什么
    # 让整个引导非零退出？在包源贫乏的发行版上这个矛盾很致命：
    # RHEL/CentOS 7 的仓库里没有 eza/lazygit/gh/yq，于是引导永远失败，
    # 即使 zsh、git、字体、密钥全都装好了。
    #
    # 现在只有 essential 的工具失败才让模块失败。
    if [ -n "$_dot_cli_failed" ]; then
        if [ -n "$_dot_cli_failed_essential" ]; then
            dot_error "could not install:$_dot_cli_failed"
            dot_error "  essential:$_dot_cli_failed_essential"
            dot_tip 'the rest degrade gracefully, but essential tools should be fixed'
            return 1
        fi

        dot_tip "could not install:$_dot_cli_failed"
        dot_tip 'none of these are essential — shell config degrades gracefully'
        dot_tip '  they are absent from your package repos; a source build is the only route'
    fi
}

# 报告「在 PATH 里但来自非包管理器位置」的工具。
#
# 幂等判定基于「PATH 里可执行」，这是对的 —— 但它也意味着一个从旧配置
# 继承来的老二进制会让我们跳过安装，用户则停留在旧版本上。实测遇到过：
# 一个 2023 年的 fzf 0.41 缺少 `--zsh`，shell 集成静默失效。
# 这里只提示不自动替换 —— 覆盖用户手工装的工具属于越界。
_dot_cli_stale_check() {
    _dot_sc_notes=''

    # fzf：0.48 起才有 --zsh，没有它就得去找自带的 shell 脚本
    if command -v fzf >/dev/null 2>&1 && ! fzf --zsh >/dev/null 2>&1; then
        _dot_sc_notes="$_dot_sc_notes fzf"
    fi

    [ -n "$_dot_sc_notes" ] || return 0

    dot_tip "outdated tool(s) found in PATH:$_dot_sc_notes"
    for _dot_sc_t in $_dot_sc_notes; do
        dot_tip "  $_dot_sc_t -> $(command -v "$_dot_sc_t")"
    done
    dot_tip 'these predate features the shell config expects; consider removing the old copy'
    dot_tip "  so the package manager's version takes over"
}

# 值是否在空格分隔的列表里
_dot_cli_in() {
    for _dot_ci in $2; do
        [ "$_dot_ci" = "$1" ] && return 0
    done
    return 1
}

# optional 工具是否被显式要求。
# 两种方式：环境变量 DOT_WANT_<NAME>=1，或 DOT_CLI_OPTIONAL 里列出名字。
_dot_cli_wanted() {
    _dot_cw_name=$1
    _dot_cw_var="DOT_WANT_$(printf '%s' "$_dot_cw_name" | tr '[:lower:]-' '[:upper:]_')"

    # 变量名由 eval 动态构造，shellcheck 追不进去
    eval "_dot_cw_val=\${$_dot_cw_var:-}"
    # shellcheck disable=SC2154
    [ "$_dot_cw_val" = 1 ] && return 0

    _dot_cli_in "$_dot_cw_name" "${DOT_CLI_OPTIONAL:-}" && return 0
    return 1
}
