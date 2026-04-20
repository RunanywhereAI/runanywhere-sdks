# RunAnywhere v1 → v2 migration

The legacy `sdk/runanywhere-*` packages (v1) have been replaced by the v2
architecture (`core/` C++20 + `engines/` plugins + `sdk/{swift,kotlin,dart,ts,web}/`
thin frontends). This document summarises the mapping for developers who
wrote code against v1.

## Directory layout

| v1 (deleted)                          | v2 (now canonical)                 |
| ------------------------------------- | ---------------------------------- |
| `sdk/runanywhere-commons/`            | `core/` (+ `engines/`, `solutions/`) |
| `sdk/runanywhere-swift/`              | `sdk/swift/`                        |
| `sdk/runanywhere-kotlin/`             | `sdk/kotlin/`                       |
| `sdk/runanywhere-flutter/`            | `sdk/dart/`                         |
| `sdk/runanywhere-react-native/`       | `sdk/ts/` (+ future `sdk/rn/`)      |
| `sdk/runanywhere-web/`                | `sdk/web/`                          |

The public API shape (method names, argument types) is preserved — only
the dependency paths change.

## C ABI mapping: `rac_*` → `ra_*`

Every legacy `rac_*` symbol now has a `ra_*` equivalent in `core/abi/`.
Notable mappings:

### Core

| v1 `rac_*` | v2 `ra_*` | Header |
|---|---|---|
| `rac_init` / `rac_shutdown` | `ra_init` / `ra_shutdown` | `ra_core_init.h` |
| `rac_state_initialize` | `ra_state_initialize` | `ra_state.h` |
| `rac_logger_*` | `ra_logger_*` | `ra_core_init.h` |

### Plugins & sessions

| v1 | v2 |
|---|---|
| `rac_llm_*` | `ra_llm_*` on `ra_engine_vtable_t.llm_*` slots |
| `rac_stt_*` | `ra_stt_*` |
| `rac_tts_*` | `ra_tts_*` |
| `rac_vad_*` | `ra_vad_*` |
| `rac_wakeword_*` | `ra_ww_*` |
| `rac_embed_*` | `ra_embed_*` |
| `rac_vlm_*` | `ra_vlm_*` (header: `ra_vlm.h`) |
| `rac_diffusion_*` | `ra_diffusion_*` (header: `ra_diffusion.h`) |

### Feature modules

| v1 | v2 |
|---|---|
| `rac_tool_*` | `ra_tool_*` (header: `ra_tool.h`) |
| `rac_structured_*` | `ra_structured_*` (header: `ra_structured.h`) |
| `rac_rag_*` | `ra_rag_*` (header: `ra_rag.h`, planned) |
| `rac_auth_*` | `ra_auth_*` (header: `ra_auth.h`) |
| `rac_telemetry_*` | `ra_telemetry_*` (header: `ra_telemetry.h`) |
| `rac_download_*` | `ra_download_*` (header: `ra_download.h`) |
| `rac_file_*` | `ra_file_*` (header: `ra_file.h`) |
| `rac_storage_*` | `ra_storage_*` (header: `ra_storage.h`) |
| `rac_extract_*` | `ra_extract_*` (header: `ra_extract.h`) |
| `rac_device_*` | `ra_device_*` (header: `ra_device.h`) |
| `rac_event_*` | `ra_event_*` (header: `ra_event.h`) |
| `rac_http_*` | `ra_http_*` (header: `ra_http.h`) |
| `rac_platform_llm_*` | `ra_platform_llm_*` (header: `ra_platform_llm.h`) |
| `rac_benchmark_*` | `ra_benchmark_*` (header: `ra_benchmark.h`) |
| `rac_image_*` | `ra_image_*` (header: `ra_image.h`) |
| `rac_model_*` | `ra_model_*` (header: `ra_model.h`) |
| `rac_server_*` | `ra_server_*` (header: `ra_server.h`) |

### Types

| v1 | v2 |
|---|---|
| `rac_status_t` | `ra_status_t` |
| `rac_model_format_t` | `ra_model_format_t` (aliases: `RA_MODEL_FORMAT_*`) |
| `rac_model_category_t` | `ra_model_category_t` (new, no v1 counterpart) |
| `rac_runtime_id_t` | `ra_runtime_id_t` |
| `rac_primitive_id_t` | `ra_primitive_id_t` |
| `rac_platform_adapter_t` | `ra_platform_adapter_t` |

## Swift SDK

The `RunAnywhere.*` top-level API is preserved across all sample-app call
sites. Notable internal changes:

- `RACommonsCore.xcframework` replaces the v1 `RACommons.xcframework`.
  The Swift module is `CRACommonsCore`.
- `sdk/swift/Package.swift` now exposes `RunAnywhere`, plus
  `RunAnywhereLlamaCPP`, `RunAnywhereONNX`, `RunAnywhereWhisperKit`,
  `RunAnywhereMetalRT`, `RunAnywhereGenie`, and
  `RunAnywhereFoundationModels` products.
- `sdk/swift/Sources/RunAnywhere/Platform/` hosts ported services:
  `AudioCaptureManager`, `AudioPlaybackManager`, `KeychainManager`,
  `DownloadService`, `SentryAdapter`.

## Kotlin SDK

- Single Gradle project at `sdk/kotlin/` replaces the v1 multi-module
  `sdk/runanywhere-kotlin/`.
- JNI surface lives in `sdk/kotlin/src/main/cpp/` (condensed
  `jni_all.cpp` pending — see `docs/restoration_progress.md` Wave 5).

## Dart / Flutter

- `sdk/dart/` is the single Dart package. Federated split into
  `sdk/dart/packages/runanywhere{,_llamacpp,_onnx,_genie}` is pending
  (Wave 7).

## TypeScript / React Native

- `sdk/ts/` hosts the core TS adapter. React-Native Nitro / JSI bridge
  lives under `sdk/rn/` (not yet created — Wave 6).

## Web / WASM

- `sdk/web/` hosts the Web adapter. Per-backend WASM bundles
  (`scripts/build-core-wasm.sh`) pending (Wave 8).

## Removed external dependencies

The new core drops these v1 runtime deps (handled by platform adapters now):

- `Alamofire` → replaced by `DownloadService.swift` (URLSessionDownloadDelegate).
- `swift-crypto` → `CommonCrypto` via the platform adapter.
- `protobuf` runtime → struct-based C ABI (no wire serialisation inside core).

Opt-in SDK targets can still pull external deps:
- `RunAnywhereSentry` optional target pulls `Sentry` SPM package when linked.
- `RunAnywhereWhisperKit` pulls `WhisperKit` when linked (Wave 2b).

## CI / CD

The legacy `release.yml`, `pr-build.yml`, and `auto-tag.yml` GitHub
workflows were removed — they only built the deleted `sdk/legacy/`
artifacts. The v2 workflows (`v2-core.yml`, `v2-release.yml`,
`secret-scan.yml`) remain.

## Further reading

- `docs/restoration_progress.md` — per-wave status tracker
- `/Users/sanchitmonga/.cursor/plans/path_a_restore_parity_b9043b08.plan.md`
  — the full restoration plan
