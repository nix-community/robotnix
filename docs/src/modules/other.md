# Other Modules

## Resources
Android applications may have [resources](https://developer.android.com/guide/topics/resources/providing-resources) which are additional static content such as bitmaps, user interface strings, configuration values, and others.
Some simple resources may be set for certain packages using the `resources` option.

For example, the settings available [here](https://android.googlesource.com/platform/frameworks/base/+/master/core/res/res/values/config.xml) may be configured in robotnix by setting (for example):
```nix
{
  resources."frameworks/base/core/res".config_displayWhiteBalanceAvailable = true;
}
```
The first key refers toe the relative path for the package resources, and the second key refers to the resource name.
The resource type is automatically determined based on value set.
Setting `resources.<path>.<name>.type` can be used to override the automatically determined type.
Available values types are `bool`, `integer`, `dimen`, `color`, `string`, `integer-array`, and `string-array`.
If this manual override is used, the value must be set using `resources.<path>.<name>.value`.

## CCache

Set `ccache.enable = true` in configuration, and be sure to pass `/var/cache/ccache` as a sandbox exception when building.
In NixOS, to set up the cache, also run (as root):
```shell
# mkdir -p -m0770 /var/cache/ccache
# chown root:nixbld /var/cache/ccache
# echo max_size = 100G > /var/cache/ccache/ccache.conf
```

This option only applies to the Android build process. (It does not apply to chromium, kernels, etc.)
CCache support is deprecated in upstream AOSP, and might be removed from robotnix in the future.
