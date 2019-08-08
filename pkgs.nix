let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/525eaf407d4edb329ea48f6dc9c6590fb73c779a.tar.gz";
    sha256 = "0l2hvrpsvnlv2ly6il4n5gzn673zjlssrwi0ryvla42i06grqpis";
#    url = "https://github.com/nixos/nixpkgs/archive/acbdaa569f4ee387386ebe1b9e60b9f95b4ab21b.tar.gz";
#    sha256 = "0xzyghyxk3hwhicgdbi8yv8b8ijy1rgdsj5wb26y5j322v96zlpz";
  };

  # Hack since I can't figure out how to overide the androidenv stuff with an overlay.
  # TODO: Should this patch be upstreamed?
  patchedNixpkgs = (import nixpkgs {}).runCommand "nixpkgs-patched" {} ''
    cp -r ${nixpkgs} $out
    chmod -R +w $out
    patch -d $out -p1 < ${./patches/nixpkgs-licenses.patch}
  '';
in
import patchedNixpkgs { config = { android_sdk.accept_license=true; }; }
