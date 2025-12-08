{
  mkShell,
  python3,
  gitRepo,
  callPackage,
  curl,
  pup,
  jq,
  shellcheck,
  wget,
  prefetch-yarn-deps,
  cachix,
  signing-validator,
}:

mkShell {
  name = "robotnix-devshell";
  nativeBuildInputs = [
    # For android updater scripts
    (python3.withPackages (
      p: with p; [
        mypy
        flake8
        pytest
      ]
    ))
    gitRepo
    (callPackage ./pkgs/fetchgit/nix-prefetch-git.nix { })
    curl
    pup
    jq
    shellcheck
    wget

    (callPackage ./repo2nix/package.nix { })
    prefetch-yarn-deps
    signing-validator

    cachix
  ];
  PYTHONPATH = ./scripts;
}
