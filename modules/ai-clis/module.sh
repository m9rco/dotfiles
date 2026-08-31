#!/usr/bin/env sh
#
# AI 编码 CLI 的安装（Claude Code / Codex CLI / Gemini CLI）。
#
# 清单在 config/ai/clis.txt，新增工具只需加一行。
#
# 三条硬约束：
#   1. 安装过程不索取 API key、不触发登录 —— 认证是用户之后自己做的事
#   2. npm 全局安装绝不用 sudo —— 需要 sudo 说明 npm 前缀配置有问题，
#      该修配置而不是提权
#   3. 默认引导不自动升级已装的 CLI —— 升级要显式触发
#
# shellcheck shell=sh

MODULE_DESC="AI coding CLIs (Claude Code, Codex CLI, Gemini CLI)"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="ai"

install() {
    _dot_ac_manifest="$DOT_CONFIG_DIR/ai/clis.txt"

    if [ ! -f "$_dot_ac_manifest" ]; then
        dot_error "AI CLI manifest not found: $_dot_ac_manifest"
        return 1
    fi

    _dot_ac_ok=0
    _dot_ac_skipped=0
    _dot_ac_failed=''

    # 清单先读进变量再用 here-doc 喂给循环 —— npm 会从 stdin 读取，
    # 直接 `done < manifest` 会让它吃掉剩余清单行（见 modules/modern-cli 的说明）
    _dot_ac_lines=$(cat "$_dot_ac_manifest")

    while IFS='|' read -r _dot_ac_cmd _dot_ac_plat _dot_ac_how _dot_ac_vflag _dot_ac_desc; do
        case $_dot_ac_cmd in
            '' | \#*) continue ;;
        esac

        if [ -z "$_dot_ac_plat" ] || [ -z "$_dot_ac_how" ]; then
            dot_error "malformed manifest line for '$_dot_ac_cmd' (need cmd|platforms|how|versionflag|desc)"
            _dot_ac_failed="$_dot_ac_failed $_dot_ac_cmd"
            continue
        fi

        # 子集筛选：DOT_AI_CLIS 给出时只装其中列出的
        if [ -n "${DOT_AI_CLIS:-}" ] && ! _dot_ac_in "$_dot_ac_cmd" "$DOT_AI_CLIS"; then
            dot_skip "$_dot_ac_cmd: not in DOT_AI_CLIS"
            _dot_ac_skipped=$((_dot_ac_skipped + 1))
            continue
        fi

        if [ "$_dot_ac_plat" != all ] && ! _dot_ac_in "$DOT_OS" "$_dot_ac_plat"; then
            dot_skip "$_dot_ac_cmd: not for $DOT_OS"
            _dot_ac_skipped=$((_dot_ac_skipped + 1))
            continue
        fi

        if _dot_ac_install_one "$_dot_ac_cmd" "$_dot_ac_how" "$_dot_ac_vflag"; then
            _dot_ac_ok=$((_dot_ac_ok + 1))
        else
            _dot_ac_failed="$_dot_ac_failed $_dot_ac_cmd"
        fi
    done <<EOF
$_dot_ac_lines
EOF

    dot_info "ready: $_dot_ac_ok · skipped: $_dot_ac_skipped"

    if [ -n "$_dot_ac_failed" ]; then
        dot_error "could not install:$_dot_ac_failed"
        return 1
    fi

    _dot_ac_auth_hint
}

# ---------------------------------------------------------------- 单个 CLI

_dot_ac_install_one() {
    _dot_ai1_cmd=$1
    _dot_ai1_how=$2
    _dot_ai1_vflag=$3

    # 幂等：已装则跳过并报版本，不重装也不升级
    if _dot_ac_present "$_dot_ai1_cmd"; then
        _dot_ai1_path=$(_dot_ac_which "$_dot_ai1_cmd")
        dot_skip "$_dot_ai1_cmd already installed at $_dot_ai1_path"
        _dot_ac_report_version "$_dot_ai1_cmd" "$_dot_ai1_vflag"
        _dot_ac_note_manager "$_dot_ai1_cmd" "$_dot_ai1_path"
        return 0
    fi

    # 按清单里给出的顺序尝试各安装方式
    _dot_ai1_tried=''
    for _dot_ai1_m in $(printf '%s' "$_dot_ai1_how" | tr ',' ' '); do
        _dot_ai1_kind=${_dot_ai1_m%%:*}
        _dot_ai1_arg=${_dot_ai1_m#*:}
        _dot_ai1_tried="$_dot_ai1_tried $_dot_ai1_kind"

        case $_dot_ai1_kind in
            npm)
                if _dot_ac_npm_install "$_dot_ai1_cmd" "$_dot_ai1_arg"; then
                    _dot_ac_report_version "$_dot_ai1_cmd" "$_dot_ai1_vflag"
                    return 0
                fi
                ;;
            brew)
                if command -v brew >/dev/null 2>&1; then
                    if dot_is_dry_run; then
                        dot_info "[dry-run] would install $_dot_ai1_cmd via brew ($_dot_ai1_arg)"
                        return 0
                    fi
                    if brew install "$_dot_ai1_arg" </dev/null; then
                        dot_success "$_dot_ai1_cmd installed via brew"
                        _dot_ac_report_version "$_dot_ai1_cmd" "$_dot_ai1_vflag"
                        return 0
                    fi
                fi
                ;;
            script)
                if dot_is_dry_run; then
                    dot_info "[dry-run] would install $_dot_ai1_cmd via official script"
                    return 0
                fi
                if command -v curl >/dev/null 2>&1 &&
                    curl -fsSL "$_dot_ai1_arg" | sh >/dev/null 2>&1; then
                    dot_success "$_dot_ai1_cmd installed via official script"
                    _dot_ac_report_version "$_dot_ai1_cmd" "$_dot_ai1_vflag"
                    return 0
                fi
                ;;
            *)
                dot_error "unknown install method '$_dot_ai1_kind' for $_dot_ai1_cmd"
                ;;
        esac
    done

    dot_error "$_dot_ai1_cmd: no install method succeeded (tried:$_dot_ai1_tried)"
    return 1
}

# 命令是否真的已安装。
#
# 不能用 `command -v` —— shell alias 也会让它成功。实测：`claude` 在交互式
# shell 里是个 alias，command -v 输出 "alias claude='claude --append-...'"
# 而不是路径，天真的检测会误判为已安装并跳过安装。
#
# 也不能用 `command -v -p` —— -p 搜索的是系统默认 PATH 而非当前 PATH，
# 于是沙箱里明明没有的命令也会被「找到」（实测把 emptybin 测试骗过去了）。
#
# 只能显式遍历当前 PATH 找可执行文件：既不被 alias 骗，也尊重当前 PATH。
_dot_ac_present() {
    _dot_ap_cmd=$1
    _dot_ap_ifs=$IFS
    IFS=:
    for _dot_ap_dir in $PATH; do
        if [ -x "$_dot_ap_dir/$_dot_ap_cmd" ]; then
            IFS=$_dot_ap_ifs
            return 0
        fi
    done
    IFS=$_dot_ap_ifs
    return 1
}

_dot_ac_which() {
    _dot_aw_cmd=$1
    _dot_aw_ifs=$IFS
    IFS=:
    for _dot_aw_dir in $PATH; do
        if [ -x "$_dot_aw_dir/$_dot_aw_cmd" ]; then
            IFS=$_dot_aw_ifs
            printf '%s' "$_dot_aw_dir/$_dot_aw_cmd"
            return 0
        fi
    done
    IFS=$_dot_aw_ifs
    printf '%s' '(unknown location)'
}

# 说明这个工具由哪个版本管理器托管。
#
# volta / asdf / mise 装的工具有自己的 shim，用 `npm install -g` 升级会在
# 别处再装一份并遮蔽原来的 —— 用户看到「成功」但 which 指向的还是旧副本。
# 这里只说明来源，让用户知道该用哪个工具升级（见 bin/dot-ai-upgrade）。
_dot_ac_note_manager() {
    case $2 in
        *"/.volta/"*) dot_tip "  managed by volta — upgrade with: volta install <pkg>@latest" ;;
        *"/.asdf/"*) dot_tip '  managed by asdf — upgrade through asdf, not npm -g' ;;
        *"/.local/share/mise/"* | *"/.mise/"*) dot_tip '  managed by mise — upgrade through mise, not npm -g' ;;
    esac
}

# ---------------------------------------------------------------- npm

# npm 全局安装。绝不用 sudo。
_dot_ac_npm_install() {
    _dot_an_cmd=$1
    _dot_an_pkg=$2

    if ! command -v npm >/dev/null 2>&1; then
        dot_error "$_dot_an_cmd needs npm, which is not installed"
        dot_tip 'install node (e.g. via nvm or your package manager) and rerun'
        return 1
    fi

    if dot_is_dry_run; then
        dot_info "[dry-run] would install $_dot_an_cmd via npm ($_dot_an_pkg)"
        return 0
    fi

    _dot_ac_ensure_npm_prefix || return 1

    dot_info "installing $_dot_an_pkg via npm"
    if ! npm install --global "$_dot_an_pkg" </dev/null; then
        dot_error "npm install --global $_dot_an_pkg failed"
        return 1
    fi

    dot_success "$_dot_an_cmd installed via npm"
}

# 确保 npm 全局安装不需要 root。
#
# npm 默认前缀可能指向系统目录（/usr/local 等），那样全局安装要 sudo。
# 用 sudo 装 npm 包会让文件属主变 root，之后的普通安装反而失败 ——
# 所以这里把前缀改到用户目录，而不是提权。
_dot_ac_ensure_npm_prefix() {
    _dot_np_prefix=$(npm config get prefix 2>/dev/null)

    # 前缀已经在 $HOME 下（nvm/volta/fnm 管理的 node 都是这样）就无需处理
    case $_dot_np_prefix in
        "$HOME"/*)
            return 0
            ;;
    esac

    # 前缀可写也行（比如 Homebrew 装的 node，前缀在 brew 目录且属主是当前用户）
    if [ -n "$_dot_np_prefix" ] && [ -w "$_dot_np_prefix/lib" ] 2>/dev/null; then
        return 0
    fi

    _dot_np_want="$HOME/.npm-global"
    dot_info "npm prefix ($_dot_np_prefix) is not user-writable; switching to $_dot_np_want"
    dot_mkdir "$_dot_np_want" || return 1

    if ! npm config set prefix "$_dot_np_want"; then
        dot_error 'failed to set a user-writable npm prefix'
        return 1
    fi

    # 让本次会话立即可用；持久化由 zsh 的 10-path.zsh 负责
    PATH="$_dot_np_want/bin:$PATH"
    export PATH

    dot_success "npm prefix set to $_dot_np_want (no sudo needed)"
    dot_tip "$_dot_np_want/bin is on PATH via config/zsh/zshrc.d/10-path.zsh"
}

# ---------------------------------------------------------------- 版本

# 报告版本。查询失败只警告 —— CLI 可能不支持 --version、输出格式变化、
# 或首次运行要联网初始化。这些都不该让安装被判为失败。
_dot_ac_report_version() {
    _dot_av_cmd=$1
    _dot_av_flag=$2

    [ -n "$_dot_av_flag" ] || return 0
    dot_is_dry_run && return 0

    _dot_av_out=$("$_dot_av_cmd" "$_dot_av_flag" 2>/dev/null </dev/null | head -n 1)

    if [ -n "$_dot_av_out" ]; then
        dot_info "  $_dot_av_cmd: $_dot_av_out"
    else
        dot_tip "  $_dot_av_cmd: version check produced no output (not fatal)"
    fi
}

# ---------------------------------------------------------------- 认证指引

_dot_ac_auth_hint() {
    dot_tip 'authentication is a separate step — none of the above asked for credentials:'
    # 这些是给用户看的命令示例，反引号与内容必须原样输出，所以用单引号
    # shellcheck disable=SC2016
    {
        _dot_ac_present claude && dot_tip '  claude  -> run `claude` and follow the login prompt'
        _dot_ac_present codex && dot_tip '  codex   -> run `codex login` (or set OPENAI_API_KEY)'
        _dot_ac_present gemini && dot_tip '  gemini  -> run `gemini` and follow the login prompt'
    }
    dot_tip 'store keys in your keychain, not in this repo (see the secrets module)'
}

# ---------------------------------------------------------------- 工具

_dot_ac_in() {
    for _dot_ai_x in $(printf '%s' "$2" | tr ',' ' '); do
        [ "$_dot_ai_x" = "$1" ] && return 0
    done
    return 1
}
