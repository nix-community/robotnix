{ }: with builtins;
let
  defaultNixDroid = {
    nixexprpath = "release.nix";
    checkinterval = 300;
    schedulingshares = 1000;
    keepnr = 3;
  };
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
      value = args.device;
      emailresponsible = false;
    };
    manifest = {
      type = "string";
      value = optConf args "manifest" "https://github.com/LineageOS/android.git";
      emailresponsible = false;
    };
    sha256Path = {
      type = "path";
      value = "/var/lib/nixdroid/hashes/" + args.device + ".sha256";
      emailresponsible = false;
    };
    localManifests = {
      type = "expr";
      value = [ (../roomservice- + "${args.device}.xml") ] ++
        (if (hasAttr "enableWireguard" args && args.enableWireguard) then [ ../wireguard.xml ] else []) ++
        (if (hasAttr "opengappsVariant" args) then [ ../opengapps.xml ] else []);
      emailresponsible = false;
    };
    extraFlags = {
      type = "string";
      value = optConf args "extraFlags" "-g all,-darwin,-infra,-sts --no-repo-verify";
    };
  };
  optConf = set: attr: default: if (hasAttr attr set) then set.${attr} else default;
in {
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
  jobsets = {
    "los-15.1-hammerhead" = defaultNixDroid // {
      description = "LineageOS 15.1 for Hammerhead";
      inputs = defaultInputs {
        device = "hammerhead";
        rev = "lineage-15.1";
        opengappsVariant = "pico";
      };
    };
    "los-15.1-payton" = defaultNixDroid // {
      description = "LineageOS 15.1 for Payton";
      inputs = defaultInputs {
        device = "payton";
        rev = "lineage-15.1";
        enableWireguard = true;
        opengappsVariant = "nano";
      };
    };
    "los-16.0-oneplus3" = defaultNixDroid // {
      description = "LineageOS 16.0 for OnePlus 3";
      inputs = defaultInputs {
        device = "oneplus3";
        enableWireguard = true;
        opengappsVariant = "nano";
      };
    };
    # "los-16.0-bacon" = defaultNixDroid // {
    #   description = "LineageOS 16.0 for Bacon";
    #   inputs = defaultInputs {
    #     device = "bacon";
    #     enableWireguard = true;
    #     opengappsVariant = "pico";
    #   };
    # };
  };
}
