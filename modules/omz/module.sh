#!/usr/bin/env sh
#
# oh-my-zsh 框架与自定义插件的安装。
#
# 为什么单独成一个模块而不是并进 modules/zsh：zsh 模块装的是 shell 本体
# 与配置链接，那是「shell 能用」的前提；omz 与插件是从网络拉取的第三方
# 内容，失败不该让 shell 配置也一起失败。拆开后 --skip omz 也能单独跳过。
#
# 配置侧的对应片段是 config/zsh/zshrc.d/20-omz.zsh —— 它在
# $ZSH/oh-my-zsh.sh 不存在时整段 return，所以没有本模块的话，那份片段
# 在新机器上永远是空转，插件列表里的 zsh-autosuggestions 等也永远不生效。
#
# shellcheck shell=sh

MODULE_DESC="oh-my-zsh framework + custom plugins (autosuggestions, syntax-highlighting)"
MODULE_PLATFORMS="macos linux"
MODULE_TAGS="core shell"
# zsh 本体与 ~/.zshrc 要先就位：omz 装完即被下一次启动加载，
# 而那份 zshrc 正是加载它的入口。
#
# git 也是硬依赖 —— 装 omz 与插件全靠 git clone。不声明它的后果不是
# 顺序错乱（默认顺序里 git 本来就在前），而是 `--only omz` 在一台没有
# git 的新机器上直接失败：--only 只会带上声明过的依赖，git 不在其中。
MODULE_REQUIRES="zsh git"

# 自定义插件清单。
#
# 目录名必须与 config/zsh/zshrc.d/20-omz.zsh 里的探测路径
# "$ZSH/custom/plugins/$1/$1.plugin.zsh" 对得上 —— 两处名字漂移的话
# 插件装好了却不会被加载，且没有任何报错。test/omz_test.sh 交叉验证这一点。
DOT_OMZ_PLUGINS='zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search'

# 插件名 -> 上游仓库。三个都在 zsh-users 组织下。
_dot_omz_plugin_repo() {
    case $1 in
        zsh-autosuggestions) printf 'https://github.com/zsh-users/zsh-autosuggestions.git' ;;
        zsh-syntax-highlighting) printf 'https://github.com/zsh-users/zsh-syntax-highlighting.git' ;;
        zsh-history-substring-search) printf 'https://github.com/zsh-users/zsh-history-substring-search.git' ;;
        *) printf '' ;;
    esac
}

install() {
    # git 是硬前提。缺了它 clone 会以一句 "command not found" 失败，
    # 那只在 stderr 留一行，模块却可能照样往下走 —— 显式检查把这种
    # 情况变成明确的失败（同 modules/modern-cli 对平台适配层的检查）。
    if ! command -v git >/dev/null 2>&1; then
        dot_error 'git is required to install oh-my-zsh but is not available'
        dot_tip 'install git first, then re-run: ./bootstrap.sh --only omz'
        return 1
    fi

    # 安装目录。刻意不读 $ZSH —— 那个变量由交互式 shell 导出（见
    # 20-omz.zsh），在已经装好 omz 的机器上跑引导时它指向真实的家目录，
    # 会让 HOME 沙箱失效：测试以为在临时目录里操作，实际写进了 ~/.oh-my-zsh。
    # 覆盖入口是 DOT_OMZ_DIR，与 DOT_FONT_DIR 同理（见 platform/macos.sh）。
    _dot_omz_dir="${DOT_OMZ_DIR:-$HOME/.oh-my-zsh}"

    _dot_omz_install_framework || return 1

    # ------------------------------------------------------------ 插件
    #
    # 单个插件装不上不中断其余 —— 一个仓库不可达不该让整个 shell 配置失败，
    # 且 20-omz.zsh 对每个插件都是按存在性加载的，缺失只是少一个功能。
    _dot_omz_ok=0
    _dot_omz_skipped=0
    _dot_omz_failed=''

    for _dot_omz_p in $DOT_OMZ_PLUGINS; do
        _dot_omz_install_plugin "$_dot_omz_p"
        case $? in
            0) _dot_omz_ok=$((_dot_omz_ok + 1)) ;;
            2) _dot_omz_skipped=$((_dot_omz_skipped + 1)) ;;
            *) _dot_omz_failed="$_dot_omz_failed $_dot_omz_p" ;;
        esac
    done

    dot_info "plugins installed: $_dot_omz_ok · already present: $_dot_omz_skipped"

    if [ -n "$_dot_omz_failed" ]; then
        dot_error "could not install plugin(s):$_dot_omz_failed"
        dot_tip 'zsh still works; 20-omz.zsh loads plugins only when present'
        return 1
    fi
}

# 装 omz 本体。已存在则跳过，不做更新 —— 见下面关于不擅自 pull 的说明。
_dot_omz_install_framework() {
    if [ -f "$_dot_omz_dir/oh-my-zsh.sh" ]; then
        dot_skip "oh-my-zsh already installed ($_dot_omz_dir)"
        return 0
    fi

    # 目录存在但没有 oh-my-zsh.sh：可能是上次 clone 中断留下的残骸，也可能
    # 是用户放了别的东西。不主动删 —— 直接 clone 会因非空目录失败，那个
    # 错误信息比我们悄悄删掉用户的目录要好。
    if [ -d "$_dot_omz_dir" ] && [ -n "$(ls -A "$_dot_omz_dir" 2>/dev/null)" ]; then
        dot_error "$_dot_omz_dir exists but has no oh-my-zsh.sh"
        dot_tip 'remove or move it, then re-run — refusing to clone into a non-empty directory'
        return 1
    fi

    if dot_is_dry_run; then
        dot_info "[dry-run] would clone oh-my-zsh into $_dot_omz_dir"
        return 0
    fi

    dot_info 'installing oh-my-zsh'

    # --depth 1：只要工作树，不要十几年的提交历史。完整 clone 是几十 MB
    # 且没有任何用处 —— 同 modules/fonts 不 clone 字体源码仓库的理由。
    if git clone --depth 1 --quiet \
        https://github.com/ohmyzsh/ohmyzsh.git "$_dot_omz_dir" </dev/null; then
        dot_success "oh-my-zsh installed ($_dot_omz_dir)"
    else
        dot_error 'failed to clone oh-my-zsh'
        return 1
    fi
}

# 装单个自定义插件。
#
# 返回：0 = 装好了，2 = 已存在跳过，1 = 失败。
# 用 2 区分「跳过」与「新装」，好让上层汇总时不把幂等跳过算成安装。
_dot_omz_install_plugin() {
    _dot_omzp_name=$1
    _dot_omzp_url=$(_dot_omz_plugin_repo "$_dot_omzp_name")

    if [ -z "$_dot_omzp_url" ]; then
        dot_error "no upstream repository known for plugin '$_dot_omzp_name'"
        return 1
    fi

    _dot_omzp_dest="$_dot_omz_dir/custom/plugins/$_dot_omzp_name"

    # 幂等判定用插件入口文件，与 20-omz.zsh 的判定条件完全一致 ——
    # 目录存在但入口缺失时它不会加载，所以那种情况不算已安装。
    if [ -f "$_dot_omzp_dest/$_dot_omzp_name.plugin.zsh" ]; then
        dot_skip "$_dot_omzp_name already installed"
        return 2
    fi

    # 已有目录但没有入口文件：同框架那里的理由，不擅自删用户的东西。
    if [ -d "$_dot_omzp_dest" ] && [ -n "$(ls -A "$_dot_omzp_dest" 2>/dev/null)" ]; then
        dot_error "$_dot_omzp_dest exists but has no $_dot_omzp_name.plugin.zsh"
        dot_tip 'remove or move it, then re-run'
        return 1
    fi

    if dot_is_dry_run; then
        dot_info "[dry-run] would clone $_dot_omzp_name into $_dot_omzp_dest"
        return 0
    fi

    # 父目录要先有。dry-run 已在上面返回，这里不会误创建。
    dot_mkdir "$_dot_omz_dir/custom/plugins" || return 1

    if git clone --depth 1 --quiet "$_dot_omzp_url" "$_dot_omzp_dest" </dev/null; then
        dot_success "$_dot_omzp_name installed"
        return 0
    fi

    dot_error "$_dot_omzp_name: clone failed"
    # 失败会留下半个目录，它会让下一次运行撞上「目录非空」的检查。
    # 这个是我们自己造成的，可以清掉。
    rm -rf "$_dot_omzp_dest" 2>/dev/null
    return 1
}
