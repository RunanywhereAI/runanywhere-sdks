# Path A Restoration Progress

Living tracker for the post-cutover restoration effort that re-implements
every dropped legacy-v1 capability on the new v2 architecture.
Source plan: `/Users/sanchitmonga/.cursor/plans/path_a_restore_parity_b9043b08.plan.md`.

## Status by wave

| Wave | Goal | Status | Notes |
|---|---|---|---|
| 0 — Swift P0 API fixes | iOS sample compiles | **Done** | `Modality`, `ArchiveFormat`/`ArchiveStructure`, `ModelFileDescriptor.filename`, `InferenceFramework.whisperKitCoreML`/`.metalrt`, `availableModels()` async, `LoRAAdapterCatalog`, `storageInfo()`, `deleteModel()`, `downloadModel` stream, `environment`, no-arg `initialize()`, `generateImage(prompt:options:)`. 38 Swift tests green. |
| 1 — Swift platform services | Real AVFoundation + Keychain + Sentry | **Done** | `sdk/swift/Sources/RunAnywhere/Platform/{AudioCaptureManager, AudioPlaybackManager, KeychainManager, DownloadService, SentryAdapter}.swift`. |
| 2a — ONNX engine | Real ORT plugin | Pending | Stub only. Needs port of `sdk/runanywhere-commons/src/backends/onnx/**` (4599 LoC). Requires vcpkg onnxruntime + onnxruntime-genai. |
| 2b — WhisperKit | Real STT vtable | Pending | Stub only. Needs Swift port + `@_cdecl` bridge. Requires `WhisperKit` SPM dep. |
| 2c — CoreML Diffusion | Real diffusion vtable | Pending | Stub only. Needs `ml-stable-diffusion` SPM dep + `features/diffusion/*.cpp` port. |
| 2d — Foundation Models | Apple Intelligence LLM | **Done** | `sdk/swift/Sources/Backends/FoundationModelsRuntime/` wires `ra_platform_llm_*` with `@available(iOS 26, macOS 26)` gate. |
| 2e — MetalRT | Apple GPU runtime | Pending | Stub only. Closed-source Apple SDK; gate via `RA_METALRT_SDK_DIR`. |
| 3a — Auth manager ABI | 16 `ra_auth_*` fns | **Done** | `core/abi/ra_auth.{h,cpp}` + 6 gtests. |
| 3b — Telemetry ABI | 11 `ra_telemetry_*` fns | **Done** | Device-registration struct + JSON serialiser + batch response parser + properties helper + 5 gtests. |
| 3c — Download orchestrator | Chunk resume + SHA256 + extract | Pending | Existing `ra_download.*` has foundation; need orchestrator-level retry/backoff logic port. |
| 3d — Model management | Framework × category matrix + format detect | **Done** | `core/abi/ra_model.{h,cpp}` + new `RA_MODEL_CATEGORY_*` enum + `RA_FORMAT_*` extensions + 6 gtests. |
| 3e — RAG | Real vector store + ONNX embedder | Pending | Needs 2a (ONNX) first. Full port of `features/rag/*` (4121 LoC) to `solutions/rag/`. |
| 4 — OpenAI server | Real HTTP server | Pending | Needs 2a + 3a. Port `sdk/runanywhere-commons/src/server/*` (2481 LoC). |
| 5 — Kotlin JNI | Full JNI surface | Pending | Largest item (~31k LoC). Strategy: thin `jni_all.cpp` instead of 23 CppBridge*.kt files. |
| 6 — React Native | Nitro + JSI | Pending | `sdk/rn/packages/{core,llamacpp,onnx,genie}` federated structure. |
| 7 — Flutter | Federated packages | Pending | `sdk/dart/packages/runanywhere{,_llamacpp,_onnx,_genie}`. |
| 8 — Web + WASM | Per-backend WASM bundles | Pending | `scripts/build-core-wasm.sh` + EMBIND. |
| 9 — Tests + CI + docs | Green matrix | **In progress** | Legacy pr-build / release / auto-tag workflows removed. Docs updated. |

## What's actually in each landed wave

### Wave 0 (committed)

Files changed:
- `sdk/swift/Sources/RunAnywhere/Adapter/ModelCatalog.swift`
- `sdk/swift/Sources/RunAnywhere/Adapter/PublicAPI.swift`
- `sdk/swift/Sources/RunAnywhere/Adapter/StateSession.swift`
- `sdk/swift/Sources/RunAnywhere/Adapter/DiffusionSession.swift`
- `sdk/swift/Tests/RunAnywhereTests/APICompatibilityTests.swift`

### Wave 1 (committed)

New: `sdk/swift/Sources/RunAnywhere/Platform/{AudioCaptureManager, AudioPlaybackManager, KeychainManager, DownloadService, SentryAdapter}.swift`.

### Wave 2d (committed)

New: `sdk/swift/Sources/Backends/FoundationModelsRuntime/{SystemFoundationModelsService, FoundationModelsRuntime}.swift`.
Package.swift: `RunAnywhereFoundationModels` product.
Adapter/Backends.swift: `FoundationModels.installer` hook.

### Wave 3a (committed)

New: `core/abi/ra_auth.{h,cpp}` + `core/tests/ra_auth_abi_test.cpp`.

### Wave 3b (committed)

Expanded: `core/abi/ra_telemetry.{h,cpp}` + `core/tests/ra_telemetry_abi_test.cpp`.

### Wave 3d (committed)

New: `core/abi/ra_model.{h,cpp}` + `core/tests/ra_model_abi_test.cpp`.
Expanded: `core/abi/ra_primitives.h` with `RA_FORMAT_*` additions + `ra_model_category_t`.

## Deferred engineering work

The remaining waves (2a, 2b, 2c, 2e, 3c, 3e, 4, 5, 6, 7, 8) require
substantial porting of legacy C++ / Swift / Kotlin / TS code
(~60k+ LoC) and external SDK dependencies. Each is self-contained under
its wave's directory (`engines/<name>/`, `sdk/kotlin/src/main/cpp/`,
`sdk/rn/`, etc). Recommendations in the Path-A plan apply as-is.

See the source plan for detailed file lists, estimated effort, and
parallelization windows.
