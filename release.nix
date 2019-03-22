{ device, rev, manifest, localManifests, opengappsVariant, enableWireguard, keyStorePath, extraFlags, sha256Path, ... }: {
    ota = import ./default.nix {
        inherit device rev manifest localManifests opengappsVariant enableWireguard keyStorePath extraFlags sha256Path;
    };
}
