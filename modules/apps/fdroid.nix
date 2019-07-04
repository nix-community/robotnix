{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.apps.fdroid;
  fdroid = pkgs.callPackage ./fdroid {};
  privext = pkgs.fetchFromGitLab {
    owner = "fdroid";
    repo = "privileged-extension";
    rev = "0.2.9";
    sha256 = "0r2s7zyrkfhl88sal8jifhnq47s5p7bs340ifrm9pi7vq91ydvil";
  };
  fdroidAndroidmk = pkgs.writeText "Android.mk" ''
LOCAL_PATH:= $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := F-Droid
LOCAL_MODULE_TAGS := optional
LOCAL_PACKAGE_NAME := F-Droid

LOCAL_CERTIFICATE := platform
LOCAL_SRC_FILES := FDroid.apk
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)

include $(BUILD_PREBUILT)
  '';
in
{
  options = {
    apps.fdroid.enable = mkEnableOption "F-Droid";
  };

  config = mkIf cfg.enable {
    overlays."packages/apps/F-DroidPrivilegedExtension".contents = [ privext ];

    postPatch = ''
      mkdir -p packages/apps/F-Droid
      cp --no-preserve=all -v ${fdroidAndroidmk} packages/apps/F-Droid/Android.mk
      cp --no-preserve=all -v ${fdroid}/apk/full/release/app-full-release-unsigned.apk packages/apps/F-Droid/FDroid.apk
    '';

    additionalProductPackages = [ "F-Droid" "F-DroidPrivilegedExtension" ];

    patches = [ ./fdroid/privext.patch ];
  };
}
