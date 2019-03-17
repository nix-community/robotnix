{ ... }: let
  defaultJobset = {
    enabled = 1;
    hidden = false;
    nixexprinput = "nixdroid";
    nixexprpath = "release.nix";
    checkinterval = 300;
    schedulingshares = 1000;
    enableemail = false;
    emailoverride = "";
    keepnr = 3;
  };
  defaultNixDroid = {
    nixexprpath = "release.nix";
    checkinterval = 300;
    schedulingshares = 1000;
    keepnr = 3;
  };
  optConf = set: attr: default: if (builtins.hasAttr attr set) then builtins.getAttr attr set else default;
  defaultInputs = args: {
    nixdroid = {
      type = "git";
      value = "https://github.com/ajs124/NixDroid dev";
      emailresponsible = true;
    };
    nixpkgs = {
      type = "git";
      value = "https://github.com/nixos/nixpkgs-channels nixos-18.09";
      emailresponsible = false;
    };
    opengappsVariant = {
      type = "string";
      value = optConf args "opengappsVariant" "nano";
      emailresponsible = false;
    };
    rev = {
      type = "string";
      value = optConf args "rev" "lineage-16.0";
      emailresponsible = false;
    };
    keyStorePath = {
      type = "string";
      value = "/var/lib/nixdroid/keystore";
      emailresponsible = false;
    };
    device = {
      type = "string";
      value = args.deviceName;
      emailresponsible = false;
    };
    sha256Path = {
      type = "path";
      value = "/var/lib/nixdroid/hashes/" + args.deviceName + ".sha256";
      emailresponsible = false;
    };
    enableWireguard = {
      type = "boolean";
      value = optConf args "enableWireguard" "false";
      emailresponsible = false;
    };
  };

  jobsets = {
    "los-15.1-hammerhead" = defaultNixDroid // {
      description = "LineageOS 15.1 for Hammerhead";
      inputs = defaultInputs {
        deviceName = "hammerhead";
        rev = "lineage-15.1";
        opengappsVariant = "pico";
      };
    };
    "los-16.0-oneplus3" = defaultNixDroid // {
      description = "LineageOS 16.0 for OnePlus 3";
      inputs = defaultInputs {
        deviceName = "oneplus3";
        enableWireguard = "true";
      };
    };
    "los-16.0-bacon" = defaultNixDroid // {
      description = "LineageOS 16.0 for Bacon";
      inputs = defaultInputs {
        deviceName = "bacon";
        enableWireguard = "true";
      };
    };
  };
in {
  jobsets = derivation {
    name = "spec.json";
    system = builtins.currentSystem;

    builder = "/bin/sh";
    args = [ (builtins.toFile "spec-builder.sh" ''
      echo '
      ${builtins.toJSON (builtins.mapAttrs (k: v: defaultJobset // v) jobsets)}
      ' > $out
    '') ];
  };
}
