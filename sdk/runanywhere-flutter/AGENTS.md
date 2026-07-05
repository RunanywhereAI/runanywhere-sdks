# RunAnywhere Flutter SDK

## Info

Melos-managed Dart workspace of 4 Flutter plugin packages that wrap the shared C++ core (`runanywhere-commons`) via hand-written Dart FFI — no platform channels for AI operations. Global rules: see repo-root AGENTS.md.

- `packages/runanywhere/` — core SDK: `RunAnywhere` static entry point, capability classes (`lib/public/capabilities/`), 33 `DartBridge` slices (`lib/native/dart_bridge_*.dart`), FFI bindings (`lib/core/native/rac_native.dart`), generated protos (`lib/generated/`, do not edit)
- `packages/runanywhere_llamacpp/` — llama.cpp backend (LLM + VLM, one vtable, single `LlamaCpp.register()`)
- `packages/runanywhere_onnx/` — ONNX Runtime + Sherpa backends (STT/TTS/VAD + embeddings) co-distributed to share `libonnxruntime`
- `packages/runanywhere_genie/` — Qualcomm Genie NPU LLM, Android/Snapdragon only, closed-source `.so` downloaded at build time

Key patterns (iOS Swift SDK is source of truth):
- Two-phase init: Phase 1 sync (lib load, platform adapter, `rac_sdk_init`); Phase 2 fire-and-forget async (auth, device, assignments).
- Streaming and event fan-out use `NativeCallable.listener` + broadcast `StreamController` (`dart:async`, never rxdart).
- HTTP transport is platform-injected: URLSession vtable (ObjC++ in `ios/Classes/`), OkHttp vtable via JNI (`android/`).
- Each package bundles its own `libc++_shared.so` — intentional (self-contained AARs); do not dedup. Consumers use `pickFirst`.
- iOS vendors static XCFrameworks (`RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendSherpa`); requires `use_frameworks! :linkage => :static` and `-all_load`.

## Build Info

```bash
# From sdk/runanywhere-flutter/
melos bootstrap        # pub get across the workspace
melos run analyze      # flutter analyze in all packages
melos run format
melos run test
melos run clean

# From repo root (dev entry point)
./run sdk flutter build          # pub get + analyze the core package
./run sdk flutter lint
./run sdk flutter clean

# Native binaries (repo root; rebuild after C++ commons changes)
./run sdk commons build-android      # scripts/build/android.sh — .so into jniLibs/
./run sdk commons build-ios          # scripts/build/ios-xcframework.sh (macOS only)

# Proto codegen (repo root) — regenerates lib/generated/
./run codegen dart                   # scripts/codegen/generate_dart.sh

# Release packaging / pub-publish dry-run validation
scripts/release/package-flutter.sh                       # from repo root
scripts/release/package-flutter.sh --natives-from PATH   # stage natives then validate
```

Requirements: Flutter 3.24+, Dart 3.5+, iOS 15.1+, Android minSdk 24, NDK per `sdk/runanywhere-commons/VERSIONS`.

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: Analyzer strict mode — `dead_code`/`unused_import`/etc. are errors; generated files under `lib/generated/` are excluded. Never hand-edit generated protos.
- 2026-07-05: FFI scheduling — keep blocking calls off worker isolates unless the C++ path is proven not to publish back through a Dart callback; model load must stay on the main isolate (SIGABRT otherwise).
- 2026-07-05: VLM stream callback C type returns `rac_bool_t` (LLM's is `void`); returning void truncates output to one token.
