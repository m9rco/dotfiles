# 语言环境、编辑器、以及集中的镜像配置。
#
# 所有镜像设置都集中在本文件，改镜像只需动一处。
# 旧配置散落在多个文件里且指向已下线的 npm.taobao.org 系列域名。

# ---------------------------------------------------------------- locale

# 只在未设置时给默认值，尊重终端/系统已有的选择
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-$LANG}"

# ---------------------------------------------------------------- editor

# SSH 会话里用终端编辑器；本地留给 EDITOR 已有的值或回退 vim
if [[ -n "$SSH_CONNECTION" ]]; then
  export EDITOR=vim
else
  export EDITOR="${EDITOR:-vim}"
fi
export VISUAL="$EDITOR"

# 让 less 直接显示颜色转义，delta / bat 的输出才不会变成乱码
export LESS='-R -F -X'

# ---------------------------------------------------------------- mirrors
#
# 国内网络下的下载加速。旧的 npm.taobao.org 系列域名已下线，
# 现行地址是 npmmirror.com。
#
# 不需要镜像时把 DOT_NO_MIRRORS=1 写进 ~/.zshrc.local 即可整体关闭。

if [[ -z "$DOT_NO_MIRRORS" ]]; then
  # Homebrew bottles（仅 macOS/Linuxbrew 需要）
  if [[ -z "$HOMEBREW_BOTTLE_DOMAIN" ]]; then
    export HOMEBREW_BOTTLE_DOMAIN='https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles'
  fi

  # Node 生态的二进制下载
  export ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://npmmirror.com/mirrors/electron/}"
  export SASS_BINARY_SITE="${SASS_BINARY_SITE:-https://npmmirror.com/mirrors/node-sass}"
  export PUPPETEER_DOWNLOAD_BASE_URL="${PUPPETEER_DOWNLOAD_BASE_URL:-https://npmmirror.com/mirrors/chrome-for-testing}"
  export NODEJS_ORG_MIRROR="${NODEJS_ORG_MIRROR:-https://npmmirror.com/mirrors/node}"
fi

# ---------------------------------------------------------------- misc

# 不要把重复命令与以空格开头的命令写进历史（细节在 15-history.zsh）
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
