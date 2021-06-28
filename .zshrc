alias ls='ls --color=auto -v'
alias tmux="TERM=screen-256color-bce tmux"

source $HOME/.nix-profile/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source $HOME/.nix-profile/share/zsh/plugins/nix/init.zsh

export FPATH=$HOME/.nix-profile/share/zsh/site-functions:$FPATH

export PATH=/usr/local/sbin:$PATH
export ZSH_DISABLE_COMPFIX="true"

export HISTFILESIZE=400000000
export HISTSIZE=1000000
export GPG_TTY=$(tty)
if [ -e /Users/cjr/.nix-profile/etc/profile.d/nix.sh ]; then . /Users/cjr/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

# stack auto completions
autoload -U +X compinit && compinit -u
autoload -U +X bashcompinit && bashcompinit -u
eval "$(stack --bash-completion-script stack)"

prompt_nix_shell_setup "$@"
