{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  openssl,
  git,
  nix-prefetch-git,
  prefetch-yarn-deps,
}:

rustPlatform.buildRustPackage {
  name = "repo2nix";
  src = ./.;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "nix-compat-0.1.0" = "sha256-xSY1Ngs4oElXFDSlLvj+21WLXhnY991uzEwwspu78u8=";
    };
  };

  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ openssl ];

  postInstall = ''
    wrapProgram $out/bin/generate_lockfile \
    --prefix PATH : ${lib.makeBinPath [ git nix-prefetch-git prefetch-yarn-deps ]}
  '';
}
