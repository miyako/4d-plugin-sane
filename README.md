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

#### linked to libjpeg

* libsane-dc210
* libsane-epsonds
* libsane-pixma
* libsane-dc240
* libsane-xerox_mfp

#### linked to libtiff

* libsane-hp3900 (x86_64)
* libsane-genesys (x86_64)

libusb-1.0.0.dylib for the sane shared objects are compiled without hotplug.

libusb.a for the main plugin is compiled with hotplug.

```
-> Network parameters:
Build saned:   yes
IPv6 support:  no
Avahi support: no
cURL support:  yes
POPPLER_GLIB support:  no
SNMP support:  yes
-> The following backends will be built:
abaton 
agfafocus 
apple 
artec 
artec_eplus48u 
as6e 
avision 
bh 
canon 
canon630u 
canon_dr 
canon_lide70 
cardscan 
coolscan 
coolscan2 
coolscan3 
dc25 
dc210 
dc240 
dmc 
epjitsu 
epson 
epson2 
epsonds 
fujitsu 
genesys 
gt68xx 
hp 
hp3500 
hp3900 
hp4200 
hp5400 
hp5590 
hpljm1005 
hs2p 
ibm 
kodak 
kodakaio 
kvs1025 
kvs20xx 
kvs40xx 
leo 
lexmark 
ma1509 
magicolor 
matsushita 
microtek 
microtek2 
mustek 
mustek_usb 
mustek_usb2 
nec 
net 
niash 
pie 
pieusb 
pixma 
plustek 
plustek_pp 
ricoh 
ricoh2 
rts8891 
s9036 
sceptre 
sharp 
sm3600 
sm3840 
snapscan 
sp15c 
st400 
stv680 
tamarack 
teco1 
teco2 
teco3 
test 
u12 
umax 
umax_pp 
umax1220u 
xerox_mfp 
p5 
```
