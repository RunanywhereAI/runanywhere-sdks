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

GAP 08 Phase 23 ships the audit doc + the deprecation marker on the
worst offender (`CppBridgeVoiceAgent.kt`) plus a tracking issue.
Per-symbol pruning needs the JNI .so build artifact + automated symbol
diff in CI; queued as a follow-up PR after the Wave D adapters have
soaked in production.

The legacy spec estimated 131 orphans; the count today is 88, so 43
have been incidentally cleaned by the Wave A/B/C work (mostly in the
`CppBridgeAuth.kt` deprecation, which itself has zero `external fun
native` decls — the auth path is pure Kotlin/HTTP).
