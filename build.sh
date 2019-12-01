nix-build --option extra-sandbox-paths "/keys=/var/secrets/android-keys /dev/fuse? /var/cache/ccache?" -j1 --cores $(nproc) "$@"
