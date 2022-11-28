![version](https://img.shields.io/badge/version-19%2B-5682DF)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-sane)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-sane/total)

# 4d-plugin-sane
SANE ([Scanner Access Now Easy](http://www.sane-project.org)) for macOS

### About

SANE talks directly to the scanner over USB. You can use devices that do not offer a native (ICA) driver.

### Patches

* sane-backends/backends/dll.c: reference ``SANE_LD_LIBRARY_PATH`` instead of ``LD_LIBRARY_PATH`` can't remember why this was necessary.

* libsub/darwin_usb: ignore hotplug. reason: ``pthread`` crash). scanner must be connected to the computer before you load the plugin.

### Configure

`--without-poppler-glib` `--enable-static`
