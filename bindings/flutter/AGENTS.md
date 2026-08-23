# AGENTS.md — RunAnywhere Flutter SDK

Re-verified against source 2026-08-17; corrects drift from the 2026-07-12 pass (see
inline notes). Deeper reference: `docs/ARCHITECTURE.md` (data flow, extensibility,
trade-offs, native binary inventory — trust *this* file over it for exact counts, it
lags), `docs/Documentation.md` (public API reference, same caveat), `docs/DEVELOPMENT.md`
(platform setup, first build, troubleshooting).

## Repository Structure

Melos-managed monorepo, 5 Flutter plugin packages wrapping the shared C++ core
(`runanywhere-commons` / `RACommons`) via Dart FFI — no platform channels for AI, all
inference is direct FFI.

```
bindings/flutter/
├── pubspec.yaml                # Dart workspace + Melos config
├── analysis_options.yaml       # Strict lint rules
├── scripts/package-sdk.sh      # Packaging/validation script
├── docs/                       # ARCHITECTURE.md, Documentation.md, DEVELOPMENT.md
└── packages/
    ├── runanywhere/            # Core SDK (FFI bridge, public API, events, models)
    ├── runanywhere_llamacpp/   # LlamaCpp backend (LLM + VLM)
    ├── runanywhere_mlx/        # Apple MLX backend (LLM + VLM + embeddings + STT + TTS, physical iOS)
    ├── runanywhere_onnx/       # Sherpa/ONNX Runtime backend (STT + TTS + VAD)
    └── runanywhere_qhexrt/     # QHexRT Qualcomm Hexagon NPU backend (Android-only)
```

All four backend packages depend on `runanywhere ^0.20.26`; the core package vendors
`RACommons`, each backend vendors its own XCFrameworks/`.so` files. Example app:
`bindings/flutter/example/` (setup/troubleshooting in `docs/DEVELOPMENT.md`;
`example/scripts/verify.sh` is the clean-clone build gate).

Toolchain: Flutter 3.44.6 · Dart `>=3.12.0 <4.0.0` · iOS 17.5+ · Android minSdk 24 /
compile+target SDK 36 · NDK **28.2.13676358** (`racFlutterNdkVersion` override) · AGP
9.0.1 / Gradle 9.1.0 · Xcode/Swift 26+ / 6.2.

## Development Commands

```bash
# From bindings/flutter/
melos bootstrap        # flutter pub get across the Dart workspace
melos run analyze      # flutter analyze --no-pub in all 5 packages
melos run format       # dart format in all 5 packages
melos run test         # flutter test in all 5 packages
melos run clean        # flutter clean in all 5 packages
melos version          # Bump versions + generate workspace CHANGELOG

./scripts/package-sdk.sh                          # pub publish --dry-run, all packages
./scripts/package-sdk.sh --natives-from PATH      # stage natives (xcframeworks + .so), then validate
./scripts/package-sdk.sh --include-private-qhexrt # requires --natives-from; stages private QHexRT natives too
```

Example-app commands (`flutter pub get`/`run`, `scripts/verify.sh`) are in
`docs/DEVELOPMENT.md`.

## Architecture

Flutter App → `RunAnywhere` static namespace (17 capability-namespace getters, see
below) → `lib/native/dart_bridge_*.dart` (38 FFI slices, one per C++ subsystem) →
`NativeFunctions`/`PlatformLoader` (cached lookups + `DynamicLibrary` load) → RACommons
C++ core (registries, events, router) → backend engine vtables (LlamaCpp, Sherpa/ONNX,
QHexRT). Full diagram + per-pattern rationale: `docs/ARCHITECTURE.md` §2.2, §4.

Gotchas not obvious from that diagram:

1. **FFI scheduling is gated on callback safety**, not just "is this slow." A blocking
   call may only move to a worker isolate when its C++ path cannot publish back through
   an isolate-local Dart callback, or when the callback is proven safe with
   `NativeCallable.listener`. SDK event fan-out and low-risk callbacks use
   `NativeCallable.listener` with broadcast `StreamController`s (`dart:async`, never
   rxdart — it is not a dependency); high-risk proto streams (LLM/VLM/STT/TTS/voice-agent)
   do NOT — see "Streaming Callbacks: Native-Port Helpers" below for why and how.
2. **Two-phase init, Phase 2 is genuinely fire-and-forget.** It's assigned to
   `_servicesInitFuture` without awaiting (Swift `Task.detached` parity). A prior
   implementation eagerly awaited despite a doc comment claiming otherwise — don't trust
   a doc comment on this over the call site.
3. **Secure storage vtable**: C++ calls Dart callbacks synchronously; Flutter delegates
   to native helpers (Keychain on Apple, Android Keystore AES-GCM + atomic no-backup
   ciphertext files). A callback returns success only after the mutation completes.
4. **No `ffigen`.** `lib/core/native/rac_native.dart` + `lib/native/native_functions.dart`
   (cached lookup registry) hand-define every C ABI binding.
5. **Native library loading** differs per platform: iOS `DynamicLibrary.process()`
   resolves symbols in the main binary (static `RACommons.xcframework`, requires
   `use_frameworks! :linkage => :static` + `-all_load`/`DEAD_CODE_STRIPPING=NO`); Android
   `DynamicLibrary.open('librac_commons.so')` with `librunanywhere_jni.so` fallback;
   macOS tries `process()` → `executable()` → an explicit dylib path for unit tests.

## Core Package (`packages/runanywhere/`)

### Public API Surface

`RunAnywhere` (`lib/public/runanywhere.dart`) is the entry point and the only source of
truth for the current namespace set — treat any other list, including this one, as a
snapshot. It currently exposes **17 capability-namespace getters**: 15 "v3 spec"
namespaces (`llm`, `vlm`, `stt`, `tts`, `vad`, `embeddings`, `rerank`, `images`,
`diarization`, `segmentation`, `voice`, `rag`, `models`, `lora`, `cua`) plus 2
"beyond v3 spec" namespaces kept for shipped features the spec doesn't cover yet
(`solutions`, `hybrid`). Most v3 namespaces are stateless `const <Name>Api` classes under
`lib/public/api/namespaces/`; `cua`/`solutions`/`hybrid` are `RunAnywhere<Name>`
singletons (`.shared`) under the older `lib/public/capabilities/` layout.

**Retired as top-level accessors — don't assume these exist:** `downloads`, `tools`,
`modelLifecycle`, `pluginLoader`, `diffusion`, `hardware`. Tool calling folded into
`llm`; `images` replaced `diffusion`; `models` absorbs registry/lifecycle/download
concerns.

### Source Layout

```
packages/runanywhere/lib/
├── runanywhere.dart              # Barrel (~150 re-exports)
├── runanywhere_protos.dart       # Proto re-export hub
├── core/native/rac_native.dart   # Hand-written FFI bindings (~2.1K LOC)
├── features/
│   ├── stt/services/audio_capture_manager.dart   # SDK-owned mic capture (PCM16 via package:record)
│   └── tts/services/audio_playback_manager.dart  # SDK-owned speak() playback via audioplayers
├── foundation/                    # constants/, errors/ (sdk_exception.dart), logging/
├── generated/                    # runtime proto files (DO NOT EDIT)
├── native/                       # dart_bridge_*.dart slices + native_functions + platform_loader + types/ + type_conversions/
└── public/
    ├── runanywhere.dart          # RunAnywhere static entry point
    ├── api/                      # namespaces/ (<Name>Api classes) + types/ + internal/ — the newer v3-spec layer
    ├── capabilities/             # older RunAnywhere<Name> singleton classes (cua, solutions, hybrid + internals)
    └── events/                   # event_bus.dart (dart:async)
```

**Not present (do not search for):** no top-level `lib/capabilities/`, no
`lib/infrastructure/`, no `dart_bridge_hardware.dart`, no `dart_bridge_llm_streaming.dart`,
no `native_backend.dart`.

`lib/native/` has 41 `.dart` files: 38 one-per-C++-subsystem `dart_bridge_*.dart` slices,
the `dart_bridge.dart` coordinator, and 2 supporting modules (`native_functions.dart`,
`platform_loader.dart`). The slice set has grown past the historical "33 slices" figure —
`diarization`, `segmentation`, `rerank`, `secure_storage`, `hf_auth`, and `cua` are newer
additions matching ABI v9's primitive set; `ls lib/native/` for the current list rather
than trusting an enumeration here.

### iOS Native Layer (`packages/runanywhere/ios/`)

A local SwiftPM package (`ios/runanywhere/Package.swift`, tools-version 6.2) — **not** a
flat CocoaPods `Classes/` layout (an older revision of this doc described one; it no
longer exists).

| Path | Role |
|---|---|
| `Package.swift` | 3 targets: binary `RACommons`, ObjC++ `runanywhere_native`, Swift `runanywhere` (the Flutter plugin) |
| `Sources/runanywhere/RunAnywherePlugin.swift` | Flutter plugin entry; calls `URLSessionHttpTransport.register()` before Dart FFI fires HTTP |
| `Sources/runanywhere/URLSessionHttpTransport.swift` | Swift façade; `@_silgen_name("ra_flutter_register_urlsession_transport")`, idempotent |
| `Sources/runanywhere_native/URLSessionHttpTransport.mm` | ObjC++ vtable wiring; owns static `rac_http_transport_ops_t` |
| `Sources/runanywhere_native/*StreamNativePort.mm` | 6 native-port stream-callback helpers — see `docs/ARCHITECTURE.md` §10.3 |
| `Sources/runanywhere_native/SecureStorageBridge.mm` | Keychain bridge for the secure-storage vtable |
| `Frameworks/RACommons.xcframework` | Vendored static archive, 3 slices: `ios-arm64`, `ios-arm64-simulator`, `macos-arm64` |
| `runanywhere.podspec` | iOS 17.5+; `-lc++ -larchive -lbz2 -lz -ObjC -all_load -Wl,-export_dynamic`; `DEAD_CODE_STRIPPING=NO` |

### Android Plumbing (`packages/runanywhere/android/`)

| File | Role |
|---|---|
| `src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt` | Flutter plugin; static `init {}` registers OkHttp transport via JNI before FFI HTTP fires |
| `src/main/kotlin/com/runanywhere/sdk/native/bridge/RunAnywhereBridge.kt` | JNI shim; `System.loadLibrary("runanywhere_jni")` |
| `src/main/kotlin/com/runanywhere/sdk/httptransport/OkHttpHttpTransport.kt` | OkHttp 4.12 vtable backing `rac_http_request_send`/`_stream`/`_resume`; 30s/24h/60s timeouts, 32 KB chunks, range-honored 206, in-flight registry for `cancelAllStreams()` |
| `src/main/cpp/NativePortHelpers.cpp` | Builds `librunanywhere_flutter_helpers.so` — see `docs/ARCHITECTURE.md` §10.3 |
| `build.gradle` | AGP 9, Java 17, NDK `28.2.13676358`; ABIs: arm64-v8a, armeabi-v7a, x86_64 |
| `binary_config.gradle` | `useLocalNatives` toggle + GitHub-release URL + checksum |

## Backend Packages

Full native-binary inventory (which `.so`/`.xcframework` each package ships) is in
`docs/ARCHITECTURE.md` §13 — don't re-derive or duplicate it here.

- **`runanywhere_llamacpp`** (LLM + VLM, `.gguf`): `LlamaCpp.register()` → FFI
  `rac_backend_llamacpp_register()` + `..._vlm_register()`. One call fills both
  `llm_ops` and `vlm_ops` on a single vtable — there is no separate `registerVlm()`.
- **`runanywhere_onnx`** (STT + TTS + VAD): `await Onnx.register()` registers both the
  generic ONNX engine and the Sherpa STT/TTS/VAD engine — two engines in one package
  because both share the underlying ONNX Runtime and splitting them would double-ship
  it. Custom downloader `OnnxDownloadStrategy` handles `.tar.bz2` via
  `rac_extract_archive_native`.
- **`runanywhere_mlx`** (Apple MLX, physical iOS only): `await MLX.register()` → FFI
  `ra_mlx_register_runtime()`. Canonical implementation is the Swift `RunAnywhereMLX`
  product, no inference logic in Dart. CocoaPods-only (Hub/Crypto need app-root bundles
  Flutter SwiftPM can't provide). Simulator slices build/link/start only — registration
  reports unavailable there. Android: unsupported, not in the manifest.
- **`runanywhere_qhexrt`** (Qualcomm Hexagon NPU, Android-only): `await
  QHexRT.register()` → FFI `rac_backend_qhexrt_register()`, registers only on supported
  Snapdragon Hexagon NPUs. Private backend — natives are staged separately and are not
  present in a checkout.

**`libc++_shared.so` duplication across all four Android packages is intentional — do
not dedup at the package level.** Each Flutter plugin must be a self-contained AAR (a
consumer may add only `runanywhere` + `runanywhere_llamacpp`, and every transitive
closure needs the lib); Gradle `packaging { jniLibs.pickFirsts += "**/libc++_shared.so"
}` resolves the merge at APK time. Plugin packages can't transitively depend on another
plugin's `jniLibs`, so factoring this into a shared sub-package would break standalone
consumption.

## Generated Code

`packages/runanywhere/lib/generated/` holds **~79 files** across **~39 proto schemas**
(2 files each: `.pb.dart`, `.pbenum.dart`), generated by `protoc` + `protoc-gen-dart`
from `idl/*.proto` — up from an older 58-file/29-schema count as `diarization`,
`segmentation`, `rerank`, `cua`, and others landed alongside the ABI v9 primitive set.
Excluded from the analyzer; do not hand-edit.
`*.pbjson.dart`/`*.pbserver.dart`/`*.pbgrpc.dart` are stripped by
`idl/codegen/generate_dart.sh` — Flutter doesn't use descriptor/server/gRPC stubs.

## Lint Rules

Extends `package:flutter_lints/flutter.yaml` with strict-casts/strict-inference/
strict-raw-types, error-level `dead_code`/`unused_import`/`unused_local_variable`/
`unused_element`/`unused_field`, warning-level `avoid_dynamic_calls`/`avoid_print`/
`prefer_const_constructors`/`prefer_final_locals` (full rule set in
`analysis_options.yaml`). Excludes `**/*.g.dart`, `**/*.freezed.dart`,
`**/lib/generated/**`.

## Versions

| Package / Artifact | Version |
|---|---|
| `runanywhere`, `runanywhere_llamacpp`, `runanywhere_mlx`, `runanywhere_onnx`, `runanywhere_qhexrt` | 0.20.26 (all 5, confirmed identical) |
| `RACommons` native | 0.1.6 |
| llama.cpp engine | runanywhere-b10453.4 |
| ONNX Runtime | 1.28.0 |
| Canonical version source | `core/VERSION` |

## Streaming Callbacks: Native-Port Helpers

**Never read borrowed C callback bytes asynchronously from Dart.** High-risk streams
(LLM/VLM/STT/TTS, voice-agent) copy bytes synchronously inside the native callback via a
plugin-owned native-port helper and post owned `Uint8List`s to a Dart `ReceivePort`,
because `NativeCallable.isolateLocal` is only safe on the registering isolate thread and
`NativeCallable.listener` runs too late on the event loop for buffers commons may reuse
immediately. `rac_native.dart` prefers the optional `ra_flutter_*_native_port` symbols
when present, falling back to same-thread `isolateLocal` only where documented.

**When adding a new stream callback**, follow the same pattern rather than reading
borrowed bytes from Dart directly: add a native-port helper at the platform SDK layer,
copy bytes before returning to commons, expose it as an optional FFI symbol in
`rac_native.dart`, keep example apps thin. Full rationale, file map, and the Android
warm-load sequence: `docs/ARCHITECTURE.md` §10.3.
