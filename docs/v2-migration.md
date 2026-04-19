# RunAnywhere v1 → v2 migration

This document describes the coexistence strategy for v1 (existing
`sdk/runanywhere-*`) and v2 (`core/`, `engines/`, `solutions/`, `frontends/`)
during the rewrite. **v1 keeps shipping unchanged** until the Phase 1 gate
lands; v2 is additive.

## Layout

| v1 (current, unchanged)       | v2 (new, bootstrapped in this PR)     |
| ----------------------------- | ------------------------------------- |
| `sdk/runanywhere-commons/`    | `core/` (+ `engines/`, `solutions/`)  |
| `sdk/runanywhere-swift/`      | `frontends/swift/`                    |
| `sdk/runanywhere-kotlin/`     | `frontends/kotlin/`                   |
| `sdk/runanywhere-flutter/`    | `frontends/dart/`                     |
| `sdk/runanywhere-react-native/` | `frontends/ts/`                     |
| `sdk/runanywhere-web/`        | `frontends/web/`                      |

## What this PR includes

The bootstrap PR contains the **complete v2 skeleton** with every
integration point defined:

- ✅ proto3 IDL (`idl/voice_events.proto`, `pipeline.proto`, `solutions.proto`)
- ✅ C ABI (`core/abi/ra_primitives.h`, `ra_pipeline.h`, `ra_plugin.h`)
- ✅ L4 graph primitives (`RingBuffer`, `MemoryPool`, `StreamEdge`,
  `CancelToken`, `PipelineNode`, `GraphScheduler`)
- ✅ L2 plugin system (`PluginRegistry`, `PluginLoader<VTABLE>`,
  static iOS / dlopen Android dual-path)
- ✅ L3 engine router + `HardwareProfile`
- ✅ Concrete VoiceAgent pipeline with transactional barge-in cancellation
- ✅ L5 solutions: VoiceAgent + RAG (BM25 + HybridRetriever ported from
  FastVoice)
- ✅ L2 engine plugins: llamacpp, sherpa, wakeword (vtable structure +
  stub implementations that return a clear error instead of silently lying)
- ✅ L6 frontends for all 5 languages: Swift (SwiftPM), Kotlin (Gradle),
  Dart (pub), TS / RN (npm), Web (npm + WASM build)
- ✅ CMake build (presets for macOS / Linux / iOS / Android / WASM) with
  ASan, UBSan, and TSan wired
- ✅ vcpkg dependency manifest
- ✅ CI workflow (`.github/workflows/v2-core.yml`) that builds C++ core
  + runs every frontend's native lint/test on every PR
- ✅ codegen scripts for all 5 languages (`idl/codegen/generate_*.sh`)
- ✅ unit tests for ring buffer, memory pool, cancel token, stream edge,
  sentence detector, text sanitizer, plugin registry, engine router
- ✅ per-primitive benchmark harness (`tools/benchmark/ra_bench`)
- ✅ pipeline validator stub (`tools/pipeline-validator/ra_validate`)

## What this PR does NOT include (next PRs)

- The actual llama.cpp / sherpa-onnx / sherpa-wakeword C integrations —
  the plugin vtables are wired but the implementations return
  `RA_ERR_RUNTIME_UNAVAILABLE`. This is intentional: the engine work is
  large enough to deserve its own PR per engine.
- JNI/JSI/FFI bridges from L6 frontends to the C ABI. The frontends
  currently emit a clear `backendUnavailable` error when you call
  `session.run()`; this is the correct path while the bridges are landed
  one platform at a time.
- Proto codegen output (`frontends/*/Generated/`, `frontends/*/generated/`
  directories). These are populated on the first run of
  `idl/codegen/generate_*.sh` and committed. CI verifies they are in sync.
- Port of the existing v1 examples to use the v2 adapters. v1 examples
  continue to work against the v1 SDKs unchanged.

## Migration order

Per `thoughts/shared/plans/v2_rearchitecture/MASTER_PLAN.md`:

1. **Phase 0** (this PR + next few): C++ core + VoiceAgent pipeline with
   real llama.cpp/sherpa integrations; macOS/Linux benchmarks.
2. **Phase 1**: Swift frontend + iOS XCFramework.
3. **Phase 2**: Kotlin frontend + Android + RAG solution shipping.
4. **Phase 3**: Dart, TS/RN, Web frontends + L1 runtimes (ORT, ExecuTorch,
   MLX, CoreML) + production CI.

The hard go/no-go gate for each phase is in the MASTER_PLAN. Do not
advance phases without passing the gate.

## Building v1 and v2 together

v2 adds files to new directories and does not modify any v1 path. Existing
build flows are untouched:

```bash
# v1 Kotlin (unchanged)
cd sdk/runanywhere-kotlin && ./scripts/sdk.sh build

# v1 Swift (unchanged)
cd sdk/runanywhere-swift && swift build

# v2 C++ core (new)
cmake --preset macos-debug && cmake --build --preset macos-debug

# v2 Swift (new, independent package)
cd frontends/swift && swift build

# v2 Kotlin (new)
cd frontends/kotlin && gradle build
```

## For reviewers

The PR is intentionally large to establish the complete skeleton in one
commit rather than land it piecemeal. Review priorities:

1. `core/abi/*.h` — these are the stable contract every frontend depends on.
2. `core/voice_pipeline/voice_pipeline.cpp` — the barge-in transactional
   boundary is the most subtle piece of the entire rewrite.
3. `idl/*.proto` — any wire-format concerns should be flagged now.
4. `.github/workflows/v2-core.yml` — the CI matrix.
5. `CMakeLists.txt` + `cmake/*.cmake` — the build system.

Everything else (unit tests, frontend adapters, scripts) is scaffolding
that gets filled in over the subsequent phases.
