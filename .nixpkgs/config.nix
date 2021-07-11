{
  allowUnfree = true;

  permittedInsecurePackages = [ "openssl-1.0.2u" ];

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
          pandoc
        ]);

      myPythonEnv = pkgs.python3.withPackages (ps: # python3Packages
        with ps; [
          pypdf2
          jupyter
          jupyterlab
          tqdm
          matplotlib
          seaborn
          scikitlearn
          pip
        ]);

      alacritty_0_6_0 = import ./alacritty.nix;

      myPackages = pkgs.buildEnv {
        name = "my-packages";
        paths = with pkgs; [
          # haskell dev
          myHaskellEnv
          ghcid
          # python dev
          myPythonEnv
          # admin tools
          mtr htop
          # user commandline softwares
          bash zsh
          zsh-syntax-highlighting
          nix-zsh-completions
          vim-darwin
          # use zsh as the default shell will overwrite several env variables such as configurePhase, which is not desired in some cases
          # zsh-nix-shell # or any-nix-shell
          tmux tmuxPlugins.resurrect
          gnupg pinentry-curses
          wget
          bat
          # darwin.iproute2mac # cannot be built unless allow insecure openssl_1_0_2, see https://github.com/NixOS/nixpkgs/pull/109003
          alacritty_0_6_0
          ubuntu_font_family
          tinc
          rust-analyzer
          gnuplot_qt
          graphviz
          jq
          fuse
          ntfs3g
          shadowsocks-rust
          # Better userland for macOS
          coreutils diffutils findutils gnugrep gnused tree
          hwloc # lstopo
          # latex
          texlive.combined.scheme-full
          # unfree softwares
          vscode
        ];
      };
    };
}
