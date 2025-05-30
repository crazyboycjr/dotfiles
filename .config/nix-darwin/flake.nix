{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, ... }:
  let
    configuration = { lib, pkgs, config, ... }: {
      environment.variables = {
        EDITOR = "vim";
      };

      fonts.packages = with pkgs; [
        ubuntu_font_family source-code-pro vistafonts dejavu_fonts powerline-fonts libertinus
      ];

      environment.pathsToLink = [
        "/share"
        "/etc"
        "/lib"
      ];
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = with pkgs; [
        haskellPackages.stack
        alacritty
        nodejs_24
        # admin tools
        mtr htop
        # user commandline softwares
        bash zsh
        zsh-syntax-highlighting
        nix-zsh-completions # needs to remove /nix/store/ym6bnwyjs930lwl9mlvmn21i2dym4hgg-nix-2.8pre20220512_d354fc3/share/zsh/site-functions/_nix
        vim-darwin
        neovim
        # use zsh as the default shell will overwrite several env variables such as configurePhase, which is not desired in some cases
        # zsh-nix-shell # or any-nix-shell
        tmux tmuxPlugins.resurrect
        gnupg pinentry-curses
        wget
        bat
        mosh
        sshfs
        iproute2mac
        eternal-terminal
        # tinc_pre
        # tinc_latest
        gnuplot_qt
        graphviz
        jq
        fuse
        ntfs3g
        shadowsocks-rust
        iperf2
        # Better userland for macOS
        coreutils diffutils findutils gnugrep gnused tree gzip
        hwloc # lstopo
        # llvmPackages_12.llvm llvmPackages_12.clang
        # latex
        # texlive.combined.scheme-full
        yabai skhd
        mpv-unwrapped
        rclone
        discord
        notion-app
        zotero
        # unfree softwares
        vscode
        google-chrome
        chatgpt
        betterdisplay
      ];

      nixpkgs.config.allowUnfree = true;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;
      # zsh
      programs.zsh.enable = true;
      programs.zsh.interactiveShellInit = ''
        source ${pkgs.grml-zsh-config}/etc/zsh/zshrc
      '';
      programs.zsh.promptInit = ""; # otherwise it'll override the grml prompt

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      system.primaryUser = "cjr";
      system.defaults = {
        dock.autohide = true;
        finder.AppleShowAllExtensions = true;
        screencapture.location = "~/Pictures";
      };

      system.activationScripts.applications.text = lib.mkForce ''
        echo "Setting up /Applications/Nix Apps" >&2
        appsSrc="${config.system.build.applications}/Applications/"
        baseDir="/Applications/Nix Apps"
        mkdir -p "$baseDir"
        ${pkgs.rsync}/bin/rsync --archive --checksum --chmod=-w --copy-unsafe-links --delete "$appsSrc" "$baseDir"
      '';

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    darwinConfigurations."cjr-mac" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
      ];
    };

    # darwinPackages = self.darwinConfigurations."cjr-mac".pkgs;
  };
}
