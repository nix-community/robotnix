{ lib, inputs, fetchFromGitHub, rsync, git, gnupg, less, openssh, ... }:
let
  inherit (inputs) nixpkgs-unstable;

  unstablePkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
in
  unstablePkgs.gitRepo.overrideAttrs(oldAttrs: rec {
    version = "2.45";

    src = fetchFromGitHub {
      owner = "android";
      repo = "tools_repo";
      rev = "v${ version }";
      hash = "sha256-f765TcOHL8wdPa9qSmGegofjCXx1tF/K5bRQnYQcYVc=";
    };

    nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ rsync  git ];

    repo2nixPatches = ./patches;

    # NOTE: why `git apply` instead of relying  on `patches`? For some reason when
    #       using `patches` the source `rsync`ed into `var/repo` is missing those changes
    installPhase = ''
      runHook preInstall

      mkdir -p var/repo
      rsync -a $src/ var/repo/

      (
        export GIT_CONFIG_GLOBAL=$TMPDIR/.gitconfig
        export GIT_CONFIG_NOSYSTEM=true

        cd var/repo

        git config --global --add safe.directory "$PWD"
        git config --global user.email "nemo@nix"
        git config --global user.name "Nemo Nix"

        chmod +w -R .

        git init
        git add -A
        git commit -m "Upstream sources"

        git am $repo2nixPatches/*.patch

        git log -n 1 --format="%H" > ../../COMMITED_REPO_REV
      )

      mkdir -p $out/var/repo
      mkdir -p $out/bin

      rsync -a var/repo/ $out/var/repo/

      # Copying instead of symlinking to the above directory is necessary, because otherwise
      # running `repo init` fails, as I assume the script gets confused by being located in
      # a git repo itself
      cp repo $out/bin/repo

      runHook postInstall
    '';

    # Specify the patched checkout as the default version of repo
    postFixup = ''
      wrapProgram "$out/bin/repo" \
        --set REPO_URL "file://$out/var/repo" \
        --set REPO_REV "$(cat ./COMMITED_REPO_REV)" \
        --prefix PATH ":" "${ lib.makeBinPath [ git gnupg less openssh ] }"
    '';
  })
