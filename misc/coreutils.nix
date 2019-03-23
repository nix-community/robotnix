{ coreutils, autoreconfHook, texinfo }:
coreutils.overrideAttrs (origAttrs: {
  nativeBuildInputs = origAttrs.nativeBuildInputs ++ [ autoreconfHook texinfo ];
  doCheck = false;
  patches = [
    ./coreutils.patch
  ];
})
