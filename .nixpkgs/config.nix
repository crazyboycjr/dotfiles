{
  packageOverrides = super:
    let pkgs = super.pkgs;
    in rec {
      myHaskellEnv = pkgs.haskellPackages.ghcWithHoogle (haskellPkgs:
        with haskellPkgs; [
          # libraries
          bytestring

          # tools
          cabal2nix
          stack
          brittany
          haskell-language-server
        ]);

      alacritty_0_6_0 = import ./alacritty.nix;

      myPackages = pkgs.buildEnv {
        name = "my-packages";
        paths = with pkgs; [
          # haskell dev
          myHaskellEnv
          ghcid
          # admin tools
          mtr htop
          # user softwares
          zsh-syntax-highlighting
          nix-zsh-completions
          tmux
          gnupg pinentry-curses
          wget
          # darwin.iproute2mac # cannot be built, see https://github.com/NixOS/nixpkgs/pull/109003
          alacritty_0_6_0
          tinc
          rust-analyzer
          gnuplot_qt
        ];
      };
    };
}
