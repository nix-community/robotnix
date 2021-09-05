<!--
SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# robotnix - Build Android (AOSP) using Nix

Robotnix is a build system for Android (AOSP) images on top of the Nix package
manager.  Instead of having to follow complicated instructions to install
several build tools and fetch source code from multiple sources, robotnix
encapsulates all this complexity in a simple Nix expression.

The documentation included here should help inform you how to [create your configuration file](configuration.md),
[build your Android image](building.md),
and [install the image onto your phone](installation.md).

If you find parts of this manual confusing, please create an issue, or (even better) create a pull request on Github.
Robotnix users and developers can also be contacted on `#robotnix:nixos.org` on Matrix.
