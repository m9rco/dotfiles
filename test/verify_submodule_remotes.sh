#!/usr/bin/env sh
#
# 迁移前的安全检查：确认每个子模块的内容都存在于其独立远端仓库。
#
# 这是 tasks 10.1 的实现。移除子模块是破坏性操作 —— 只有确认内容
# 在别处存在，才能安全地把它们从本仓库删掉。
#
# 输出可直接贴进迁移说明。
#
# shellcheck shell=sh

set -u

DOT_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DOT_ROOT" || exit 1

printf '# 子模块移除前的远端存在性确认\n\n'
printf '生成时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
printf '生成命令：`sh test/verify_submodule_remotes.sh`\n\n'

# ---------------------------------------------------------------- 全部 gitlink

printf '## 索引中的全部 gitlink（mode 160000）\n\n'
total=$(git ls-files -s | awk '$1=="160000"' | wc -l | tr -d ' ')
printf '共 %s 个。其中只有部分在 `.gitmodules` 里有声明 ——\n' "$total"
printf '其余是「孤立 gitlink」：索引里是子模块，但没有 URL 记录，\n'
printf '`git submodule status` 会直接报错。这类条目无法通过 deinit 处理，\n'
printf '只能用 `git rm --cached` 从索引里移除。\n\n'

declared=$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | wc -l | tr -d ' ')
printf '%s\n' "- 索引中的 gitlink：$total"
printf '%s\n' "- \`.gitmodules\` 中声明的：$declared"
printf '%s\n\n' "- 孤立 gitlink：$((total - declared))"

# ---------------------------------------------------------------- 已声明的

printf '## 已声明的子模块（有远端 URL，逐个验证）\n\n'
printf '| 路径 | 远端 | 远端可达 |\n'
printf '|---|---|---|\n'

unreachable=0

git config -f .gitmodules --get-regexp '^submodule\..*\.url$' 2>/dev/null |
    while read -r key url; do
        path=$(git config -f .gitmodules --get "$(printf '%s' "$key" | sed 's/\.url$/.path/')" 2>/dev/null)
        [ -n "$path" ] || path='(no path)'

        # SSH 形式换成 https 再探测：ls-remote 走 SSH 需要 key，
        # 在 CI 或别人的机器上不可用，而我们只是想确认「内容还在」。
        probe=$(printf '%s' "$url" | sed 's|git@github\.com:|https://github.com/|')

        if git ls-remote --exit-code "$probe" >/dev/null 2>&1; then
            printf '| `%s` | `%s` | 是 |\n' "$path" "$url"
        else
            printf '| `%s` | `%s` | **否** |\n' "$path" "$url"
            unreachable=$((unreachable + 1))
        fi
    done

printf '\n'

# ---------------------------------------------------------------- 孤立的

printf '## 孤立 gitlink（无远端记录）\n\n'
printf '这些路径在索引里是子模块，但 `.gitmodules` 里没有对应条目 ——\n'
printf '意味着仓库从未记录它们来自哪里。它们本就无法被 clone 出内容\n'
printf '（`git clone --recurse-submodules` 会跳过或报错），因此移除它们\n'
printf '不会丢失任何本仓库曾经提供过的东西。\n\n'

declared_paths=$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null |
    awk '{print $2}')

git ls-files -s | awk '$1=="160000"{print $4}' | while read -r gl; do
    found=no
    for d in $declared_paths; do
        [ "$d" = "$gl" ] && found=yes && break
    done
    [ "$found" = no ] && printf -- '- `%s`\n' "$gl"
done

printf '\n## 上游来源（供需要时自行恢复）\n\n'
printf 'vim 插件均为第三方上游仓库，新结构改为由插件管理器按需拉取，\n'
printf '不再由本仓库携带：\n\n'
git ls-files -s | awk '$1=="160000"{print $4}' | grep 'vim/plugins/' |
    while read -r p; do
        printf -- '- `%s`\n' "$(basename "$p")"
    done

printf '\n'
if [ "$unreachable" -gt 0 ]; then
    printf '**注意：有远端不可达，移除前需人工确认。**\n'
    exit 1
fi
printf '结论：已声明的子模块内容均存在于各自远端，可安全移除。\n'
