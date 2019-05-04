{ fdroidClientVersion, fdroidPrivExtVersion }:
''
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="fdroid" fetch="https://gitlab.com/fdroid/" />

    <project path="packages/apps/F-Droid" name="fdroidclient" remote="fdroid" revision="refs/tags/${fdroidClientVersion}" />"
    <project path="packages/apps/F-DroidPrivilegedExtension" name="privileged-extension" remote="fdroid" revision="refs/tags/${fdroidPrivExtVersion}" />"
</manifest>
''
