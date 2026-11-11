![version](https://img.shields.io/badge/version-19%2B-5682DF)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-sane)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-sane/total)

# 4d-plugin-sane

SANE ([Scanner Access Now Easy](http://www.sane-project.org)) for macOS. The plugin embeds `libsane` and its scanner backends (`Contents/PlugIns/libsane-*.1.so`) and talks to the scanner directly over USB through `libusb`, so you can use devices that have no native (ICA) driver. Scanned pages come back as a `Collection` of `Picture` values encoded as PNG or JPEG; scanner and option lists come back as `Collection`s of objects.

| Command | Returns | Purpose |
|---|---|---|
| [SANE Scanners list](#sane-scanners-list) | `Collection` | Initialise SANE and list the attached scanners |
| [SANE Scan](#sane-scan) | `Collection` of `Picture` | Scan every available page |
| [SANE Scan option values](#sane-scan-option-values) | `Collection` | Describe every option of a scanner |
| [SANE SET SCAN OPTION](#sane-set-scan-option) | — | Set one option of a scanner |
| [SANE Get scan option](#sane-get-scan-option) | `Text` | Read one option of a scanner |

**Platforms:** macOS (Apple Silicon and Intel). There is no Windows implementation.

Releases: [GitHub releases](https://github.com/miyako/4d-plugin-sane/releases)

---

## Requirements & platform notes

- **macOS only.** The repository contains a Visual Studio project, but the plugin code is Objective-C++ against `libsane`/`libusb`, and no Windows binary is built or shipped.
- **macOS 12 in practice.** The plugin binary targets macOS 11.5, but the bundled backends (`libsane-*.1.so`, arm64 slices) and `libusb-1.0.0.dylib` (both slices) were built for macOS 12.0, so they are expected to fail to load on macOS 11.
- **Call [SANE Scanners list](#sane-scanners-list) first.** SANE is initialised only by that command. Until it has run in the current 4D session, the other commands find no scanner and fail silently. SANE is shut down when 4D quits.
- **Scanner names** are the `name` property returned by [SANE Scanners list](#sane-scanners-list), a backend-specific string. Every other command takes that name as its first parameter.
- **Failures are silent.** No command raises a 4D error. A scanner that can't be opened, an unknown option or a rejected value gives an empty result or no change; the details go to the process's standard output (`printf`), not to 4D.
- **Not thread-safe.** All commands are declared `threadSafe: false`: call them from cooperative processes only. Device discovery, scanning and option listing run on a worker thread while the calling 4D process sleeps, so other 4D processes keep running meanwhile.
- **Backend configuration** ships in `Contents/Resources/sane.d` (`dll.conf` lists the enabled backends, one `<backend>.conf` per backend). The plugin points `SANE_CONFIG_DIR` there at startup.

---

## SANE Scanners list

### Syntax

```
SANE Scanners list ( names ) -> Collection
```

| Parameter | Type | Description |
|---|---|---|
| `names` | Text array | Receives the device names (output) |
| Result | Collection | One object per scanner |

### Description

(Re)initialises SANE (`sane_exit` then `sane_init`, which clears the device cache) and asks every backend for its devices. Each element of the result is an object:

| Property | Type | Description |
|---|---|---|
| `name` | Text | Device name to pass to the other commands |
| `vendor` | Text | Manufacturer |
| `model` | Text | Model name |
| `type` | Text | Device type as reported by the backend |

`names` receives the same device names from element 1 on. Element 0 holds the whole result as JSON text.

If SANE can't be initialised, the command has no list to return and parses an empty string as JSON instead. Whether that gives `Null` or a JSON parse error depends on your 4D version (not verified), so test the result before using `.length`.

Because the command restarts SANE, don't call it while another process is scanning (see [Error handling & troubleshooting](#error-handling--troubleshooting)).

### Example

From the plugin's own test method (`TEST.4dm`):

```4d
C_TEXT:C284(<>DEFAULT_SCANNER)
If (<>DEFAULT_SCANNER="")
	ARRAY TEXT:C222($scannerNames; 0)
	$scanners:=SANE Scanners list($scannerNames)
	If ($scanners.length#0)
		<>DEFAULT_SCANNER:=$scanners[0].name
	End if 
End if 
```

Picking a scanner by vendor:

```4d
ARRAY TEXT($names; 0)
$scanners:=SANE Scanners list($names)
$scanner:=Null
If ($scanners#Null)
	For each ($s; $scanners)
		If ($s.vendor="FUJITSU")
			$scanner:=$s
		End if 
	End for each 
End if 
```

---

## SANE Scan

### Syntax

```
SANE Scan ( scanner ; format ) -> Collection
```

| Parameter | Type | Description |
|---|---|---|
| `scanner` | Text | Device name from [SANE Scanners list](#sane-scanners-list) |
| `format` | Longint | `Scanner image type JPEG` (0) or `Scanner image type PNG` (2). `Scanner image type TIFF` (1) is **not implemented** and gives PNG |
| Result | Collection | One `Picture` per scanned page or side |

### Description

Opens the scanner, then starts one scan after another until the backend reports that there are no more documents (empty feeder) or an error, and returns the pages in order. Set the mode, resolution, source etc. beforehand with [SANE SET SCAN OPTION](#sane-set-scan-option). Any `format` other than 0 gives PNG.

The loop ends when the backend refuses to start another scan. With a sheet feeder that happens when the feeder is empty. Whether a flatbed backend refuses a second start (and so returns one page) is backend-specific and not verified.

Supported frame formats:

| Mode | Depth | PNG | JPEG |
|---|---|---|---|
| Color (single-pass RGB) | 8 | 8-bit RGB | RGB |
| Color (single-pass RGB) | 16 | 16-bit RGB | not converted: the image is garbled |
| Gray | 8 | 8-bit gray | gray |
| Gray | 16 | 16-bit gray | not converted: the image is garbled |
| Lineart | 1 | 1-bit gray, black and white expected to be swapped | 8-bit gray |

- **JPEG** is written progressive, quality 100. JPEG has no 16-bit mode and the plugin copies 16-bit samples as they are, so use PNG (or depth 8) for 16-bit scans.
- **Lineart (depth 1) to PNG**: SANE uses 1 for black, PNG gray uses 0 for black, and the plugin copies the bits unchanged, so black and white are expected to come out swapped (inferred from the code and the SANE convention, not tested with a scanner). The JPEG path converts them correctly.
- **Resolution metadata**: the picture's DPI is the scanner's `resolution` option, or 300 when there is none. Separate X/Y resolution options are ignored.
- **Read timeout**: reading a page stops after 30 seconds. Since this version, a page cut short (or a page of unknown length, as some sheet-fed scanners report) is written with the lines actually read; before, it could crash or produce no image.
- **3-pass color scanners** (separate red, green and blue frames) are not supported. Since this version the scan stops after the first frame instead of hanging the process.
- **An unsupported mode or depth** ends the scan with an empty collection (before this version it hung the process).
- If the scanner can't be opened (wrong name, busy, SANE not initialised), the result is an empty collection.

### Example

From the plugin's test form (`TEST` form, object method `scan`):

```4d
If (Form event code:C388=On Clicked:K2:4)
	
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "mode"; "Color")
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "resolution"; "300")
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "depth"; "16")
	
	$images:=SANE Scan(Form:C1466.scanner.name; Scanner image type PNG)
	
	$targetFolder:=Folder:C1567(fk desktop folder:K87:19).folder("scaned documents")
	$targetFolder.create()
	$i:=1
	For each ($image; $images)
		WRITE PICTURE FILE:C680($targetFolder.file(String:C10($i)+".png").platformPath; $image)
		$i:=$i+1
	End for each 
	
End if 
```

JPEG, 8-bit gray (JPEG has no 16-bit mode):

```4d
SANE SET SCAN OPTION($scanner; "mode"; "Gray")
SANE SET SCAN OPTION($scanner; "depth"; "8")
$images:=SANE Scan($scanner; Scanner image type JPEG)
If ($images.length=0)
	ALERT("Nothing was scanned.")
End if 
```

Option names and values (`mode`, `source`, `"ADF Duplex"`, …) are defined by each backend: list them with [SANE Scan option values](#sane-scan-option-values).

---

## SANE Scan option values

### Syntax

```
SANE Scan option values ( scanner ; names ) -> Collection
```

| Parameter | Type | Description |
|---|---|---|
| `scanner` | Text | Device name from [SANE Scanners list](#sane-scanners-list) |
| `names` | Text array | Receives the option names (output) |
| Result | Collection | One object per option |

### Description

Opens the scanner and describes every option it exposes (option 0, the option count, is skipped). Each element is an object:

| Property | Type | Description |
|---|---|---|
| `option` | Longint | Option index |
| `name` | Text | Option name to pass to [SANE SET SCAN OPTION](#sane-set-scan-option) and [SANE Get scan option](#sane-get-scan-option). Empty for group headings |
| `title` | Text | Display title |
| `desc` | Text | Description |
| `type` | Longint | SANE value type (0 to 5) |
| `_type` | Text | `"SANE_TYPE_BOOL"`, `"SANE_TYPE_INT"`, `"SANE_TYPE_FIXED"`, `"SANE_TYPE_STRING"`, `"SANE_TYPE_BUTTON"` or `"SANE_TYPE_GROUP"` |
| `unit` | Longint | SANE unit (0 to 6) |
| `_unit` | Text | `"SANE_UNIT_NONE"`, `"SANE_UNIT_PIXEL"`, `"SANE_UNIT_BIT"`, `"SANE_UNIT_MM"`, `"SANE_UNIT_DPI"`, `"SANE_UNIT_PERCENT"` or `"SANE_UNIT_MICROSECOND"` |
| `size` | Longint | Size of the value in bytes. More than 4 for a `BOOL`/`INT`/`FIXED` option means an array of values |
| `cap` | Longint | SANE capability bits |
| `flags` | Object | `automatic`, `selectable` (can be set) and `detectable` (can be read), all Boolean |
| `values` | Collection or Object | Allowed values, when the option has a constraint (below) |

`values` depends on the constraint:
- a list of strings: a collection of Text (e.g. the `mode` or `source` choices);
- a list of numbers: a collection of numbers. **Its first element is the number of entries**, not a value, and the list stops at the first `0` value (current plugin behaviour);
- a range: an object with `min`, `max` and `quant`.

Numbers of `FIXED` options (list values, `min`, `max`, `quant`) are raw SANE fixed-point integers: divide by 65536 to get the real value.

`names` receives the option names from element 1 on; element 0 holds the whole result as JSON text. If the scanner can't be opened, the result is an empty collection.

### Example

From the plugin's test form (`TEST` form method, `On Load`):

```4d
If (Form:C1466.scanner=Null:C1517)
	ARRAY TEXT:C222($scannerNames; 0)
	$scanners:=SANE Scanners list($scannerNames)
	If ($scanners.length#0)
		Form:C1466.scanner:=$scanners[0]
		Form:C1466.options:=New object:C1471
		Form:C1466.options.source:=SANE Get scan option(Form:C1466.scanner.name; "source")
		ARRAY TEXT:C222($options; 0)
		Form:C1466.option_values:=SANE Scan option values(Form:C1466.scanner.name; $options)
	End if 
End if 
```

The allowed values of one option:

```4d
ARRAY TEXT($names; 0)
$options:=SANE Scan option values($scanner; $names)
For each ($o; $options)
	If ($o.name="source")
		$sources:=$o.values
	End if 
End for each 
```

---

## SANE SET SCAN OPTION

### Syntax

```
SANE SET SCAN OPTION ( scanner ; option ; value )
```

| Parameter | Type | Description |
|---|---|---|
| `scanner` | Text | Device name from [SANE Scanners list](#sane-scanners-list) |
| `option` | Text | Option `name` (case-sensitive) |
| `value` | Text | New value, as text |

### Description

Opens the scanner, sets the option, and closes the scanner again. Options whose `flags.selectable` is false are left alone. The text `value` is converted according to the option's type:

| Type | Conversion |
|---|---|
| `BOOL` | Integer: `"1"` is true, `"0"` is false. `"true"` and `"false"` both give **false** |
| `INT` | Integer (`"300"`). For an array option only the first element is set and, since this version, the others become 0 |
| `STRING` | As is, cut to the option's `size` minus one byte |
| `FIXED` (size 4) | **Raw fixed-point integer**: `"300"` sets 300/65536. Pass the value × 65536 (e.g. `"19660800"` for 300) |
| `BUTTON` | Ignored |

A value the backend rejects is ignored silently.

Each call opens and closes the device. Whether a value set this way is still in effect for the next [SANE Scan](#sane-scan), which opens the device again, depends on the backend: the plugin's own test code relies on it, but SANE doesn't guarantee it (not verified for every backend).

Since this version, a string longer than the option's size is truncated instead of overflowing a buffer, and array options get a buffer of the right size.

### Example

From the plugin's own test method (`TEST.4dm`):

```4d
SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "mode"; "Color")
SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "resolution"; "300")
SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "depth"; "16")
SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "source"; "ADF Duplex")

$images:=SANE Scan(<>DEFAULT_SCANNER; Scanner image type PNG)
```

Set an option and read it back, as the test form's buttons do:

```4d
SANE SET SCAN OPTION($scanner; "source"; "ADF Front")
If (SANE Get scan option($scanner; "source")#"ADF Front")
	ALERT("The scanner did not accept the source.")
End if 
```

---

## SANE Get scan option

### Syntax

```
SANE Get scan option ( scanner ; option ) -> Text
```

| Parameter | Type | Description |
|---|---|---|
| `scanner` | Text | Device name from [SANE Scanners list](#sane-scanners-list) |
| `option` | Text | Option `name` (case-sensitive) |
| Result | Text | Current value as text |

### Description

Opens the scanner, reads the option, and closes the scanner. The value is formatted according to the option's type:

| Type | Result |
|---|---|
| `BOOL` | `"true"` or `"false"` |
| `INT` | Decimal integer. Negative values come out as large unsigned numbers (`-1` gives `"4294967295"`). For an array option, the first element |
| `STRING` | The string |
| `FIXED` (size 4) | Raw fixed-point integer: divide by 65536 |
| `BUTTON` | `""` |

The result is `""` when the scanner can't be opened, the option doesn't exist, or its `flags.detectable` is false.

### Example

From the plugin's test form (`TEST` form, object method `Button1`):

```4d
If (Form event code:C388=On Clicked:K2:4)
	
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "source"; "ADF Duplex")
	
	Form:C1466.options.source:=SANE Get scan option(Form:C1466.scanner.name; "source")
	
End if 
```

A numeric option:

```4d
$dpi:=Num(SANE Get scan option($scanner; "resolution"))
```

---

## Error handling & troubleshooting

- **Nothing is found or scanned after a restart.** SANE is initialised only by [SANE Scanners list](#sane-scanners-list). Call it once per 4D session before the other commands, even if you already know the scanner name.
- **No 4D error is ever raised.** Check results instead: an empty collection from [SANE Scan](#sane-scan) or [SANE Scan option values](#sane-scan-option-values), `""` from [SANE Get scan option](#sane-get-scan-option), and read an option back after [SANE SET SCAN OPTION](#sane-set-scan-option).
- **The scanner list is `Null`, or JSON parsing fails.** SANE could not be initialised, e.g. backends or configuration missing from the bundle.
- **Don't use the plugin from two processes at once.** [SANE Scanners list](#sane-scanners-list) restarts SANE and can pull the backends from under a scan running in another process, and two processes opening the same device can be refused as busy. Serialise access, e.g. with a semaphore.
- **A value doesn't stick.** The option may not be `selectable`, the value may be outside `values`, a `BOOL` must be `"1"` or `"0"`, and a `FIXED` value must be passed × 65536. A backend may also reset options when the device is reopened.
- **Garbled JPEG.** JPEG has no 16-bit mode: set `depth` to 8, or use PNG.
- **Inverted lineart PNG.** 1-bit scans saved as PNG are expected to have black and white swapped: use JPEG or 8-bit gray.
- **The scan stops early.** Each page is read for at most 30 seconds, and a 3-pass color scanner stops after the first frame.
- **A backend doesn't load on macOS 11.** The bundled backends and `libusb` require macOS 12.

---

## Quick reference

```4d
ARRAY TEXT($names; 0)
$scanners:=SANE Scanners list($names)
$scanner:=$scanners[0].name

ARRAY TEXT($options; 0)
$info:=SANE Scan option values($scanner; $options)

SANE SET SCAN OPTION($scanner; "mode"; "Color")
SANE SET SCAN OPTION($scanner; "resolution"; "300")
SANE SET SCAN OPTION($scanner; "source"; "ADF Duplex")
$source:=SANE Get scan option($scanner; "source")

$pages:=SANE Scan($scanner; Scanner image type PNG)
```

---

## Build notes

The modified SANE sources are in [modification/](modification).

### Patches

* sane-backends/backends/dll.c: reference ``SANE_LD_LIBRARY_PATH`` instead of ``LD_LIBRARY_PATH`` for portability.

* libsub/darwin_usb: ignore hotplug to avoid ``pthread`` crash. 

* also set ``LD_LIBRARY_PATH`` for compatibility with standard libsane. `3.0.1`

to compile sane via CLI

* backend/Makefile: `-version-number "1:1:1"` because of`UNKNOWN`

* sane-backends/backends/dll.c, net.c: `V_MAJOR`, etc. to literal `1` 

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

~~libusb.a for the main plugin is compiled with hotplug.~~ the main plugin is also linked to the dynamic library. `3.0.1`

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
