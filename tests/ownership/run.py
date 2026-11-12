#!/usr/bin/env python3
"""Compile actual plugin/SDK sources against deny-by-default memory fixtures."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

arguments = [arg for arg in sys.argv[1:] if arg != "--expect-baseline"]
expect_baseline = "--expect-baseline" in sys.argv
root = Path(arguments[0] if arguments else ".").resolve()
here = Path(__file__).resolve().parent
sources = [
    "4D Plugin API/4DPluginAPI.c",
    "4D Plugin API/Classes/C_TEXT.cpp",
    "4D Plugin API/Classes/ARRAY_TEXT.cpp",
    "4D Plugin API/Classes/C_BLOB.cpp",
    "4D Plugin API/Classes/C_LONGINT.cpp",
    "support/4DPlugin-JSON.cpp",
    "4DPlugin-SANE.cpp",
]
for path in sorted(set(
    [root / name for name in sources]
    + list((root / "4D Plugin API").rglob("*.h"))
    + [root / "support/4DPlugin-JSON.h", root / "4DPlugin-SANE.h", root / "manifest.json"]
    + list(here.rglob("*.h")) + [here / "main.mm", here / "run.py"]
)):
    print(hashlib.sha256(path.read_bytes()).hexdigest(), path, flush=True)

with tempfile.TemporaryDirectory(prefix="sane-ownership-") as directory:
    out = Path(directory)
    flags = [
        "-g", "-O1", "-fsanitize=address,undefined", "-fno-sanitize=alignment",
        "-fno-omit-frame-pointer", "-Wno-deprecated-declarations", "-Wno-multichar",
        "-Wno-deprecated-builtins", "-I" + str(here / "boundaries"),
    ]
    for path in [
        "4D Plugin API", "4D Plugin API/Classes", "support", "include/sane",
        "include/libusb-1.0", "include/libpng16", "include/tiff", "include/jpeglib",
    ]:
        flags.append("-I" + str(root / path))
    objects = []
    for i, source in enumerate([root / n for n in sources] + [here / "main.mm"]):
        obj = out / (str(i) + ".o")
        language = ["-x", "c", "-Wno-int-conversion"] if source.suffix == ".c" else [
            "-x", "objective-c++", "-std=c++14"
        ]
        subprocess.run(["clang++", *flags, *language, "-c", str(source), "-o", str(obj)],
                       check=True)
        objects.append(str(obj))
    exe = out / "ownership"
    subprocess.run(["clang++", *flags, *objects, "-framework", "Cocoa",
                    "-framework", "CoreFoundation", "-o", str(exe)], check=True)
    imports = subprocess.check_output(["nm", "-u", str(exe)], text=True)
    exact = {
        "_abort", "_calloc", "_free", "_malloc", "_realloc", "_memcmp", "_memcpy",
        "_memmove", "_memset", "_strlen", "_wcslen", "_isspace", "_sprintf",
        "_snprintf", "_vsnprintf", "_printf", "_fprintf", "_fwrite", "_puts",
        "_exit", "_atexit", "_bzero", "dyld_stub_binder", "__Unwind_Resume",
        "__tlv_bootstrap", "_memchr", "_kCFAllocatorDefault", "_CFRelease",
        "_CFStringCreateWithBytes", "_CFStringCreateWithCharacters", "_CFStringGetLength",
        "_CFStringGetCharacters", "_CFStringGetMaximumSizeForEncoding", "_CFStringGetBytes",
        "_setjmp", "_longjmp", "_atoi", "___stack_chk_fail", "___stack_chk_guard",
        "__DefaultRuneLocale",
        "_class_getClassMethod", "_class_getInstanceMethod", "_method_setImplementation",
        "_sel_registerName",
        "_pthread_create", "_pthread_detach", "_pthread_join", "_pthread_setspecific",
        "_strcmp", "_strcpy", "_strncmp",
    }
    allowed_classes = {"NSString", "NSMutableString", "NSURL", "NSBundle", "NSDate"}
    unexpected = []
    for symbol in (s.strip() for s in imports.splitlines() if s.strip()):
        if any(p in symbol for p in ("basic_filebuf", "basic_ifstream", "basic_ofstream",
                                     "basic_fstream", "filesystem", "random_device")):
            raise RuntimeError("Forbidden external-data import: " + symbol)
        if symbol.startswith("_OBJC_CLASS_$_") and symbol[14:] in allowed_classes:
            continue
        if symbol in exact or symbol.startswith(("___", "__Z", "_objc_")):
            continue
        unexpected.append(symbol)
    if unexpected:
        raise RuntimeError("Unexpected imports before execution: " + repr(unexpected))
    linked = subprocess.check_output(["otool", "-L", str(exe)], text=True)
    if any(n in linked.lower() for n in ("libsane", "libusb", "libjpeg", "libpng", "libtiff")):
        raise RuntimeError("Real device/graphics library linked")
    print("PASS pre-execution synthetic boundary/import gate", flush=True)
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
    results = []
    outputs = []
    for args in ([], ["--resize-failure"], ["--dispatcher-resize-failure"]):
        print("CASE", args or ["all-consumers"], flush=True)
        result = subprocess.run([str(exe), *args], env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end="", flush=True)
        results.append(result.returncode)
        outputs.append(result.stdout)
    print("case_exit_codes=" + repr(results), flush=True)
    if expect_baseline:
        failures = "\n".join(line for line in outputs[0].splitlines()
                             if line.startswith("FAIL ")) + "\n"
        signature = hashlib.sha256(failures.encode()).hexdigest()
        expected = "3a846a69ab2a764188549a108dd434fb63d90c95c9e4c3694cacfddf63302786"
        if not (results == [1, -6, -6] and "checks=169 failures=60" in outputs[0]
                and signature == expected
                and "AddressSanitizer: heap-buffer-overflow" in outputs[1]
                and "PA_SetStringInArray" in outputs[1]
                and "AddressSanitizer: heap-buffer-overflow" in outputs[2]
                and "PA_SetStringInArray" in outputs[2]):
            raise RuntimeError("Unexpected baseline result/signature: " + signature)
        print("PASS immutable baseline: 60 exact named failures, 109 controls; "
              "isolated wrapper and dispatcher failed-resize ASan overflows asserted", flush=True)
        sys.exit(0)
    sys.exit(1 if any(results) else 0)
