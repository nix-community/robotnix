{
  mkShell,
  python3,
  gitRepo,
  nix-prefetch-git-patched,
  callPackage,
  curl,
  pup,
  jq,
  shellcheck,
  wget,
  prefetch-yarn-deps,
  cachix,
  nodejs_24,
  repo2nix,
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
    nix-prefetch-git-patched
    curl
    pup
    jq
    shellcheck
    wget

    repo2nix
    nodejs_24
    prefetch-yarn-deps

    cachix
  ];
  PYTHONPATH = ./scripts;
}
