{ rustPlatform }:

rustPlatform.buildRustPackage {
  name = "signing-validator";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
}
