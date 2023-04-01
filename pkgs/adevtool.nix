{ yarn2nix-moretea, nodejs }:

yarn2nix-moretea.mkYarnPackage {
  name = "adevtool";
  src = config.source.dirs."/vendor/adevtool".src;
  buildInputs = [ nodejs ];
  yarnFlags = [
    "--offline"
    "--frozen-lockfile"
    "--ignore-engines"
    "--ignore-scripts"
    "--verbose"
  ];
}
