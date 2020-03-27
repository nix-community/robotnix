nix-build --option extra-sandbox-paths "/keys=/var/secrets/android-keys /var/cache/ccache?" -j4 --cores $(nproc) "$@"
