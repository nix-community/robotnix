<!--
SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# MicroG


[MicroG](https://microg.org/) is a free-as-in-freedom re-implementation of Google’s proprietary Android user space apps and libraries.
MicroG support may be enabled using:
```nix
{
  microg.enable = true;
}
```

MicroG requires a patch to the Android system to allow spoofing Google's signature for MicroG's reimplemented version of Google services.
The patch included in robotnix locks down this signature spoofing functionality to only the MicroG application and the Google signatures.
