# 历史记录。
#
# 目标：跨会话共享、条目足够多、去掉连续重复、带时间戳。

HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=50000          # 内存中保留的条目数
SAVEHIST=50000          # 写入文件的条目数（须 >= 10000）

# 追加而非覆盖，且立即写入 —— 否则多个并行 shell 会互相覆盖历史，
# 且异常退出的会话会丢掉全部历史
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY

# 多个 shell 之间实时共享历史
setopt SHARE_HISTORY

# 连续重复的命令只记一条
setopt HIST_IGNORE_DUPS
# 新命令与历史中的旧条目重复时，删掉旧的那条
setopt HIST_IGNORE_ALL_DUPS
# 写入时跳过与上一条完全相同的记录
setopt HIST_SAVE_NO_DUPS

# 以空格开头的命令不记入历史 —— 临时敏感命令的常规做法
setopt HIST_IGNORE_SPACE

# 记录时间戳与耗时
setopt EXTENDED_HISTORY

# 折叠多余空白后再记录
setopt HIST_REDUCE_BLANKS

# 历史展开（!!）先展示结果再执行，避免误操作
setopt HIST_VERIFY

# 目录栈也当作历史用：cd - 加 TAB 可跳回历史路径
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
