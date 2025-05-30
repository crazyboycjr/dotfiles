alias ls='ls --color=auto -v'
alias tmux="TERM=screen-256color-bce tmux"

source /run/current-system/sw/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /run/current-system/sw/share/zsh/plugins/nix/init.zsh

export FPATH=/run/current-system/sw/share/zsh/site-functions:$FPATH

export PATH=/usr/local/sbin:/run/current-system/sw/bin:$PATH
export ZSH_DISABLE_COMPFIX="true"

export HISTFILESIZE=400000000
export HISTSIZE=1000000
export GPG_TTY=$(tty)
# if [ -e /Users/cjr/.nix-profile/etc/profile.d/nix.sh ]; then . /Users/cjr/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

# fix zsh completion for nix experimental features
function _nix() {
  local ifs_bk="$IFS"
  local input=("${(Q)words[@]}")
  IFS=$'\n'
  local res=($(NIX_GET_COMPLETIONS=$((CURRENT - 1)) "$input[@]"))
  IFS="$ifs_bk"
  local tpe="${${res[1]}%%>	*}"
  local -a suggestions
  declare -a suggestions
  for suggestion in ${res:1}; do
    # FIXME: This doesn't work properly if the suggestion word contains a `:`
    # itself
    suggestions+="${suggestion/	/:}"
  done
  if [[ "$tpe" == filenames ]]; then
    compadd -f
  fi
  _describe 'nix' suggestions
}

# stack auto completions
autoload -U +X compinit && compinit -u
autoload -U +X bashcompinit && bashcompinit -u
# eval "$(stack --bash-completion-script stack)"

compdef _nix nix

# prepend a [nix-shell] to zsh prompt
prompt_nix_shell_setup "$@"

# to make grammar like nixpkgs#hello work as expected
setopt noextendedglob
