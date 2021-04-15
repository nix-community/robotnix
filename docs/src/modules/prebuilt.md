# Prebuilt Apps

Robotnix provides convenient configuration options for including additional prebuilt applications in the Android build using `apps.prebuilt.*` options.
These apps are "prebuilt" from the perspective of the Android build step, and might even be built from source using Nix in another build step.

Perhaps the main reason to include additional prebuilt applications is to take advantage of privileged permissions only available to system applications.
Secondarily, other Android applications that are built and customized from source inside Nix might be useful to include as prebuilts to the overall Android build.
As each change to the robotnix configuration may require a long build process each time, try to avoid the temptation to include all of the applications you typically use in your robotnix configuration.

To include a prebuilt app in the robotnix build, consider the following example configuration:
```nix
{ pkgs, ... }:
{
  apps.prebuilt.ExampleApp = {
    apk = (pkgs.fetchurl {
      url = "https://example.com/test.apk";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    });
    privileged = true;  # Enable if the application needs access to privileged permissions
    privappPermissions = [ "INSTALL_PACKAGES "];
    packageName = "com.example.test";  # Needs to be set if using privappPermissions
  };
}
```

The use of `pkgs.fetchurl` above is for example only.
`apps.prebuilt.<name>.apk` could also refer to an existing APK file by path, or could refer to some APK file output by another Nix expression.
In fact, many of the included robotnix modules (such as F-Droid and Chromium) are implemented using the `apps.prebuilt` module.
Some of these Nix expressions for these apks are available under `apks/`.
