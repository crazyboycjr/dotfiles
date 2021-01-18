alias tmux="TERM=screen-256color-bce tmux"

source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

export PATH=/usr/local/sbin:$PATH
export ZSH_DISABLE_COMPFIX="true"

export HISTFILESIZE=400000000
export HISTSIZE=1000000
export GPG_TTY=$(tty)
if [ -e /Users/cjr/.nix-profile/etc/profile.d/nix.sh ]; then . /Users/cjr/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer
