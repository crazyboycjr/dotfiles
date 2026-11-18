{
  description = "The packages in cjr's nix profile";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      haskellEnv = pkgs.haskellPackages.ghcWithHoogle (hp: with hp; [
        # libraries
        bytestring
        data-ordlist

        # tools
        xmonad xmonad-contrib
        pandoc
        cabal-install
        cabal2nix
        stack
        haskell-language-server
        # compile ghc
        happy alex
      ]);
    in {
      packages.x86_64-linux = rec {
        my-packages = pkgs.buildEnv {
          name = "my-packages";
          paths = with pkgs; [
            haskellEnv
            ghcid
            elan
            code-cursor
          ];
        };
        nix = pkgs.nix;
        default = my-packages;
      };
    };
}
