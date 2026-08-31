#!/usr/bin/env sh
#
# spec 覆盖度走查（tasks 11.10）。
#
# 把每条 spec requirement 映射到「实现在哪、由什么验证」，输出一份可复核的
# 追溯表。没有对应实现或验证的条目会被列为未覆盖并使脚本返回非零。
#
# 映射关系写在下面的 COVERAGE 数据里 —— 手工维护是有意的：
# 自动猜测「哪个测试覆盖哪条 requirement」只会产生看起来完整、实际无意义的
# 表格。这里每一行都是人读过 spec 后写下的判断。
#
#   sh test/spec_coverage.sh            # 人读的报告
#   sh test/spec_coverage.sh --check    # 只判断有无未覆盖项（CI 用）
#
# shellcheck shell=sh

set -u

DOT_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DOT_ROOT" || exit 1

SPEC_DIR=openspec/changes/modernize-dotfiles/specs

CHECK_ONLY=0
[ "${1:-}" = --check ] && CHECK_ONLY=1

TMP_MATCH=$(mktemp)
trap 'rm -f "$TMP_MATCH"' EXIT INT TERM

# ------------------------------------------------------------------ 覆盖映射
#
# 格式：<spec>|<requirement 名称的可识别片段>|<实现位置>|<验证方式>
#
# 验证方式的取值约定：
#   test:<file>     有断言测试
#   lint:<check>    由 lint 强制
#   manual:<说明>   实机验证过，附一句结论
#   ci:<job>        只能在 CI 环境验证
#   PENDING:<原因>  尚未验证 —— 这才是这份表格的价值所在

coverage_data() {
    cat <<'EOF'
platform-detection|操作系统识别|lib/detect.sh|test:detect_test.sh
platform-detection|CPU 架构识别|lib/detect.sh|test:detect_test.sh
platform-detection|Linux 发行版识别|lib/detect.sh|test:detect_test.sh
platform-detection|包管理器识别|lib/detect.sh|test:detect_test.sh
platform-detection|Homebrew 前缀探测|lib/detect.sh|test:detect_test.sh
platform-detection|WSL 环境识别|lib/detect.sh|test:detect_test.sh
platform-detection|无图形环境识别|lib/detect.sh|test:detect_test.sh
platform-detection|探测结果可查询|bootstrap.sh --info|test:detect_test.sh
platform-detection|模块代码不直接探测平台|modules/*|lint:modules-no-uname

bootstrap-installer|双入口引导程序|bootstrap.sh + bootstrap.ps1|test:runner_test.sh
bootstrap-installer|模块自描述与目录发现|lib/runner.sh|test:runner_test.sh
bootstrap-installer|平台适用性过滤|lib/runner.sh|test:runner_test.sh
bootstrap-installer|依赖排序|lib/runner.sh|test:runner_test.sh
bootstrap-installer|幂等执行|lib/fs.sh|test:runner_test.sh
bootstrap-installer|预演模式|lib/fs.sh|test:runner_test.sh
bootstrap-installer|选择性执行|bootstrap.sh|test:runner_test.sh
bootstrap-installer|模块清单查询|lib/runner.sh|test:runner_test.sh
bootstrap-installer|链接前备份|lib/fs.sh|test:fs_test.sh
bootstrap-installer|统一日志输出|lib/log.sh|test:runner_test.sh
bootstrap-installer|失败处理与退出码|lib/runner.sh|test:runner_test.sh
bootstrap-installer|帮助信息|bootstrap.sh|test:runner_test.sh

shell-environment|zsh 安装与默认 shell 设置|modules/zsh|test:cli_test.sh
shell-environment|zshrc 分片架构|config/zsh/zshrc + config/zsh/zshrc.d|manual:沙箱 HOME 载入零错误
shell-environment|本地覆盖不入库|config/zsh/zshrc.d/90-local.zsh|lint:no-tracked-local
shell-environment|Homebrew 环境正确加载|config/zsh/zshrc.d/10-path.zsh|manual:Apple Silicon 上 HOMEBREW_PREFIX=/opt/homebrew
shell-environment|失效镜像地址移除|config/zsh/zshrc.d/00-env.zsh|lint:no-dead-mirror
shell-environment|单一 zsh 框架|config/zsh|manual:config 下无 zimrc
shell-environment|条件化插件加载|config/zsh/zshrc.d/20-omz.zsh|manual:缺工具时启动零错误输出
shell-environment|starship 作为跨平台 prompt|config/starship.toml|manual:zsh 与 PowerShell 共用同一份
shell-environment|历史记录配置|config/zsh/zshrc.d/15-history.zsh|manual:HISTSIZE/SAVEHIST 实测 50000
shell-environment|启动性能预算|config/zsh + bin/dot-bench|manual:中位数 153ms（预算 200ms）
shell-environment|补全缓存|config/zsh/zshrc.d/25-completion.zsh|manual:单一 .zcompdump，失效后重建
shell-environment|PowerShell profile|config/powershell/profile.ps1|test:lint_ps.sh
shell-environment|跨 shell 共享配置|config/starship.toml|manual:两侧读同一文件

font-provisioning|Nerd Fonts 作为字体来源|config/fonts/fonts.txt|test:fonts_test.sh
font-provisioning|平台字体目录|platform/*|test:fonts_test.sh
font-provisioning|字体缓存刷新|platform/linux.sh|test:fonts_test.sh
font-provisioning|字体安装幂等|modules/fonts|test:fonts_test.sh
font-provisioning|无图形环境跳过|modules/fonts|test:fonts_test.sh
font-provisioning|下载失败处理|modules/fonts|test:fonts_test.sh
font-provisioning|终端字体指向|modules/fonts|manual:输出手动设置指引（无法可靠改终端配置）
font-provisioning|预演模式不下载|modules/fonts|test:fonts_test.sh

modern-cli-toolchain|声明式工具清单|config/cli/tools.txt|test:cli_test.sh
modern-cli-toolchain|默认工具集|config/cli/tools.txt|test:cli_test.sh
modern-cli-toolchain|包管理器不可用时的回退|lib/pkg.sh|test:cli_test.sh
modern-cli-toolchain|工具安装幂等|lib/pkg.sh|test:cli_test.sh
modern-cli-toolchain|shell 集成 hook|config/zsh/zshrc.d/30-tools.zsh|manual:zoxide/fzf 实测生效
modern-cli-toolchain|别名与传统命令共存|config/zsh/zshrc.d/40-aliases.zsh|manual:仅交互式生效，脚本用原命令
modern-cli-toolchain|delta 集成 git|config/git/gitconfig|manual:delta 缺失时回退 less 无报错
modern-cli-toolchain|跨平台一致的工具体验|config/cli + platform/*|test:cli_test.sh
modern-cli-toolchain|预演模式不安装|modules/modern-cli|test:cli_test.sh

ai-coding-clis|AI 编码 CLI 安装集|config/ai/clis.txt|test:ai_clis_test.sh
ai-coding-clis|三平台安装一致|modules/ai-clis|test:ai_clis_test.sh
ai-coding-clis|npm 全局安装的 PATH 处理|modules/ai-clis|test:ai_clis_test.sh
ai-coding-clis|安装幂等与升级|modules/ai-clis + bin/dot-ai-upgrade|test:ai_clis_test.sh
ai-coding-clis|版本检查为非阻断|modules/ai-clis|test:ai_clis_test.sh
ai-coding-clis|不在安装期要求凭据|modules/ai-clis|test:ai_clis_test.sh
ai-coding-clis|预演模式不安装|modules/ai-clis|test:ai_clis_test.sh

ai-agent-config|AI 配置单一真源|config/ai/|test:ai_config_test.sh
ai-agent-config|agent 与 skill 跨工具链接|modules/ai-agent-config|test:ai_config_test.sh
ai-agent-config|MCP 配置渲染|modules/ai-agent-config|test:ai_config_test.sh
ai-agent-config|清单格式校验|modules/ai-agent-config|test:ai_config_test.sh
ai-agent-config|配置的平台无关表示|config/ai/*|test:ai_config_test.sh
ai-agent-config|保留工具的本地配置|modules/ai-agent-config|test:ai_config_test.sh
ai-agent-config|幂等与预演|modules/ai-agent-config|test:ai_config_test.sh
ai-agent-config|工具未安装时的处理|modules/ai-agent-config|test:ai_config_test.sh

secrets-management|仓库内零明文密钥|全仓|test:secrets_test.sh
secrets-management|平台密钥库集成|lib/secrets.sh|test:secrets_test.sh
secrets-management|密码管理器支持|lib/secrets.sh|test:secrets_test.sh
secrets-management|本地环境文件兜底|lib/secrets.sh + modules/secrets|test:secrets_test.sh
secrets-management|shell 启动不同步读取密钥|config/zsh/zshrc.d/50-secrets.zsh|test:secrets_test.sh
secrets-management|误提交守卫|modules/secrets|test:secrets_test.sh
secrets-management|本地推理工具可选安装|modules/secrets|test:secrets_test.sh
secrets-management|密钥值不出现在日志|lib/secrets.sh|test:secrets_test.sh

legacy-migration|彻底移除全部 git 子模块|已执行|test:migration_test.sh
legacy-migration|vim 插件改由插件管理器管理|openspec/changes/modernize-dotfiles/notes/vim-plugins.md|test:migration_test.sh
legacy-migration|private 目录整体归档|legacy/private/|test:migration_test.sh
legacy-migration|新配置为重写而非搬迁|config/|lint:no-hardcoded-home
legacy-migration|旧安装脚本退出使用|legacy/private/install.sh|test:migration_test.sh
legacy-migration|目录结构重排|仓库根|test:migration_test.sh
legacy-migration|分阶段可用性|git 历史|manual:每阶段后 lint 与测试均通过
legacy-migration|CI 从 Travis 迁移到 GitHub Actions|.github/workflows/ci.yml|test:migration_test.sh
legacy-migration|既有用户升级路径|docs/UPGRADING.md|test:migration_test.sh
legacy-migration|文档更新|README.md|test:migration_test.sh
EOF
}

# 查找某条 requirement 的映射。回显 "<impl>|<verif>"，找不到则回显空。
#
# 单独写成函数而不是内联在循环里 —— `case ... ) cmd && break ;;` 嵌在
# 管道中的 while 里会让部分 shell 的解析器直接报语法错误。
find_coverage() {
    _fc_spec=$1
    _fc_req=$2

    coverage_data | grep "^${_fc_spec}|" >"$TMP_MATCH" 2>/dev/null || true

    while IFS='|' read -r _s _frag _impl _verif; do
        [ -n "$_frag" ] || continue
        case $_fc_req in
            *"$_frag"*)
                printf '%s|%s' "$_impl" "$_verif"
                return 0
                ;;
        esac
    done <"$TMP_MATCH"

    return 1
}

# ------------------------------------------------------------------ 自校验
#
# 这张映射表是手写的，所以它本身可能过时：引用了已删掉的测试文件、
# 或指向不存在的实现路径。下面把表里的引用逐个对照磁盘校验 ——
# 一张说谎的追溯表比没有表更糟。

verify_references() {
    _vr_bad=0

    # 引用的测试文件必须存在
    coverage_data | grep -o 'test:[A-Za-z0-9_]*\.sh' | sed 's/^test://' | sort -u |
        while IFS= read -r tf; do
            [ -n "$tf" ] || continue
            if [ ! -f "test/$tf" ]; then
                printf 'BROKEN REFERENCE: test/%s does not exist\n' "$tf"
            fi
        done >"$TMP_MATCH"

    if [ -s "$TMP_MATCH" ]; then
        cat "$TMP_MATCH"
        _vr_bad=1
    fi

    # 引用的实现路径必须存在。多路径写法（"a + b"）按加号拆开逐个查。
    coverage_data | while IFS='|' read -r _s _frag impl _v; do
        [ -n "$impl" ] || continue
        # 跳过非路径的描述性写法
        case $impl in
            全仓 | 已执行 | 仓库根 | 'git 历史') continue ;;
        esac
        printf '%s\n' "$impl" | tr '+' '\n' | while IFS= read -r one; do
            # 去掉首尾空格与命令参数（如 "bootstrap.sh --info"）
            one=$(printf '%s' "$one" | sed 's/^ *//; s/ *$//; s/ --.*//')
            [ -n "$one" ] || continue
            # 通配路径（platform/*）只查其父目录
            case $one in
                */\*) one=$(dirname "$one") ;;
            esac
            [ -e "$one" ] || printf 'BROKEN REFERENCE: %s does not exist\n' "$one"
        done
    done >"$TMP_MATCH"

    if [ -s "$TMP_MATCH" ]; then
        sort -u "$TMP_MATCH"
        _vr_bad=1
    fi

    return "$_vr_bad"
}

# ------------------------------------------------------------------ 校验

# 从 spec 文件里取出全部 requirement 名称
all_requirements() {
    for d in "$SPEC_DIR"/*/; do
        spec=$(basename "$d")
        f="$d/spec.md"
        [ -f "$f" ] || continue
        sed -n 's/^### Requirement: //p' "$f" | while IFS= read -r req; do
            printf '%s|%s\n' "$spec" "$req"
        done
    done
}

uncovered=''
covered=0
total=0

while IFS='|' read -r spec req; do
    [ -n "$spec" ] || continue
    total=$((total + 1))

    # 在映射表里找这条 requirement。用片段匹配 —— spec 里的名称可能带
    # 修饰词，映射表里记的是能唯一定位的核心片段。
    if hit=$(find_coverage "$spec" "$req"); then
        covered=$((covered + 1))
    else
        uncovered="$uncovered
  $spec :: $req"
    fi
done <<EOF
$(all_requirements)
EOF

# ------------------------------------------------------------------ 输出

if [ "$CHECK_ONLY" = 0 ]; then
    printf '# spec 覆盖度追溯\n\n'
    printf '生成命令：`sh test/spec_coverage.sh`\n\n'
    printf 'requirement 总数：%s\n\n' "$total"

    for d in "$SPEC_DIR"/*/; do
        spec=$(basename "$d")
        f="$d/spec.md"
        [ -f "$f" ] || continue

        nreq=$(grep -c '^### Requirement:' "$f")
        nsce=$(grep -c '^#### Scenario:' "$f")
        printf '## %s\n\n' "$spec"
        printf '%s 条 requirement / %s 个 scenario\n\n' "$nreq" "$nsce"
        printf '| Requirement | 实现 | 验证 |\n'
        printf '|---|---|---|\n'

        sed -n 's/^### Requirement: //p' "$f" | while IFS= read -r req; do
            if row=$(find_coverage "$spec" "$req"); then
                impl=${row%%|*}
                verif=${row#*|}
                printf '| %s | `%s` | %s |\n' "$req" "$impl" "$verif"
            else
                printf '| %s | **未映射** | **未覆盖** |\n' "$req"
            fi
        done
        printf '\n'
    done
fi

printf '\n'
printf 'covered: %s / %s\n' "$covered" "$total"

if [ -n "$uncovered" ]; then
    printf 'UNCOVERED requirements:%s\n' "$uncovered"
    exit 1
fi

# PENDING 项单独报告 —— 它们有映射但尚未验证
pending=$(coverage_data | grep '|PENDING:' || true)
if [ -n "$pending" ]; then
    printf '\nPENDING verification:\n'
    printf '%s\n' "$pending" | sed 's/^/  /'
fi

if ! verify_references; then
    printf '\nthe coverage table references things that do not exist — fix it\n'
    exit 1
fi

printf 'every requirement maps to an implementation and a verification method\n'
printf 'all referenced tests and implementation paths exist\n'
