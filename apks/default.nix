{ pkgs }:

with pkgs;
{
  auditor = callPackage ./auditor {};

  fdroid = callPackage ./fdroid {};

  seedvault = callPackage ./seedvault {};
}
