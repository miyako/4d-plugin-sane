# SANE ownership audit

## Reproduction and scope

Run on macOS with the existing Apple compiler and Python 3; no dependencies
are installed:

```sh
python3 tests/ownership/run.py
```

The runner compiles **all seven actual Xcode source members**, including the
entire unmodified SDK implementation, as separate translation units. It prints
SHA-256 identities for the actual source/header inputs and the harness. It
does not build the Xcode project or run a scheme, hook, 4D database or plugin
bundle.

The same harness can check the immutable baseline:

```sh
git archive 93b264a53f0c6fedf141aab10560d96eb3f4e093 \
  '4D Plugin API' 4DPlugin-SANE.cpp 4DPlugin-SANE.h support include manifest.json \
  | tar -x -C /path/to/empty/baseline-directory
python3 tests/ownership/run.py /path/to/empty/baseline-directory --expect-baseline
```

Only the fixture boundaries differ from production: every referenced SANE
function is a memory-only stub; PNG produces the token `PNG` through the actual
plugin callback; JPEG is denied; the JSON writer is a small in-memory fixture.
No actual codec, libsane, libusb, backend, scanner discovery or acquisition is
linked or executed. Calls to the exported `FourDPackex` entry point exercise
selectors 1-5 and close-process, not reconstructed command implementations.
Initialization selectors are not invoked: bundle lookup, environment changes,
URL/path operations and drawing are denied. Time and 4D process scheduling
are synthetic. Unexpected engine selectors/commands and external imports
fail closed before execution. Pure Foundation/CoreFoundation string conversions
and C++ worker threads operate on synthetic memory only.

Both `ASan` and `UBSan` are enabled. Alignment instrumentation is disabled
because the unchanged SDK ABI uses packed structures. macOS LeakSanitizer is
not claimed; the host shim explicitly accounts for its string, picture,
reference and handle owners. Each balance assertion is evaluated **before**
isolating leaked baseline fixtures.

## Provenance

Baseline: `93b264a53f0c6fedf141aab10560d96eb3f4e093`.
Header labels (`v13`/`v14`) are not upstream SDK identities.

| Protected input | Baseline Git blob (unchanged by the fix) |
|---|---|
| `4DPluginAPI.c` | `a16cbe0c4754117ede8035923a5b2730e2899dca` |
| `4DPluginAPI.h` | `8d8477b77f5cad2a7a8739c1f89fcec337550c82` |
| `PublicTypes.h` | `9ae20b001bff9128f690fff3e6c3f873b6238333` |
| `PrivateTypes.h` | `a3098cb662cdbc43ba574fdef72a059c4c6d1cd4` |
| `EntryPoints.h` | `da428d5f6ca23b0a30371c7288a01d29aa3c466a` |
| `Flags.h` | `7a5a35539f27430a3fd9cb711d6b789051316471` |
| `4DPluginAPI.def` | `5bbdb82fb724b6f8e307feb01d9f158b802de89d` |

Guidance was read at `miyako/skills` commit
`e6b492fcb81e5e1a7f7db723594b420e63bf6eb9`,
`4d-skills/skills/4dplugin/SKILL.md` blob
`aabdd402ca8bd87be6c84a1a61f2118ad4d4cb13`. The immutable PDF Kit
`f39fca860ccbba6f06179c6b6defbf0ea17bb636` harness informed the fixture
approach; its SDK identities, assertions and results were not assumed to
apply here.

## Complete native/build inventory

| Surface | Ownership/reachability conclusion |
|---|---|
| Xcode source members | `4DPlugin-SANE.cpp`, `4DPluginAPI.c`, `C_TEXT.cpp`, `ARRAY_TEXT.cpp`, `C_BLOB.cpp`, `C_LONGINT.cpp`, `support/4DPlugin-JSON.cpp`; all compiled by this runner. |
| Windows project | Includes only the SDK and dispatcher, omits the wrappers, and cannot implement the Objective-C++/macOS plugin. No Windows build or host claim. |
| Dispatcher/manifest | Five non-thread-safe commands: scanners `(&Y):C`, scan `(&T;&L):C`, option list `(&T;&Y):C`, set option `(&T;&T;&T)`, get option `(&T;&T):T`. Root and bundled manifests agree. `.def` exports `FourDPackex`. |
| Selectors 1 and 3 | UTF-8 device/option names and JSON are copied into independent C++ strings, then into independently owned array descriptors. Parsed collection result is transferred directly to 4D, not locally cleared. Failure/mismatch paths are checked before adopting outputs. |
| Selector 2 | Local pixel and encoded-byte vectors feed the synchronous picture creation boundary; picture variable is cleared after collection insertion. The collection retains its own picture and is transferred to the result. The overwritten initialized-empty picture owner was a confirmed leak. A scoped collection owner protects failure paths before handoff. |
| Selectors 4 and 5 | Scalar inputs are copied from borrowed host buffers; returned text is set through `PA_SetUnistring`, not descriptor transfer. SANE value buffers are local vectors. All tested without real device calls. |
| Worker lifetimes | Lambdas capture `Param1`, `Param2`, JSON and picture vectors by reference, not by owning-wrapper value. Their local `future` is waited on and destroyed before captured locals. No wrapper shallow-copy lifetime is required by these consumers. |
| PNG/JPEG callbacks | PNG `io` is a borrowed pointer to the local `C_BLOB`, consumed synchronously while that owner is alive. JPEG destination owns/reallocates a separate byte buffer, read before destruction. Actual codecs are out of runtime scope; PNG callback is exercised synthetically, JPEG denied. |
| Process close | `PA_GetProcessInfo_s` success produces owned text; the wrapper reads it while alive, then clears it. Failure is checked first. No user method callbacks or independently retained callback variables exist in plugin consumers. |
| `C_TEXT` | Owns one C++ UTF-16 string; already noncopyable. Scalar input is copied, outputs use engine content setter. UTF conversion lengths are UTF-16 units on the native side and bytes on the UTF-8 side. NSString string-copy helpers are memory-only; URL/path helpers are platform-boundary deferrals. |
| `ARRAY_TEXT` | Owns a vector of independent C++ strings. Array reads are borrowed/copy-only. Accepted array writes transfer fresh descriptors including element zero. Failed resize now stops before insertion, and successful metadata is published before partial string output. Null-data destination is explicitly rejected. Indexed pointer setter and explicit-length conversions are corrected. Shallow owner copy is disabled. The `PA_Unistring*` indexed overload is declared but has no implementation or callers; no ABI was invented for it. |
| `C_BLOB` / `CBytes` | `C_BLOB` owns a `CBytes`; shallow copy is disabled. `CBytes` itself contains a value vector. Incoming handles remain borrowed and bytes are copied; newly allocated outgoing handles transfer to caller. Failed replacement now retains the original handle. Empty input and Base64 reuse reset prior contents. Codec helpers, cursor/byte accessors and scalar output paths are part of the source inventory; no external allocator contract is inferred. |
| `C_LONGINT` | Value-only integer, no heap owner; parameter and return controls run. |
| Every JSON helper | All are compiled Xcode members but **no plugin dispatcher calls them**. Every setter overload, all five getters, defined-property and stringify are exercised directly, not exempted as dormant. Successful scalar/mismatched getter results are cleared. Matching object/collection results hand an owned reference to caller, exercised through final disposal. Setter inputs retain the existing conditional consuming convention for picture/object/collection; stringify only borrows its object synchronously. |
| Third-party headers/binaries | `include/{json,jpeglib,libpng16,libusb-1.0,sane,tiff}`, `a/`, `lib/`, `sane/` and committed test bundle are external/device/codec boundaries, not additional 4D wrappers. No such binary is loaded by the harness. |
| Third-party source modifications | `modification/darwin_usb.c` and `modification/dll.c` are libusb/SANE source patches, not Xcode source members; contain no 4D calls or owning wrappers. They require missing upstream build context and would perform prohibited device/dynamic-loading operations, so are inventory-only, unchanged. |
| Bundled 4D test project | `.4dm` methods/forms describe real scanning workflows. Not run; no real data, images, database, journal or filesystem fixtures are opened. |

## Exact SDK contracts

The conclusions come from this complete SDK, not function names:

- `PA_CreateUnistring` calls the engine and returns a caller-owned descriptor
  on success. Its failure descriptor is unspecified. `PA_SetUnistring` passes
  a null-terminated UTF-16 content pointer; its outputs are not array ownership
  transfers. Explicit embedded-null conversion is tested inside C++ wrappers;
  the SDK's null-terminated host setters still terminate at the first null.
- `PA_GetStringInArray` aliases a descriptor. `PA_SetStringInArray` accepts
  only Unicode-array kind, non-null `fData` handle, non-null string pointer and
  indices `0 <= i <= fNbElements`. It disposes the old element then
  shallow-assigns the incoming descriptor. Rejection retains the caller's
  owner. There is intentionally no blanket post-insertion dispose.
- `PA_ResizeArray` unconditionally changes local `fNbElements` after an
  attempted resize, even when allocation failed. Capacity is **not** inferred
  from that count. The wrapper captures the immediate error and stops;
  protected SDK behavior is unchanged. No-op resize does not refresh the
  SDK error, so the wrapper does not mistake a stale error for resize failure.
- `PA_SetStringVariable`, picture/object/collection setters shallow-assign
  their payloads. Creating an initialized empty string/picture variable and
  overwriting it leaks the prior owner. `PA_CreateVariable(eVK_Undefined)`
  avoids that allocation where appropriate.
- The SDK explicitly requires clearing successful `PA_GetObjectProperty`
  and `PA_GetCollectionElement` results. A matching raw reference can instead
  be handed to the caller, which must finally dispose it. All nonmatching
  success values are cleared; failed values are not interpreted or cleared.
- `PA_ExecuteCommandByID` produces an owned success result. Error is captured
  before key disposal, kind inspection or result adoption. Raw kind zero can
  normalize as text; it is not evidence that a failed output is valid.
- `PA_ReturnCollection` just writes the reference to the output slot:
  no independent retain or copy is implemented. Clearing the returned
  collection locally would therefore be wrong. Array output is completed
  before this handoff, so a failed array write cannot overwrite/leak an
  already-transferred result when the dispatcher returns its empty fallback.
- Picture data ownership stays with the created picture variable until
  collection insertion copies/retains it. The fixture models independent
  collection ownership; it does not claim to verify a real 4D codec.

## Results

The identical final harness on the immutable baseline produces **169 main
checks: 60 exact named failures and 109 passing controls**. The ordered
`FAIL ...` lines (including duplicates and final newline) hash to SHA-256
`3a846a69ab2a764188549a108dd434fb63d90c95c9e4c3694cacfddf63302786`.
`--expect-baseline` asserts that identity, counts and real child exit codes.

Both separately named baseline processes, `--resize-failure` (direct wrapper)
and `--dispatcher-resize-failure` (actual exported consumer), abort with
ASan `heap-buffer-overflow` in `PA_SetStringInArray`, at protected SDK line
4945. They are expected/asserted failures, not normal test passes.

The fixed source passes **169 main checks plus 2 direct-wrapper and 2
exported-dispatcher resize-error checks**, with child exit codes `[0, 0, 0]`.
Cases cover ASCII/BMP/supplementary/empty text, exact byte/unit lengths and
terminators, descriptor replacement/reuse and element zero, rejected
destination/index and null data, explicit embedded null conversion, successful
raw kind zero, reference handoff, every owning mismatch, unspecified failure
outputs, string/property/parse/picture/handle failures and final owner balances.

## Safety and explicit gaps

Existing workflows are tag/manual release and manual version bump only;
neither is invoked. Xcode's Deployment phase signs, packages and notarizes,
and its other phase edits install names. No project configuration is built.
The new CI job is read-only, unsigned, uses `macos-15`, installs nothing and
only runs this synthetic harness on PRs targeting master and master pushes.
Git write operations for this audit disable hooks per invocation rather than
reading or running shared-checkout hooks.

Not verified: Windows, Intel execution, real 4D host/engine allocation
metadata, real scanner/device acquisition, native graphics/codecs, dynamic
backends, real path/OS/UI operations, packed alignment or LeakSanitizer.
Injected failures reproduce specified shim contracts, not actual host OOM.
The SDK can mask intermediate failures (for example array initialization
calls lock/unlock after allocation, and collection helpers may inspect their
internal result before the caller can check the error). Those protected
engine internals are not repaired or claimed safe here.

Dormant external callers are absent, so there is no evidence to change the
conditional consuming convention of `ob_set_p/o/c` into a borrowing or
deep-copy contract. Existing consuming behavior is preserved and tested.
Returned getters are explicitly owned, not magically borrowed. Genuine
`PA_GetStringVariable` conversions beyond actual text values, real engine
retain/copy behavior, unavailable allocator metadata and third-party/device
callbacks remain external-contract gaps, not fabricated fixes.
