let
    keyStorePath = "/var/lib/android_keystore";
in {
    los_hammerhead = import ./default.nix {
        inherit keyStorePath;
        sha256 = "07jh5anl0vjc1ygv5bnsl9s1qb9zlsczd7bx9370llc627m2yl34";
        device = "hammerhead";
        opengappsVariant = "pico";
        rev = "lineage-15.1";
    };
}
