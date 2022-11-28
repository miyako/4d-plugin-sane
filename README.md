![version](https://img.shields.io/badge/version-19%2B-5682DF)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-sane)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-sane/total)


# 4d-plugin-sane
SANE ([Scanner Access Now Easy](http://www.sane-project.org)) for macOS

### About

SANE talks directly to the scanner over USB. You can use devices that do not offer a native (ICA) driver.

---

### Build

``dll.c`` was modified to reference ``SANE_LD_LIBRARY_PATH`` instead of ``LD_LIBRARY_PATH``

``darwin_usb`` was modified to ignore hotplug.

* Compiled backends

net abaton agfafocus apple avision artec artec_eplus48u as6e bh canon canon630u canon_dr cardscan coolscan coolscan3 dell1600n_net dmc epjitsu epson2 epsonds fujitsu genesys gt68xx hp hp3900 hpsj5s hp3500 hp4200 hp5400 hp5590 hpljm1005 hs2p ibm kodak kodakaio kvs1025 kvs20xx leo lexmark ma1509 magicolor matsushita microtek microtek2 mustek mustek_usb mustek_usb2 nec niash pie pint pixma plustek qcam ricoh rts8891 s9036 sceptre sharp sm3600 sm3840 snapscan sp15c tamarack teco1 teco2 teco3 u12 umax umax1220u v4l xerox_mfp

```
LIBS=" -framework CoreFoundation -framework IOKit"
Lockfiles:     Feature is disabled!
Build saned:   yes
IPv6 support:  yes
Avahi support: no
SNMP support:  yes
```

**Note**: For technical reasons (``pthread`` crash), ``LIBUSB`` hotplug is disabled. The scanner must be connected to the computer before you load the plugin.
