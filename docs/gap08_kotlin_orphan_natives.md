# GAP 08 Phase 23 — Kotlin Orphan `external fun native*` Audit

Audit of `external fun native*` declarations across
`sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridge*.kt`.
Each declaration that compiles but binds to a JNI symbol that no longer
exists (or never existed) is dead weight — the JVM only fails when a
caller actually invokes the method.

| File                          | `external fun native*` count |
|-------------------------------|------------------------------|
| `CppBridgeVoiceAgent.kt`      | 11                           |
| `CppBridgeTTS.kt`             | 11                           |
| `CppBridgeVAD.kt`             | 11                           |
| `CppBridgeSTT.kt`             | 10                           |
| `CppBridgeLLM.kt`             |  9                           |
| `CppBridgeServices.kt`        |  6                           |
| `CppBridgeStorage.kt`         |  4                           |
| `CppBridgePlatform.kt`        |  4                           |
| `CppBridgeModelPaths.kt`      |  5                           |
| `CppBridgeModelAssignment.kt` |  5                           |
| `CppBridgeDownload.kt`        |  5                           |
| `CppBridgeStrategy.kt`        |  3                           |
| `CppBridgeState.kt`           |  2                           |
| `CppBridgeDevice.kt`          |  2                           |
| **Total today**               | **88**                       |

## Method to identify orphans

```bash
# 1. Build the JNI .so locally:
cmake --preset linux-release && cmake --build --preset linux-release

# 2. Symbol-table dump:
nm -D --defined-only build/linux-release/sdk/runanywhere-commons/librac_commons.so |
    grep -E 'Java_com_runanywhere_sdk_foundation_bridge' > /tmp/jni-defined.txt

# 3. Orphan list = declared - defined:
rg -oN 'external fun (\w+)' \
    sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridge*.kt \
    | sort -u > /tmp/kt-declared.txt
diff /tmp/jni-defined.txt /tmp/kt-declared.txt
```

## Status

**v2 close-out Phase 8 update — 27 orphan declarations deleted (4,318 LOC).**

Symbol-diff result on the actual shipped `librunanywhere_jni.so`
(arm64-v8a from `sdk/runanywhere-kotlin/src/androidMain/jniLibs/`):

```
$ nm -gU librunanywhere_jni.so | grep "Java_com_runanywhere" | wc -l
147   # all defined JNI symbols

$ nm -gU librunanywhere_jni.so | grep "Java_com_runanywhere" | \
    awk '{print $NF}' | sort -u | grep "Java_com_runanywhere_sdk_foundation_bridge_extensions"
0     # ZERO symbols under the foundation/bridge/extensions/ class path
```

Every `external fun native*` declaration inside a CppBridge*.kt object
binds to a symbol named `Java_com_runanywhere_sdk_foundation_bridge_extensions_CppBridgeFoo_nativeBar` — but the `.so` only ships symbols
under `RunAnywhereBridge` (the legacy class). **Every** native
declaration in a `CppBridge*.kt` object is therefore an orphan that
would throw `UnsatisfiedLinkError` on first call.

Phase 8 deleted the 3 zero-caller files outright:

| File                        | LOC  | `external fun native*` count | External callers |
|-----------------------------|------|------------------------------|------------------|
| `CppBridgeServices.kt`      | 1285 |  8 | **0** |
| `CppBridgeStrategy.kt`      | 1204 |  5 | **0** |
| `CppBridgeVoiceAgent.kt`    | 1829 | 14 | 1 (just the doc comment from Phase 6, fixed in same commit) |
| **Total deleted**           | **4318** | **27** | — |

The remaining `CppBridge*.kt` files (Auth, Device, Download, Events,
FileManager, HTTP, LLM, LoraRegistry, ModelAssignment, ModelPaths,
ModelRegistry, Platform, PlatformAdapter, State, Storage, STT,
Telemetry, ToolCalling, TTS, VAD, VLM) all have ≥1 external caller and
some have many — pruning their orphan native declarations requires
either:

  - **Per-method analysis**: trace each `nativeFoo()` call inside the
    CppBridge to see if it's reachable from a public method that any
    consumer calls. Removing only the unreachable paths is mechanical
    but file-by-file work.
  - **Bulk wait**: keep them in place until the JNI .so adds the
    matching symbols (the C++ side of the bridge is tracked under the
    eventual JNI-thunk PR — see `docs/v2_closeout_phase5_cabis.md`).

Today's commit takes the first option for the 3 files where ALL paths
are unreachable. The remaining ~95 declarations across the 21 surviving
files are queued for the per-bridge cleanup that ships with each JNI
implementation.
