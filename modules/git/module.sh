#!/usr/bin/env sh
#
# git 配置。
#
# 身份（name/email）不入库 —— 写进 ~/.gitconfig.local，由 config/git/gitconfig
# 的 [include] 引入。这样公开仓库里不出现邮箱，换工作机也不用改仓库。
#
# shellcheck shell=sh

MODULE_DESC="git config, global gitignore and delta integration"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="core git"

install() {
    if ! dot_pkg_installed git; then
        dot_info 'git not found; installing'
        dot_pkg_install git </dev/null || return 1
    fi

    dot_link "$DOT_CONFIG_DIR/git/gitconfig" "$HOME/.gitconfig" || return 1
    dot_link "$DOT_CONFIG_DIR/git/gitignore_global" "$HOME/.gitignore_global" || return 1

    _dot_git_identity || return 1
    _dot_git_credential_helper
    _dot_git_delta_note
}

# ---------------------------------------------------------------- 身份

# 确保 ~/.gitconfig.local 里有 user.name 与 user.email。
# 已有则不动 —— 这个文件属于用户，不是我们的生成物。
_dot_git_identity() {
    _dot_gi_local="$HOME/.gitconfig.local"

    # 用 --global 查（含被它 include 的 .gitconfig.local），而不是 --get：
    # 后者会把当前仓库的 .git/config 也算进来，于是在任意仓库目录下运行
    # 都会「看到」身份已设置，导致新机器上永远不提示，最后用错邮箱提交。
    _dot_gi_name=$(git config --global --get user.name 2>/dev/null || true)
    _dot_gi_email=$(git config --global --get user.email 2>/dev/null || true)

    if [ -n "$_dot_gi_name" ] && [ -n "$_dot_gi_email" ]; then
        dot_skip "git identity already set ($_dot_gi_name <$_dot_gi_email>)"
        return 0
    fi

    if dot_is_dry_run; then
        dot_info "[dry-run] would ask for git user.name/user.email and write $_dot_gi_local"
        return 0
    fi

    # 非交互环境不能问 —— 会挂住 CI。留提示让用户之后自己配。
    if [ "$DOT_HEADLESS" = 1 ] || [ ! -t 0 ]; then
        dot_skip 'headless/non-interactive; not prompting for git identity'
        dot_tip "set it later:  git config --file $_dot_gi_local user.name 'Your Name'"
        dot_tip "               git config --file $_dot_gi_local user.email you@example.com"
        return 0
    fi

    dot_info 'git identity is not configured yet'

    if [ -z "$_dot_gi_name" ]; then
        dot_prompt 'git user.name:'
        read -r _dot_gi_name
    fi
    if [ -z "$_dot_gi_email" ]; then
        dot_prompt 'git user.email:'
        read -r _dot_gi_email
    fi

    if [ -z "$_dot_gi_name" ] || [ -z "$_dot_gi_email" ]; then
        dot_tip 'left blank; skipping git identity (commits will fail until it is set)'
        return 0
    fi

    # 写进 local 文件而非 ~/.gitconfig —— 后者是指向仓库的符号链接，
    # 往里写会把身份写进公开仓库
    git config --file "$_dot_gi_local" user.name "$_dot_gi_name" || return 1
    git config --file "$_dot_gi_local" user.email "$_dot_gi_email" || return 1
    chmod 600 "$_dot_gi_local" 2>/dev/null || true

    dot_success "git identity written to $_dot_gi_local (not tracked by this repo)"
}

# ---------------------------------------------------------------- 凭据

# 凭据存储方式按平台选。这个值必须写进 local 文件 ——
# 它是平台相关的，不能进跨平台共享的 gitconfig。
_dot_git_credential_helper() {
    _dot_gc_local="$HOME/.gitconfig.local"

    _dot_gc_current=$(git config --global --get credential.helper 2>/dev/null || true)
    if [ -n "$_dot_gc_current" ]; then
        dot_skip "credential helper already set ($_dot_gc_current)"
        return 0
    fi

    case $DOT_OS in
        macos) _dot_gc_want=osxkeychain ;;
        linux)
            # gh 装了就用它管 GitHub 凭据，省掉手工存 token
            if command -v gh >/dev/null 2>&1; then
                dot_tip "run 'gh auth login' to let gh manage GitHub credentials"
            fi
            # libsecret 需要额外编译，多数发行版没现成的；不强行设置
            dot_skip 'no credential helper configured on linux (use gh auth or a keyring helper)'
            return 0
            ;;
        *) return 0 ;;
    esac

    if dot_is_dry_run; then
        dot_info "[dry-run] would set credential.helper=$_dot_gc_want"
        return 0
    fi

    git config --file "$_dot_gc_local" credential.helper "$_dot_gc_want" &&
        dot_success "credential.helper set to $_dot_gc_want"
}

# ---------------------------------------------------------------- delta

_dot_git_delta_note() {
    if command -v delta >/dev/null 2>&1; then
        dot_success "delta is available; git diff will use it"
    else
        dot_tip 'delta not installed; git falls back to less (install it via the modern-cli module)'
    fi
}
