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
  repo2nix,
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

    repo2nix
    prefetch-yarn-deps
    signing-validator

    cachix
  ];
  PYTHONPATH = ./scripts;
}
