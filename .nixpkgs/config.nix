{
  packageOverrides = super: let self = super.pkgs; in
  {
    myHaskellEnv = self.haskellPackages.ghcWithHoogle
                     (haskellPackages: with haskellPackages; [
                       # libraries
                       bytestring
                       # tools
					   cabal2nix brittany xmonad
                     ]);
  };
}
