{ androidVersion }:
''
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="rattlesnake" fetch="https://github.com/RattlesnakeOS/" revision="${androidVersion}" />";

    <project path="external/chromium" name="platform_external_chromium" remote="rattlesnake" />";
    <project path="packages/apps/Updater" name="platform_packages_apps_Updater" remote="rattlesnake" />";
</manifest>
''
