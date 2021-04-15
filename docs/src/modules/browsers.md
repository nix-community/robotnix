# Browsers / Webview

A properly functioning Android system requires the use of a "webview".
Chromium-based browsers may also provide this webview 

Robotnix can also build chromium-based browsers from source.
We currently package Chromium, Bromite, and Vanadium for use with robotnix.


> [Chromium](https://www.chromium.org/) is an open-source browser project that aims to build a safer, faster, and more stable way for all users to experience the web.

> [Bromite](https://www.bromite.org/) is a Chromium fork with ad blocking and enhanced privacy.

> [Vanadium](https://github.com/GrapheneOS/Vanadium) is a privacy and security hardened variant of Chromium providing the WebView (used by other apps to render web content) and standard browser for GrapheneOS.
> It depends on hardening and compatibility fixes in GrapheneOS rather than reinventing the wheel inside Vanadium

The following shows the available options for `chromium`. The corresponding options for `vanadium` and `bromite` are similar.
```nix
{
  apps.chromium.enable = true;
  webview.chromium.enable = true;
  webview.chromium.availableByDefault = true; # At least one webview must be availableByDefault
  webview.chromium.isFallback = true; # If true, this provider will be disabled and only used if no others are available. At most one webview can be isFallback.
}
```

If multiple webview providers are included in a build, it is possible to select the one used on a running phone under "Settings -> System -> Developer Options -> Webview implementation".

The Vanilla and LineageOS flavors enable the standard Chromium browser and webview by default.
The GrapheneOS flavor enables Vanadium browser and webview by default.
