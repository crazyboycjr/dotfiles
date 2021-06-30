let
  oldPkgs = import (builtins.fetchGit {
    # Descriptive name to make the store path easier to identify
    # name = "alacritty_0_6_0"; # this obsoleted in nixUnstable
    url = "https://github.com/NixOS/nixpkgs/";
    ref = "refs/heads/nixpkgs-unstable";
    rev = "559cf76fa3642106d9f23c9e845baf4d354be682";
  }) {};
in
  oldPkgs.alacritty
