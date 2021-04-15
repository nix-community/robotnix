<!--
SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# F-Droid

The following configuration will enable the [F-Droid app](https://www.f-droid.org/) and the [F-Droid privileged extension](https://gitlab.com/fdroid/privileged-extension).
```nix
{
    apps.fdroid.enable = true;
}
```
The F-Droid privileged extension enables F-Droid to install and delete apps without needing "Unknown Sources" to be enabled (e.g. just like Google Play does).
It also enables F-Droid to install updates in the background without the user having to click "install".

## Adding F-Droid repositories

F-Droid can manage multiple repositories to fetch apps from.  These can be set
up manually in the app, but with robotnix it is also possible to preload
F-Droid with some repositories at build time.

To add an F-Droid repository you need at least the URL and a public key.
Obtaining the URL is in general very easy but it's not obvious where to obtain
the public key.

We'll take the microG repository as an example.  The repository is located
[here]( https://microg.org/fdroid/repo).  To obtain the repository index
download the `index.xml` file from the repository root:
```console
$ curl -LO https://microg.org/fdroid/repo/index.xml
```

The content of this XML file contains metadata about the repository, including
the public key:
```xml
<?xml version="1.0" encoding="utf-8"?>
<fdroid>
	<repo name="microG F-Droid repo" icon="fdroid-icon.png" url="https://microg.org/fdroid/repo" version="19" timestamp="1606314565" pubkey="308202ed308201d5a003020102020426ffa009300d06092a864886f70d01010b05003027310b300906035504061302444531183016060355040a130f4e4f47415050532050726f6a656374301e170d3132313030363132303533325a170d3337303933303132303533325a3027310b300906035504061302444531183016060355040a130f4e4f47415050532050726f6a65637430820122300d06092a864886f70d01010105000382010f003082010a02820101009a8d2a5336b0eaaad89ce447828c7753b157459b79e3215dc962ca48f58c2cd7650df67d2dd7bda0880c682791f32b35c504e43e77b43c3e4e541f86e35a8293a54fb46e6b16af54d3a4eda458f1a7c8bc1b7479861ca7043337180e40079d9cdccb7e051ada9b6c88c9ec635541e2ebf0842521c3024c826f6fd6db6fd117c74e859d5af4db04448965ab5469b71ce719939a06ef30580f50febf96c474a7d265bb63f86a822ff7b643de6b76e966a18553c2858416cf3309dd24278374bdd82b4404ef6f7f122cec93859351fc6e5ea947e3ceb9d67374fe970e593e5cd05c905e1d24f5a5484f4aadef766e498adf64f7cf04bddd602ae8137b6eea40722d0203010001a321301f301d0603551d0e04160414110b7aa9ebc840b20399f69a431f4dba6ac42a64300d06092a864886f70d01010b0500038201010007c32ad893349cf86952fb5a49cfdc9b13f5e3c800aece77b2e7e0e9c83e34052f140f357ec7e6f4b432dc1ed542218a14835acd2df2deea7efd3fd5e8f1c34e1fb39ec6a427c6e6f4178b609b369040ac1f8844b789f3694dc640de06e44b247afed11637173f36f5886170fafd74954049858c6096308fc93c1bc4dd5685fa7a1f982a422f2a3b36baa8c9500474cf2af91c39cbec1bc898d10194d368aa5e91f1137ec115087c31962d8f76cd120d28c249cf76f4c70f5baa08c70a7234ce4123be080cee789477401965cfe537b924ef36747e8caca62dfefdd1a6288dcb1c4fd2aaa6131a7ad254e9742022cfd597d2ca5c660ce9e41ff537e5a4041e37">
		<description>This is a repository of microG apps to be used with F-Droid. Applications in this repository are signed official binaries built by the microG Team from the corresponding source code. </description>
	</repo>
	<application id="...">
		<!-- ... list of contained applications ... -->
	</application>
</fdroid>
```
Simply copy the `name` and `pubkey` fields and use them as the name and public
key for the corresponding Nix expression respectively.
```nix
{
  apps.fdroid.additionalRepos = {
    "microG F-Droid repo" = {
      enable = true;
      url = "https://microg.org/fdroid/repo";
      pubkey = "308202ed308201d5a003020102020426ffa009300d06092a864886f70d01010b05003027310b300906035504061302444531183016060355040a130f4e4f47415050532050726f6a656374301e170d3132313030363132303533325a170d3337303933303132303533325a3027310b300906035504061302444531183016060355040a130f4e4f47415050532050726f6a65637430820122300d06092a864886f70d01010105000382010f003082010a02820101009a8d2a5336b0eaaad89ce447828c7753b157459b79e3215dc962ca48f58c2cd7650df67d2dd7bda0880c682791f32b35c504e43e77b43c3e4e541f86e35a8293a54fb46e6b16af54d3a4eda458f1a7c8bc1b7479861ca7043337180e40079d9cdccb7e051ada9b6c88c9ec635541e2ebf0842521c3024c826f6fd6db6fd117c74e859d5af4db04448965ab5469b71ce719939a06ef30580f50febf96c474a7d265bb63f86a822ff7b643de6b76e966a18553c2858416cf3309dd24278374bdd82b4404ef6f7f122cec93859351fc6e5ea947e3ceb9d67374fe970e593e5cd05c905e1d24f5a5484f4aadef766e498adf64f7cf04bddd602ae8137b6eea40722d0203010001a321301f301d0603551d0e04160414110b7aa9ebc840b20399f69a431f4dba6ac42a64300d06092a864886f70d01010b0500038201010007c32ad893349cf86952fb5a49cfdc9b13f5e3c800aece77b2e7e0e9c83e34052f140f357ec7e6f4b432dc1ed542218a14835acd2df2deea7efd3fd5e8f1c34e1fb39ec6a427c6e6f4178b609b369040ac1f8844b789f3694dc640de06e44b247afed11637173f36f5886170fafd74954049858c6096308fc93c1bc4dd5685fa7a1f982a422f2a3b36baa8c9500474cf2af91c39cbec1bc898d10194d368aa5e91f1137ec115087c31962d8f76cd120d28c249cf76f4c70f5baa08c70a7234ce4123be080cee789477401965cfe537b924ef36747e8caca62dfefdd1a6288dcb1c4fd2aaa6131a7ad254e9742022cfd597d2ca5c660ce9e41ff537e5a4041e37";
    };
  };
}
```
The name can really be anything, but the one that is provided here is the one
that shows up before refreshing the F-Droid repo list for the first time, so if
you want that to look pretty, give it a pretty name here.

The `apps.fdroid.additionalRepos` variable is only used to prepopulate the internal database of F-Droid repositories upon the first run of the application.
Changes to this variable will not have any effect on phones that have already started the F-Droid application.
