{
  rustPlatform,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage {
  name = "repo2nix";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];
}
