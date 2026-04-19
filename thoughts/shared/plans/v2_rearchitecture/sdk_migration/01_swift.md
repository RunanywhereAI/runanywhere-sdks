# Swift SDK — migration plan

> `sdk/runanywhere-swift/` ships the production Swift Package that
> iOS/macOS consumers depend on via SPM. Today it links against
> pre-built XCFrameworks (`RACommons.xcframework`, `RABackendLLAMACPP`,
> `RABackendONNX`, optional `RABackendMetalRT`) downloaded from GitHub
> releases. Underneath those XCFrameworks is the legacy
> `sdk/runanywhere-commons/` C++ source tree.
>
> **Goal of this migration:** the XCFrameworks `RACommons` and its
> backend counterparts are rebuilt from the new `core/` + `engines/`
> trees instead, preserving the exact same C symbol names the Swift
> source calls (so zero Swift-side changes to
> `sdk/runanywhere-swift/Sources/RunAnywhere/*`).

## Step 1 — Current interop layer

Files under `sdk/runanywhere-swift/Sources/` that bridge to C:

| Swift target | Bridged C ABI | Links against |
|---|---|---|
| `RunAnywhere/CRACommons/` | `rac_*` symbols from `sdk/runanywhere-commons/include/rac/**/*.h` | `RACommonsBinary` (XCFramework) |
| `LlamaCPPRuntime/` | llama.cpp C symbols + `rac_backend_llamacpp_*` glue | `RABackendLlamaCPPBinary` |
| `ONNXRuntime/` | ORT C API + `rac_backend_onnx_*` | `RABackendONNXBinary`, `ONNXRuntime{iOS,macOS}Binary` |
| `WhisperKitRuntime/` | WhisperKit Swift package directly | n/a (Swift-to-Swift) |
| `MetalRTRuntime/` (optional) | MetalRT C symbols | `RABackendMetalRTBinary` |

## Step 2 — Symbol inventory

Every `rac_*` called from Swift is on a short list (grep
`sdk/runanywhere-swift/Sources/RunAnywhere` for `rac_` matches). Group:

1. **Engine registration**: `rac_backend_llamacpp_register`,
   `rac_backend_onnx_register`, `rac_backend_whispercpp_register`, …
2. **LLM**: `rac_llm_service_create`, `rac_llm_generate`, `rac_llm_stop`,
   `rac_llm_destroy`.
3. **STT**: `rac_stt_service_create`, `rac_stt_feed_audio`, `rac_stt_flush`,
   `rac_stt_destroy`.
4. **TTS**: `rac_tts_service_create`, `rac_tts_synthesize`, `rac_tts_stop`,
   `rac_tts_destroy`.
5. **VAD**: `rac_vad_service_create`, `rac_vad_feed`, `rac_vad_destroy`.
6. **Embeddings**: `rac_embeddings_*`.
7. **Voice agent**: `rac_voice_agent_*`.
8. **Server**: `rac_server_*`.
9. **Events**: `rac_set_event_callback`.
10. **Errors**: `rac_error_string`.
11. **Download**: `rac_download_*`.
12. **Extraction**: `rac_extract_*`.
13. **File manager**: `rac_file_manager_*`.
14. **Device + telemetry**: `rac_device_*`, `rac_telemetry_*`.
15. **Network / auth**: `rac_http_*`, `rac_auth_*`, `rac_endpoints_*`.

## Step 3 — ABI mapping

A C-level shim header (new file `sdk/runanywhere-swift/Sources/
RunAnywhere/CRACommons/include/rac_compat.h`) aliases every legacy
`rac_*` call site to the corresponding new `ra_*` function via
`#define` or an inline wrapper. Example:

```c
// rac_compat.h — maps legacy SDK call sites onto the new ABI.
static inline ra_status_t rac_llm_generate(ra_llm_session_t* s,
                                             const ra_prompt_t* p,
                                             ra_token_callback_t on_token,
                                             ra_error_callback_t on_error,
                                             void* ud) {
    return ra_llm_generate(s, p, on_token, on_error, ud);
}
```

Paths that don't translate 1:1 (e.g. legacy's `rac_voice_agent_*`
callback-returning entry vs. the new `ra_voice_agent_*` stream-based
entry) need a thin C glue file that bridges the call shapes.

## Step 4 — Native artifact

New script `sdk/runanywhere-swift/scripts/build-core-xcframework.sh`:

```bash
#!/usr/bin/env bash
# Builds the new C++ core as an XCFramework for iOS + iOS Simulator +
# macOS. Outputs into Binaries/RACommons.xcframework (so the existing
# Package.swift binary-target path stays the same).
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
OUT=${ROOT}/sdk/runanywhere-swift/Binaries

for triple in "OS64" "SIMULATOR64" "MAC"; do
    cmake -S ${ROOT} -B build/ios-${triple} \
        -G Xcode \
        -DCMAKE_TOOLCHAIN_FILE=${ROOT}/cmake/ios.toolchain.cmake \
        -DPLATFORM=${triple} \
        -DRA_BUILD_TESTS=OFF \
        -DRA_BUILD_TOOLS=OFF \
        -DRA_STATIC_PLUGINS=ON
    cmake --build build/ios-${triple} --config Release
done

xcodebuild -create-xcframework \
    -library build/ios-OS64/core/libra_core.a \
    -headers build/ios-OS64/install/include \
    -library build/ios-SIMULATOR64/core/libra_core.a \
    -library build/ios-MAC/core/libra_core.a \
    -output ${OUT}/RACommons.xcframework
```

## Step 5 — Wire the interop layer

Update `Package.swift` so the `RACommonsBinary` target's path points at
the newly-built XCFramework. Nothing else in `Package.swift` changes —
the Swift sources keep calling `rac_*` through the shim.

## Step 6 — Run the SDK's own tests

```
cd sdk/runanywhere-swift
swift test
```

Existing RunAnywhereTests should remain green. Anything that fails
points at an ABI gap we haven't bridged yet — fix in `rac_compat.h` or
in a new C glue.

## Step 7 — Run the example app

```
cd examples/ios/RunAnywhereAI
./scripts/build_and_run.sh simulator "iPhone 15"
```

Verify: chat works, voice agent works, model download works,
OpenAI-compatible server works.

## Known risks

- **Model download chain** requires the extraction module to be ported.
  If not yet ported, model-download flows fail until that lands.
- **OpenAI HTTP server** is ported but needs a smoke test against the
  example app's embedded server flow.
- **MetalRT** is optional; its native binary is still produced from
  legacy commons. Can be ported in a follow-up PR.

## Rollout

After this migration, sdk/runanywhere-swift continues to ship from the
same path with the same public API. The release workflow now pulls
XCFrameworks built from new core, not legacy.
