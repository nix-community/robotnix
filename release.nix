{ device, rev, manifest, localManifests, opengappsVariant, enableWireguard, keyStorePath, extraFlags, sha256Path, usePatchedCoreutils }: {
    ota = import ./default.nix {
        inherit device rev manifest localManifests opengappsVariant enableWireguard keyStorePath extraFlags sha256Path usePatchedCoreutils;
    };
}
