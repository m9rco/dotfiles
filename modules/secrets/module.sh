#!/usr/bin/env sh
#
# 密钥管理与可选的本地推理工具。
#
# 本仓库是公开的，所以这个模块的核心职责是「让密钥有个安全的去处，
# 并防止它们被误提交」——而不是管理密钥本身。
#
# shellcheck shell=sh

MODULE_DESC="Secret storage helpers and a gitleaks pre-commit guard"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="core secrets"

install() {
    # shellcheck source=lib/secrets.sh
    . "$DOT_LIB_DIR/secrets.sh"

    _dot_sec_env_file
    _dot_sec_gitignore_check
    _dot_sec_gitleaks
    _dot_sec_ollama
    _dot_sec_report_sources
}

# ---------------------------------------------------------------- 本地 env 文件

# 建好目录与文件（600 权限），但不放任何内容 —— 凭据由用户自己存。
_dot_sec_env_file() {
    if [ -f "$DOT_ENV_LOCAL" ]; then
        # 已存在则只校正权限。曾经是 644 的话现在收紧。
        _dot_se_mode=$(_dot_secret_mode "$DOT_ENV_LOCAL")
        if [ "$_dot_se_mode" != 600 ] && [ "$_dot_se_mode" != 400 ]; then
            if dot_is_dry_run; then
                dot_info "[dry-run] would chmod 600 $DOT_ENV_LOCAL (currently $_dot_se_mode)"
            else
                chmod 600 "$DOT_ENV_LOCAL"
                dot_success "tightened $DOT_ENV_LOCAL to 600 (was $_dot_se_mode)"
            fi
        else
            dot_skip "$DOT_ENV_LOCAL already exists with mode $_dot_se_mode"
        fi
        return 0
    fi

    if dot_is_dry_run; then
        dot_info "[dry-run] would create $DOT_ENV_LOCAL with mode 600"
        return 0
    fi

    dot_secret_env_file_init || return 1
    dot_success "created $DOT_ENV_LOCAL (600, never tracked by git)"
}

# 确认本地凭据文件不会被 git 跟踪。
#
# 这个文件在 $HOME 下、不在仓库里，所以 .gitignore 管不到它 ——
# 但用户可能把 dotfiles 仓库 clone 到 $HOME，或者手工把它复制进仓库。
# 全局 gitignore 里已有 *.local 与 .env* 的规则，这里做个断言式检查。
_dot_sec_gitignore_check() {
    _dot_gc_global="$DOT_CONFIG_DIR/git/gitignore_global"

    [ -f "$_dot_gc_global" ] || {
        dot_tip 'global gitignore not found; run the git module first'
        return 0
    }

    _dot_gc_missing=''
    for _dot_gc_pat in '.env' '*.local' '*.pem' '*.key'; do
        grep -qxF "$_dot_gc_pat" "$_dot_gc_global" 2>/dev/null ||
            _dot_gc_missing="$_dot_gc_missing $_dot_gc_pat"
    done

    if [ -n "$_dot_gc_missing" ]; then
        dot_error "global gitignore is missing secret patterns:$_dot_gc_missing"
        return 1
    fi
    dot_success 'global gitignore covers the usual secret file patterns'
}

# ---------------------------------------------------------------- gitleaks

# 安装 gitleaks 并在本仓库配置 pre-commit 守卫。
#
# gitignore 只能防「误 add 新文件」，防不住往已跟踪文件里写密钥 ——
# 那正是这个守卫存在的理由。
_dot_sec_gitleaks() {
    if ! command -v gitleaks >/dev/null 2>&1; then
        if dot_is_dry_run; then
            dot_info '[dry-run] would install gitleaks'
        else
            dot_info 'installing gitleaks'
            dot_pkg_install gitleaks </dev/null || {
                dot_tip 'gitleaks could not be installed; the pre-commit guard will NOT be active'
                dot_tip '  install it later and rerun this module to enable the guard'
                return 0
            }
        fi
    else
        dot_skip "gitleaks already installed ($(command -v gitleaks))"
    fi

    _dot_sec_install_hook
}

# 装 pre-commit hook 到本仓库。
#
# 只装到 dotfiles 仓库自身 —— 给所有仓库装守卫要用 core.hooksPath，
# 那会覆盖用户在别的项目里已有的 hook，越界了。
_dot_sec_install_hook() {
    _dot_ih_dir="$DOT_ROOT/.git/hooks"

    if [ ! -d "$DOT_ROOT/.git" ]; then
        dot_skip 'not a git working copy; skipping the pre-commit hook'
        return 0
    fi

    _dot_ih_hook="$_dot_ih_dir/pre-commit"

    if dot_is_dry_run; then
        dot_info "[dry-run] would install a gitleaks pre-commit hook at $_dot_ih_hook"
        return 0
    fi

    dot_mkdir "$_dot_ih_dir" || return 1

    # 已有非我们的 hook 时不覆盖 —— 用户可能有自己的检查
    if [ -f "$_dot_ih_hook" ] && ! grep -q 'dotfiles-gitleaks-guard' "$_dot_ih_hook" 2>/dev/null; then
        dot_tip "$_dot_ih_hook exists and is not ours; leaving it alone"
        dot_tip '  add a gitleaks call to it yourself if you want the guard'
        return 0
    fi

    cat >"$_dot_ih_hook" <<'HOOK'
#!/usr/bin/env sh
# dotfiles-gitleaks-guard — 阻止把凭据提交进这个公开仓库。
#
# 由 modules/secrets 安装。删掉这个文件即可停用。

if ! command -v gitleaks >/dev/null 2>&1; then
    printf 'gitleaks not installed; secret scan SKIPPED for this commit\n' >&2
    printf '  install it to re-enable the guard\n' >&2
    exit 0
fi

# 只扫暂存内容 —— 扫整个历史会让每次提交都很慢。
#
# 用 `gitleaks git --staged`。注意不要用旧文档里的 `gitleaks protect --staged`：
# gitleaks 8.28 起把 protect/detect 换成了 git/dir/stdin，而 protect 仍会
# 被接受并「成功」返回 —— 实测扫描 0 commits、放过真实私钥，
# 守卫看起来在跑其实完全无效。

# 有仓库自己的 .gitleaks.toml 就显式用它（gitleaks 只在 cwd 找配置，
# 而 hook 的 cwd 在 worktree / 子目录提交时可能不是仓库根）。
# 没有配置也要能跑 —— 传一个不存在的路径会让 gitleaks 直接报错退出，
# 那等于守卫失效。
_gl_root=$(git rev-parse --show-toplevel 2>/dev/null)
_gl_cfg="$_gl_root/.gitleaks.toml"

if [ -f "$_gl_cfg" ]; then
    _gl_ok=0
    gitleaks git --staged --config "$_gl_cfg" --redact --no-banner || _gl_ok=1
else
    _gl_ok=0
    gitleaks git --staged --redact --no-banner || _gl_ok=1
fi

if [ "$_gl_ok" = 0 ]; then
    exit 0
fi

printf '\n' >&2
printf 'commit blocked: staged changes look like they contain credentials\n' >&2
printf 'the findings above show file and line (values are redacted)\n' >&2
printf '\n' >&2
printf 'if this is a false positive, add a rule to .gitleaks.toml\n' >&2
printf 'to bypass once (NOT recommended for real keys):  git commit --no-verify\n' >&2
exit 1
HOOK

    chmod +x "$_dot_ih_hook"
    dot_success "gitleaks pre-commit guard installed at $_dot_ih_hook"
}

# ---------------------------------------------------------------- ollama

# 本地推理工具。默认不装 —— 体积大（模型另算），并非每台机器都需要。
# 装了也**不自动拉取任何模型权重**：那是几个 GB 的下载，必须由用户决定。
_dot_sec_ollama() {
    if [ "${DOT_WANT_OLLAMA:-0}" != 1 ]; then
        dot_skip 'ollama: optional, not requested (set DOT_WANT_OLLAMA=1 to install)'
        return 0
    fi

    if command -v ollama >/dev/null 2>&1; then
        dot_skip "ollama already installed ($(command -v ollama))"
    else
        if dot_is_dry_run; then
            dot_info '[dry-run] would install ollama'
            return 0
        fi
        dot_pkg_install ollama </dev/null || {
            dot_error 'ollama installation failed'
            return 1
        }
    fi

    dot_tip 'no model weights were downloaded — pull one when you need it:'
    dot_tip '  ollama pull qwen2.5-coder:7b     (coding, ~4.7GB)'
    dot_tip '  ollama pull llama3.2:3b          (general, ~2GB)'
}

# ---------------------------------------------------------------- 汇报

# 报告哪些来源可用。只说来源，不碰任何值。
_dot_sec_report_sources() {
    dot_info 'secret sources available on this machine:'

    case $DOT_OS in
        macos)
            if command -v security >/dev/null 2>&1; then
                dot_success '  macOS keychain (preferred)'
            fi
            ;;
        linux)
            if command -v secret-tool >/dev/null 2>&1; then
                dot_success '  secret-tool / libsecret (preferred)'
            else
                dot_tip '  secret-tool not installed — install libsecret-tools for keyring support'
            fi
            ;;
    esac

    if command -v op >/dev/null 2>&1; then
        dot_success '  1Password CLI'
    else
        dot_tip '  1Password CLI not installed (optional)'
    fi

    [ -f "$DOT_ENV_LOCAL" ] && dot_success "  $DOT_ENV_LOCAL (fallback)"

    dot_tip 'store a credential with:  dot-secret set <NAME>'
    dot_tip 'load one into your shell:  dot_secret_load <NAME>'
}
