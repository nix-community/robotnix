{ lib }:

lib.listToAttrs (
  builtins.map (c: lib.nameValuePair "${c.flavor}-${c.device}" c) [
    {
      device = "x86_64";
      flavor = "vanilla";
    }
    {
      device = "arm64";
      flavor = "vanilla";
    }
    {
      device = "marlin";
      flavor = "vanilla";
      androidVersion = 10;
    } # Out-of-date
    {
      device = "sailfish";
      flavor = "vanilla";
      androidVersion = 10;
    } # Out-of-date
    {
      device = "taimen";
      flavor = "vanilla";
      androidVersion = 11;
    } # Out-of-date
    {
      device = "walleye";
      flavor = "vanilla";
      androidVersion = 11;
    } # Out-of-date
    {
      device = "crosshatch";
      flavor = "vanilla";
    }
    {
      device = "blueline";
      flavor = "vanilla";
    }
    {
      device = "bonito";
      flavor = "vanilla";
    }
    {
      device = "sargo";
      flavor = "vanilla";
    }
    {
      device = "coral";
      flavor = "vanilla";
    }
    {
      device = "flame";
      flavor = "vanilla";
    }
    {
      device = "sunfish";
      flavor = "vanilla";
    }
    {
      device = "bramble";
      flavor = "vanilla";
    }
    {
      device = "redfin";
      flavor = "vanilla";
    }
    {
      device = "barbet";
      flavor = "vanilla";
    }
    {
      device = "raven";
      flavor = "vanilla";
    }
    {
      device = "oriole";
      flavor = "vanilla";
    }

    {
      device = "x86_64";
      flavor = "grapheneos";
    }
    {
      device = "arm64";
      flavor = "grapheneos";
    }
    {
      device = "crosshatch";
      flavor = "grapheneos";
    }
    {
      device = "blueline";
      flavor = "grapheneos";
    }
    {
      device = "bonito";
      flavor = "grapheneos";
    }
    {
      device = "sargo";
      flavor = "grapheneos";
    }
    {
      device = "coral";
      flavor = "grapheneos";
    }
    {
      device = "flame";
      flavor = "grapheneos";
    }
    {
      device = "sunfish";
      flavor = "grapheneos";
    }
    {
      device = "bramble";
      flavor = "grapheneos";
    }
    {
      device = "redfin";
      flavor = "grapheneos";
    }
    {
      device = "barbet";
      flavor = "grapheneos";
    }

    {
      device = "marlin";
      flavor = "lineageos";
    }
    {
      device = "pioneer";
      flavor = "lineageos";
    }

    {
      device = "x86_64";
      flavor = "anbox";
    }
    {
      device = "arm64";
      flavor = "anbox";
    }
  ]
)
