#!/usr/bin/env sh
#
# AI agent / skill / MCP 配置的部署。
#
# 两种部署方式，按内容性质选择：
#   - 符号链接：agents / skills / commands / hooks —— 纯文本定义，多工具可直接共享，
#     链接后改仓库即刻生效，无需重跑安装。
#   - 渲染：mcp.json / settings.json —— 含平台相关路径，且各工具 schema 不同，
#     必须替换占位符后写出。
#
# 渲染逻辑集中在本模块一处 —— AI 工具的配置格式还在快速演进，
# 集中意味着适配只改一个地方。
#
# shellcheck shell=sh

MODULE_DESC="AI agents, skills and MCP config (shared source of truth)"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="ai"

# 受管理的 AI 工具及其配置根目录。新增工具在这里加一行。
# 格式：<工具名>:<配置目录相对 $HOME 的路径>:<探测用的命令名>
DOT_AI_TOOLS="claude:.claude:claude"

install() {
    _dot_ai_src="$DOT_CONFIG_DIR/ai"

    if [ ! -d "$_dot_ai_src" ]; then
        dot_error "AI config source not found: $_dot_ai_src"
        return 1
    fi

    # 校验必须在任何写操作之前 —— 清单损坏时不能写出半份配置，
    # 那会用坏内容覆盖掉本来可用的配置。
    _dot_ai_validate_mcp "$_dot_ai_src/mcp.json" || return 1

    _dot_ai_failed=0

    for _dot_ai_entry in $DOT_AI_TOOLS; do
        _dot_ai_tool=$(printf '%s' "$_dot_ai_entry" | cut -d: -f1)
        _dot_ai_dir=$(printf '%s' "$_dot_ai_entry" | cut -d: -f2)
        _dot_ai_cmd=$(printf '%s' "$_dot_ai_entry" | cut -d: -f3)

        # 工具未安装则跳过它的配置，但不算失败 —— 在没装 Claude Code 的
        # 机器上为它铺配置没有意义，也不应让整个模块变红
        if ! command -v "$_dot_ai_cmd" >/dev/null 2>&1 && [ ! -d "$HOME/$_dot_ai_dir" ]; then
            dot_skip "$_dot_ai_tool not installed; skipping its config"
            continue
        fi

        dot_info "configuring $_dot_ai_tool"
        _dot_ai_deploy_claude "$_dot_ai_src" "$HOME/$_dot_ai_dir" || _dot_ai_failed=1
    done

    [ "$_dot_ai_failed" = 0 ]
}

# 渲染脚本写到临时文件再执行 —— 不能用 `cmd | python3 - <<'PY'`：
# 那样 heredoc 会占用 python 的 stdin，管道里的数据反而读不到（实测得到空输入）。
# 改为「数据走文件参数，脚本走文件」，两者都不占 stdin。
_dot_ai_pyrun() {
    _dot_py_script=$1
    shift

    _dot_py_tmp=$(mktemp) || return 1
    printf '%s' "$_dot_py_script" >"$_dot_py_tmp"
    python3 "$_dot_py_tmp" "$@"
    _dot_py_rc=$?
    rm -f "$_dot_py_tmp"
    return "$_dot_py_rc"
}

# ---------------------------------------------------------------- 校验

# mcp.json 必须是合法 JSON，且每个 server 条目必须有 command。
# 校验失败时报告具体问题并且不写出任何文件。
_dot_ai_validate_mcp() {
    _dot_mcp=$1

    if [ ! -f "$_dot_mcp" ]; then
        dot_error "mcp.json not found: $_dot_mcp"
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        dot_tip 'python3 not available; skipping mcp.json validation'
        return 0
    fi

    _dot_mcp_err=$(_dot_ai_pyrun '
import json, sys

path = sys.argv[1]
try:
    with open(path) as fh:
        data = json.load(fh)
except json.JSONDecodeError as exc:
    print("invalid JSON at line %d column %d: %s" % (exc.lineno, exc.colno, exc.msg))
    sys.exit(1)
except OSError as exc:
    print("cannot read: %s" % exc)
    sys.exit(1)

servers = data.get("mcpServers")
if servers is None:
    print("missing required top-level key: mcpServers")
    sys.exit(1)
if not isinstance(servers, dict):
    print("mcpServers must be an object, got %s" % type(servers).__name__)
    sys.exit(1)

for name, cfg in servers.items():
    if not isinstance(cfg, dict):
        print("server %r: entry must be an object" % name)
        sys.exit(1)
    # command 或 url 二者必有其一（stdio 传输 vs 远端传输）
    if not cfg.get("command") and not cfg.get("url"):
        print("server %r: missing required field \x27command\x27 (or \x27url\x27)" % name)
        sys.exit(1)
' "$_dot_mcp" 2>&1)

    if [ -n "$_dot_mcp_err" ]; then
        dot_error "mcp.json validation failed: $_dot_mcp_err"
        dot_error 'no tool config was written'
        return 1
    fi

    dot_success 'mcp.json is valid'
}

# ---------------------------------------------------------------- 渲染

# 把占位符替换为当前平台的实际值。
# 用 | 作 sed 分隔符，因为替换值里含 / 而不会含 |。
_dot_ai_render() {
    _dot_r_exe=''
    [ "$DOT_OS" = windows ] && _dot_r_exe='.exe'

    sed \
        -e "s|{{HOME}}|$HOME|g" \
        -e "s|{{DOTFILES}}|$DOT_ROOT|g" \
        -e "s|{{EXE}}|$_dot_r_exe|g"
}

# ---------------------------------------------------------------- 部署

_dot_ai_deploy_claude() {
    _dot_d_src=$1
    _dot_d_dst=$2
    _dot_d_rc=0

    # 目录整体链接：改仓库即刻生效，新增 agent/skill 无需重跑安装
    for _dot_d_sub in agents skills commands hooks; do
        [ -d "$_dot_d_src/$_dot_d_sub" ] || continue
        dot_link "$_dot_d_src/$_dot_d_sub" "$_dot_d_dst/$_dot_d_sub" || _dot_d_rc=1
    done

    # settings.json 需要渲染。合并策略见函数内说明。
    _dot_ai_merge_settings "$_dot_d_src/settings.json" "$_dot_d_dst/settings.json" || _dot_d_rc=1

    # MCP：Claude Code 读 ~/.claude/.mcp.json，schema 与我们的清单接近，
    # 只需剥掉注释与自定义字段后渲染
    _dot_ai_render_mcp_claude "$_dot_d_src/mcp.json" "$_dot_d_dst/.mcp.json" || _dot_d_rc=1

    return "$_dot_d_rc"
}

# settings.json 的合并：仓库管理的键覆盖，用户本地新增的键保留。
#
# 直接覆盖会丢掉用户在这台机器上单独加的设置；完全不动又无法下发变更。
# 折中：以现有文件为基底，用仓库版本的顶层键覆盖同名键，其余原样保留。
_dot_ai_merge_settings() {
    _dot_ms_src=$1
    _dot_ms_dst=$2

    [ -f "$_dot_ms_src" ] || return 0

    if ! command -v python3 >/dev/null 2>&1; then
        dot_tip 'python3 not available; linking settings.json instead of merging'
        dot_link "$_dot_ms_src" "$_dot_ms_dst"
        return $?
    fi

    # 渲染后的内容落到临时文件，作为参数传给 python —— 避免与脚本争 stdin
    _dot_ms_tmp=$(mktemp) || return 1
    _dot_ai_render <"$_dot_ms_src" >"$_dot_ms_tmp"

    # python 源码必须单引号 —— 里面的 $comment 等 $ 不能被 shell 展开
    # shellcheck disable=SC2016
    _dot_ms_out=$(_dot_ai_pyrun '
import json, sys, collections

with open(sys.argv[1]) as fh:
    repo = json.load(fh, object_pairs_hook=collections.OrderedDict)

# 注释键只用于仓库内的可读性，不写进实际配置
repo = collections.OrderedDict(
    (k, v) for k, v in repo.items() if not k.startswith("$comment")
)

dst = sys.argv[2]
try:
    with open(dst) as fh:
        merged = json.load(fh, object_pairs_hook=collections.OrderedDict)
except (OSError, json.JSONDecodeError):
    merged = collections.OrderedDict()

# 仓库管理的键覆盖；用户本地独有的顶层键保留
for key, value in repo.items():
    merged[key] = value

print(json.dumps(merged, indent=2, ensure_ascii=False))
' "$_dot_ms_tmp" "$_dot_ms_dst")
    _dot_ms_rc=$?
    rm -f "$_dot_ms_tmp"

    if [ "$_dot_ms_rc" != 0 ] || [ -z "$_dot_ms_out" ]; then
        dot_error 'failed to merge settings.json'
        return 1
    fi

    printf '%s\n' "$_dot_ms_out" | dot_write "$_dot_ms_dst"
}

# 渲染 Claude Code 的 .mcp.json：剥掉注释键与我们自己的元数据字段
# （description / platforms / optional 不属于 MCP schema）。
_dot_ai_render_mcp_claude() {
    _dot_rm_src=$1
    _dot_rm_dst=$2

    if ! command -v python3 >/dev/null 2>&1; then
        dot_tip 'python3 not available; skipping MCP config rendering'
        return 0
    fi

    _dot_rm_tmp=$(mktemp) || return 1
    _dot_ai_render <"$_dot_rm_src" >"$_dot_rm_tmp"

    _dot_rm_out=$(_dot_ai_pyrun '
import json, sys, collections

with open(sys.argv[1]) as fh:
    data = json.load(fh, object_pairs_hook=collections.OrderedDict)

servers = data.get("mcpServers", collections.OrderedDict())

# 只保留 MCP schema 认识的字段；其余是我们的清单元数据
allowed = ("command", "args", "env", "url", "headers", "type")
out = collections.OrderedDict()
for name, cfg in servers.items():
    out[name] = collections.OrderedDict(
        (k, v) for k, v in cfg.items() if k in allowed
    )

# 稳定输出：键顺序固定，缩进固定 —— 保证相同输入产生完全相同的文件，
# 否则每次运行都会「有变更」，幂等性就无从谈起
print(json.dumps({"mcpServers": out}, indent=4, ensure_ascii=False))
' "$_dot_rm_tmp")
    _dot_rm_rc=$?
    rm -f "$_dot_rm_tmp"

    if [ "$_dot_rm_rc" != 0 ] || [ -z "$_dot_rm_out" ]; then
        dot_error 'failed to render MCP config'
        return 1
    fi

    printf '%s\n' "$_dot_rm_out" | dot_write "$_dot_rm_dst"
}
