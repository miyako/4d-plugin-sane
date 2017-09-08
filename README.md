# 4d-plugin-sane
SANE for macOS

---

### Build Settings

```
export CCFLAGS="-arch x86_64"
export CXXFLAGS="-arch x86_64"
export CFLAGS="-arch x86_64 -mmacosx-version-min=10.8"
export LDFLAGS="-arch x86_64 -mmacosx-version-min=10.8"
export CPPFLAGS="-arch x86_64 -mmacosx-version-min=10.8"
export PRELOADABLE_BACKENDS=""

./configure --enable-shared --enable-static
```

```
export CCFLAGS="-arch i386"
export CXXFLAGS="-arch i386"
export CFLAGS="-arch i386 -mmacosx-version-min=10.8"
export LDFLAGS="-arch i386 -mmacosx-version-min=10.8"
export CPPFLAGS="-arch i386 -mmacosx-version-min=10.8"

./configure --enable-shared --enable-static
```

**Note**: specifying an older (10.8) SDK fails with ``-lcrypto.32`` error.
