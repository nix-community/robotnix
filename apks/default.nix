{ pkgs ? (import ../pkgs.nix {})}:

with pkgs;
rec {
  auditor = callPackage ./auditor {};

  fdroid = callPackage ./fdroid {};

  seedvault = callPackage ./seedvault {};

  # Chromium-based browsers
  chromiumBase = callPackage ./chromium/default.nix {};
  chromium = import ./chromium/chromium.nix {
    inherit chromiumBase;
  };
  vanadium = import ./chromium/vanadium.nix {
    inherit chromiumBase;
    inherit (pkgs) fetchFromGitHub git;
  };
  bromite = import ./chromium/bromite.nix {
    inherit chromiumBase;
    inherit (pkgs) fetchFromGitHub git;
  };
}
