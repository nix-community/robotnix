{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  openssl,
  nix-prefetch-git,
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
    --prefix PATH : ${lib.makeBinPath [ nix-prefetch-git ]}
  '';
}
