# || 尝试用 exec zsh
export ZSH=$HOME/.oh-my-zsh

# 主题
ZSH_THEME="robbyrussell"
#ZSH_THEME="agnoster"

# 插件
plugins=(git zsh-syntax-highlighting zsh-autosuggestions laravel5 tmux)

source $ZSH/oh-my-zsh.sh

# 不造
#setopt HIST_IGNORE_ALL_DUPS

#$color{{{
#autoload colors
#colors
#for color in RED GREEN YELLOW BLUE MAGENTA CYAN WHITE; do
#eval _$color='%{$terminfo[bold]$fg[${(L)color}]%}'
#eval $color='%{$fg[${(L)color}]%}'
#(( count = $count + 1 ))
#done
#FINISH="%{$terminfo[sgr0]%}"
#}}}

#命令提示符
# 时间 | PS1

#RPROMPT=$(echo "$RED%D %T$FINISH")
#PROMPT=$(echo "$CYAN%n@$YELLOW%m:$GREEN%/$_YELLOW $ $FINISH")

# 禁用用户名
#DEFAULT_USER='pushaowei'

gitRecreateBranch() {
    git checkout master
    git checkout -b $1
    git push origin $1
    git branch --set-upstream-to=origin/$1 $1
}
alias git-recreate=gitRecreateBranch
#alias git checkout -b=gitRecreateBranch()

#编辑器
export EDITOR=vim
#输入法
export XMODIFIERS="@im=ibus"
export QT_MODULE=ibus
export GTK_MODULE=ibus
#关于历史纪录的配置 {{{
#历史纪录条目数量
export HISTSIZE=10000
#注销后保存的历史纪录条目数量
export SAVEHIST=10000
#历史纪录文件
export HISTFILE=~/.zhistory
#以附加的方式写入历史纪录
setopt INC_APPEND_HISTORY
#如果连续输入的命令相同，历史纪录中只保留一个
setopt HIST_IGNORE_DUPS
#为历史纪录中的命令添加时间戳
setopt EXTENDED_HISTORY

#启用 cd 命令的历史纪录，cd -[TAB]进入历史路径
setopt AUTO_PUSHD
#相同的历史路径只保留一个
setopt PUSHD_IGNORE_DUPS


# 设置locale

#重启 fpm
#kill -USR2 `cat /usr/local/var/run/php-fpm.pid`

# 指令高亮效果
source ~/Applications/font_highlighting/zsh-syntax-highlighting.zsh
export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.ustc.edu.cn/homebrew-bottles

#PATH
source ~/.aliases
source ~/.bash_profile
export PATH="/usr/local/opt/go@1.8/bin:$PATH"
export BACKEND_PATH="/Users/pushaowei/develop/children/kids-web-server/src/www"




export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
