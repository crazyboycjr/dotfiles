# Startup files, in the order zsh reads them:
#   /etc/zsh/zshenv, ~/.zshenv   every zsh, scripts too (neither exists here)
#   /etc/zsh/zprofile            login shells only; sources /etc/profile
#   ~/.zprofile                  login shells only (doesn't exist here)
#   /etc/zsh/zshrc               interactive shells: grml's config, which reads
#     ~/.zshrc.pre                 first, before grml's setup and its compinit
#     ~/.zshrc.local               last (doesn't exist here)
#   ~/.zshrc                     this file, after grml's setup
#   /etc/zsh/zlogin, ~/.zlogin   login shells only (neither exists here)
# The desktop session's environment, PATH included, comes from /etc/profile and
# ~/.profile, which greetd reads before starting X; every terminal inherits it.

export GPG_TTY=$TTY
export SSLKEYLOGFILE=/tmp/sslkeylogout.log
export SYSTEMD_EDITOR=vim

export GOPATH=$HOME/Developing/go
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$HOME/Developing/rdma-core/build/bin
. "$HOME/.cargo/env"
. $HOME/export-esp.sh

if [ -e ~/.nix-profile/bin/ghc ]; then
  export NIX_GHC="$HOME/.nix-profile/bin/ghc"
  export NIX_GHCPKG="$HOME/.nix-profile/bin/ghc-pkg"
  export NIX_GHC_DOCDIR="$HOME/.nix-profile/share/doc/ghc/html"
  export NIX_GHC_LIBDIR="$HOME/.nix-profile/lib/ghc-$($NIX_GHC --numeric-version)"
fi

export HISTSIZE=1000000
export SAVEHIST=1000000

alias dig=drill
alias pbcopy='xclip -selection clipboard'
alias pbpaste='xclip -selection clipboard -o'
alias open='xdg-open'
alias ghci='LANG=C.UTF-8 ghci'
alias ghcid='LANG=C.UTF-8 ghcid'
alias vim='nvim'
unfunction zed
alias zed=zeditor
alias s=silent

if [[ "$TERM_PROGRAM" == "vscode" ]]; then
  PROMPT='%n@%m:%~%# '
  RPROMPT=''
fi

# BEGIN opam configuration
# This is useful if you're using opam as it adds:
#   - the correct directories to the PATH
#   - auto-completion for the opam binary
# This section can be safely removed at any time if needed.
[[ ! -r '/home/cjr/.opam/opam-init/init.zsh' ]] || source '/home/cjr/.opam/opam-init/init.zsh' > /dev/null 2> /dev/null
# END opam configuration

source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
