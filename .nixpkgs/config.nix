{
  packageOverrides = super:
    let pkgs = super.pkgs;
    in rec {
      myHaskellEnv = pkgs.haskellPackages.ghcWithHoogle (haskellPkgs:
        with haskellPkgs; [
          # libraries
          bytestring
          data-ordlist

          # tools
          xmonad xmonad-contrib
          pandoc
          cabal-install
          cabal2nix
          stack
          brittany
          haskell-language-server
        ]);

      myPackages = pkgs.buildEnv {
        name = "my-packages";
        paths = with pkgs; [
          myHaskellEnv
          ghcid
        ];
      };
    };
}
