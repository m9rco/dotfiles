#!/usr/bin/env bash

## get the real path of install.sh
SOURCE="${BASH_SOURCE[0]}"
# resolve $SOURCE until the file is no longer a symlink
while [ -L "$SOURCE" ]; do
  APP_PATH="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path
  # where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE="$APP_PATH/$SOURCE"
done
APP_PATH="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# color params
dot_color_none="\033[0m"
dot_color_dark="\033[0;30m"
dot_color_dark_light="\033[1;30m"
dot_color_red="\033[0;31m"
dot_color_red_light="\033[1;31m"
dot_color_green="\033[0;32m"
dot_color_green_light="\033[1;32m"
dot_color_yellow="\033[0;33m"
dot_color_yellow_light="\033[1;33m"
dot_color_blue="\033[0;34m"
dot_color_blue_light="\033[1;34m"
dot_color_purple="\033[0;35m"
dot_color_purple_light="\033[1;35m"
dot_color_cyan="\033[0;36m"
dot_color_cyan_light="\033[1;36m"
dot_color_gray="\033[0;37m"
dot_color_gray_light="\033[1;37m"

########## Basics setup
function msg(){
  printf '%b\n' "$*$dot_color_none" >&2
}
function prompt(){
  printf '%b' "$dot_color_purple[+] $*$dot_color_none "
}
function step(){
  msg "\n$dot_color_yellow[→] $*"
}
function info(){
  msg "$dot_color_cyan[>] $*"
}
function success(){
  msg "$dot_color_green[✓] $*"
}
function error(){
  msg "$dot_color_red_light[✗] $*"
}
function tip(){
  msg "$dot_color_red_light[!] $*"
}

function is_file_exists(){
  [[ -e "$1" ]] && return 0 || return 1
}
function is_dir_exists(){
  [[ -d "$1" ]] && return 0 || return 1
}
function is_program_exists(){
  if type "$1" &>/dev/null; then
    return 0
  else
    return 1
  fi;
}
function must_file_exists(){
  for file in $@; do
    if ( ! is_file_exists $file ); then
      error "You must have file *$file*"
      exit
    fi;
  done;
}
function better_program_exists_one(){
  local exists="no"
  for program in $@; do
    if ( is_program_exists "$program" ); then
      exists="yes"
      break
    fi;
  done;
  if [[ "$exists" = "no" ]]; then
    tip "Maybe you can take full use of this by installing one of ($*)~"
  fi;
}
function must_program_exists(){
  for program in $@; do
    if ( ! is_program_exists "$program" ); then
      error "You must have *$program* installed!"
      exit
    fi;
  done;
}

function is_platform(){
  [[ `uname` = "$1" ]] && return 0 || return 1
}
function is_linux(){
  ( is_platform Linux ) && return 0 || return 1
}
function is_mac(){
  ( is_platform Darwin ) && return 0 || return 1
}

function lnif(){
  if [ -e "$1" ]; then
    info "Linking $1 to $2"
    if ( ! is_dir_exists `dirname "$2"` ); then
      mkdir -p `dirname "$2"`
    fi;
    rm -rf "$2"
    ln -s "$1" "$2"
  fi;
}

function sync_repo(){

  must_program_exists "git"

  local repo_uri=$1
  local repo_path=$2
  local repo_branch=${3:-master}
  local repo_name=${1:19} # length of (https://github.com/)

  if ( ! is_dir_exists "$repo_path" ); then
    info "Cloning $repo_name ..."
    mkdir -p "$repo_path"
    git clone --depth 1 --branch "$repo_branch" "$repo_uri" "$repo_path"
    success "Successfully cloned $repo_name."
  else
    info "Updating $repo_name ..."
    cd "$repo_path" && git pull origin "$repo_branch"
    success "Successfully updated $repo_name."
  fi;

  if ( is_file_exists "$repo_path/.gitmodules" ); then
    info "Updating $repo_name submodules ..."
    cd "$repo_path"
    git submodule update --init --recursive
    success "Successfully updated $repo_name submodules."
  fi;
}

function util_must_python_pipx_exists(){
  if ( ! is_program_exists pip ) && ( ! is_program_exists pip2 ) && ( ! is_program_exists pip3 ); then
    error "You must have installed pip or pip2 or pip3 for installing python packages."
    exit
  fi;
}

########## Steps setup

function dir_list(){
  path=$1
  files=$(ls $path|grep -v 'build.sh')
  echo
  echo 'Usage: build.sh <task>[ taskFoo taskBar ...]'
  echo
  echo 'Tasks:'
  printf "$dot_color_green\n"
  for filename in $files
do
  echo '    - '$filename
done
  printf "$dot_color_none\n"
}


function usage(){
  echo
  echo 'Usage: install.sh <task>[ taskFoo taskBar ...]'
  echo
  echo 'Tasks:'
  printf "$dot_color_green\n"
  echo '    - astyle_rc'
  echo '    - bin'
  echo '    - editorconfig'
  echo '    - emacs'
  echo '    - emacs_spacemacs'
  echo '    - fonts_source_code_pro'
  echo '    - git_config'
  echo '    - git_diff_fancy'
  echo '    - git_dmtool'
  echo '    - git_extras'
  echo '    - git_flow'
  echo '    - sublime2'
  echo '    - sublime3'
  echo '    - tmux'
  echo '    - vim_rc'
  echo '    - vim_plugins'
  echo '    - vim_plugins_fcitx'
  echo '    - vim_plugins_matchtag'
  echo '    - vim_plugins_snippets'
  echo '    - vim_plugins_ycm'
  echo '    - vscode'
  echo '    - zsh_rc'
  echo '    - zsh_plugins_fasd'
  echo '    - zsh_plugins_fzf'
  echo '    - zsh_plugins_thefuck'
  printf "$dot_color_none\n"
}

function install_astyle_rc(){

  must_program_exists "astyle"

  step "Installing astylerc ..."

  lnif "$APP_PATH/astyle/astylerc" \
       "$HOME/.astylerc"

  success "Successfully installed astylerc."
}

function install_bin(){

  step "Installing useful small scripts ..."

  local source_path="$APP_PATH/bin"

  for bin in `ls -p $source_path | grep -v /`; do
    lnif "$source_path/$bin" "$HOME/bin/$bin"
  done;

  success "Successfully installed useful scripts."
}

function install_editorconfig(){

  step "Installing editorconfig ..."

  lnif "$APP_PATH/editorconfig/editorconfig" \
       "$HOME/.editorconfig"

  tip "Maybe you should install editorconfig plugin for vim or sublime"
  success "Successfully installed editorconfig."
}

function install_emacs(){

  must_program_exists "emacs"

  step "Installing emacs config ..."

  local prompt=false
  local repo_uri="https://github.com/Wyntau/emacs.d.git"

  if ( is_dir_exists "$HOME/.emacs.d" ); then
    if [[ $repo_uri != `cd $HOME/.emacs.d && git remote get-url origin 2> /dev/null` ]]; then
      tip "Your old .emacs.d is not the .emacs.d to be installed."
      prompt=true
    fi;
  fi;

  if [[ $prompt == true ]]; then
    prompt "Do you want to override your old .emacs.d? (y/n) "
    read override
    case $override in
      y|Y|'')
        info "Remove old .emacs.d"
        rm -rf $HOME/.emacs.d
        ;;
      n|N)
        info "Do not override your old .emacs.d. Please remove or backup yourself."
        return
        ;;
      *)
        error "invalid option"
        exit
    esac;
  fi;

  sync_repo "$repo_uri" "$HOME/.emacs.d"

  lnif "$APP_PATH/bin/emacs/ec" "$HOME/bin/ec"
  lnif "$APP_PATH/bin/emacs/et" "$HOME/bin/et"
  lnif "$APP_PATH/bin/emacs/es" "$HOME/bin/es"

  success "Successfully installed emacs config."
}

function install_emacs_spacemacs(){

  must_program_exists "emacs"

  step "Installing spacemacs config ..."

  local prompt=false
  local repo_spacemacs_uri="https://github.com/syl20bnr/spacemacs.git"
  local repo_config_uri="https://github.com/Wyntau/spacemacs.d.git"

  if ( is_dir_exists "$HOME/.emacs.d" ); then
    local exist_repo_uri=`cd $HOME/.emacs.d && git remote get-url origin 2> /dev/null`
    if [[ $repo_spacemacs_uri != "$exist_repo_uri" ]] &&
       [[ $repo_spacemacs_uri != "$exist_repo_uri.git" ]]; then
      tip "Your old .emacs.d is not spacemacs repo."
      prompt=true
    fi;
  fi;

  if [[ $prompt == true ]]; then
    prompt "Do you want to override your old .emacs.d? (y/n) "
    read override
    case $override in
      y|Y|'')
        info "Remove old .emacs.d"
        rm -rf $HOME/.emacs.d
        ;;
      n|N)
        info "Do not override your old .emacs.d. Please remove or backup yourself."
        return
        ;;
      *)
        error "invalid option"
        exit
    esac;
  fi;

  sync_repo "$repo_spacemacs_uri" \
            "$HOME/.emacs.d" \
            "develop"

  sync_repo "$repo_config_uri" \
            "$HOME/.spacemacs.d"

  lnif "$APP_PATH/bin/emacs/ec" "$HOME/bin/ec"
  lnif "$APP_PATH/bin/emacs/et" "$HOME/bin/et"
  lnif "$APP_PATH/bin/emacs/es" "$HOME/bin/es"

  success "Successfully installed spacemacs and config."

  # only install the font locally
  if [ -z "$SSH_CONNECTION" ]; then
    install_fonts_source_code_pro
  else
    tip "Maybe you should install the font *Source Code Pro* locally."
  fi;
}

function install_fonts_source_code_pro(){

  if ( ! is_mac ) && ( ! is_linux ); then
    error "This support *Linux* and *Mac* only"
    exit
  fi;

  must_program_exists "git"

  step "Installing font Source Code Pro ..."

  sync_repo "https://github.com/adobe-fonts/source-code-pro.git" \
            "$APP_PATH/.cache/source-code-pro" \
            "release"

  local source_code_pro_ttf_dir="$APP_PATH/.cache/source-code-pro/TTF"

  # borrowed from powerline/fonts/install.sh
  local find_command="find \"$source_code_pro_ttf_dir\" \( -name '*.[o,t]tf' -or -name '*.pcf.gz' \) -type f -print0"

  local fonts_dir

  if ( is_mac ); then
    # MacOS
    fonts_dir="$HOME/Library/Fonts"
  else
    # Linux
    fonts_dir="$HOME/.fonts"
    mkdir -p $fonts_dir
  fi

  # Copy all fonts to user fonts directory
  eval $find_command | xargs -0 -I % cp "%" "$fonts_dir/"

  # Reset font cache on Linux
  if [[ -n `which fc-cache` ]]; then
    fc-cache -f $fonts_dir
  fi

  success "Successfully installed Source Code Pro font."
}

function install_git_config(){

  must_program_exists "git"

  step "Installing gitconfig ..."

  lnif "$APP_PATH/git/gitconfig" \
       "$HOME/.gitconfig"

  info "Now config your name and email for git."

  local user_now=`whoami`

  prompt "What's your git username? ($user_now) "

  local user_name
  read user_name
  if [ "$user_name" = "" ]; then
    user_name=$user_now
  fi;
  git config --global user.name $user_name

  prompt "What's your git email? ($user_name@example.com) "

  local user_email
  read user_email
  if [ "$user_email" = "" ]; then
    user_email=$user_now@example.com
  fi;
  git config --global user.email $user_email

  if ( is_mac ); then
    git config --global credential.helper osxkeychain
  fi;

  success "Successfully installed gitconfig."
}
