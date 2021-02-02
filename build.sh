# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

nix-build --option extra-sandbox-paths "/keys=/var/secrets/android-keys /var/cache/ccache?" -j4 --cores $(nproc) "$@"
