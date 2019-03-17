{ opengappsVariant, rev, keyStorePath, device, sha256Path, enableWireguard, ... }: {
    ota = import ./default.nix {
        inherit opengappsVariant rev keyStorePath device sha256Path enableWireguard;
    };
}
