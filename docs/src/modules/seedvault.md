# Seedvault Backup

[Seedvault](https://github.com/seedvault-app/seedvault) is a backup application for the Android Open Source Project.
The following configuration will enable the Seedvault:
```nix
{
  apps.seedvault.enable = true;
}
```

## Backing Up

Normally, the settings for the Seedvault backup application is available under "Settings -> System -> Backup".
However, if you have flashed a new ROM including Seedvault over one which did not have Seedvault initially (without wiping userdata), you may need to manually set the backup transport using `adb`.
```shell
$ adb shell bmgr enable true
$ adb shell bmgr transport com.stevesoltys.seedvault.transport.ConfigurableBackupTransport
```

## Restoring

The GrapheneOS and LineageOS flavors provide the option to use Seedvault upon first boot using the SetupWizard.
The vanilla flavor currently does not use SetupWizard, so the restore activity must be manually started using:
```shell
adb shell am start-activity -a com.stevesoltys.seedvault.RESTORE_BACKUP
```
See the following issue: [seedvault#85](https://github.com/seedvault-app/seedvault/issues/85)
