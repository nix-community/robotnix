{
  self,
  nixpkgs,
  nixpkgs-unstable,
  androidPkgs,
  flake-compat,
  treefmt,
  treefmt-nix,
  ...
}@inputs:
let
  pkgs = import ./../pkgs/default.nix { inherit inputs; };

  treeFmt = treefmt-nix.lib.evalModule pkgs ./../treefmt.nix;
  pythonForUpdaterScripts = pkgs.python3.withPackages (
    p: with p; [
      mypy
      flake8
      pytest
    ]
  );
in
{
  # robotnixSystem evaluates a robotnix configuration
  lib.robotnixSystem = configuration: import ./../default.nix { inherit configuration pkgs; };

  defaultTemplate = {
    path = ./../template;
    description = "A basic robotnix configuration";
  };

  nixosModule = import ./../nixos; # Contains all robotnix nixos modules
  nixosModules.attestation-server = import ./../nixos/attestation-server/module.nix;

  packages.x86_64-linux = {
    manual = (import ./../docs { inherit pkgs; }).manual;
    gitRepo = pkgs.gitRepo;
  };

  devShell.x86_64-linux = pkgs.mkShell {
    name = "robotnix-scripts";
    inputsFrom = [ treeFmt.config.build.devShell ];
    nativeBuildInputs = with pkgs; [
      pythonForUpdaterScripts
      gitRepo
      nix-prefetch-git
      curl
      pup
      jq
      wget

      # For chromium updater script
      # python2
      cipd
      git

      cachix
    ];
    PYTHONPATH = ./../scripts;
  };

  formatter.x86_64-linux = treeFmt.config.build.wrapper;

  checks.x86_64-linux = {
    formatting = treeFmt.config.build.check self;
    pytest = pkgs.stdenvNoCC.mkDerivation {
      name = "pytest";
      src = ./..;

      dontBuild = true;
      doCheck = true;

      nativeBuildInputs = with pkgs; [
        pythonForUpdaterScripts
        git
        gitRepo
        nix-prefetch-git
      ];
      checkPhase = ''
        NIX_PREFIX="$TMPDIR/nix"

        mkdir -p "$NIX_PREFIX"

        export NIX_STATE_DIR="$NIX_PREFIX/var/nix"

        pytest "$src" \
          -p no:cacheprovider \
          --junitxml="$out/report.xml"
      '';
    };
  };
}
