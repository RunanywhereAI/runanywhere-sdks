# v3.1 Phase 6 — CMakeLists normalization (GAP 06)

_Status: the rac_add_engine_plugin() macro already exists in
`cmake/plugins.cmake` (landed in GAP 07 Phase 4). Phase 6 of v3.1
audits which engines use it vs hand-rolled CMake and documents the
migration path for the remaining engines._

## Canonical macro

The canonical engine-plugin macro is `rac_add_engine_plugin()` defined
at [cmake/plugins.cmake](../cmake/plugins.cmake). It handles:

- STATIC vs SHARED library branching via `RAC_STATIC_PLUGINS`
- Consistent target naming (`runanywhere_<name>` for SHARED,
  linked into `rac_commons` for STATIC)
- Include dirs, compile definitions, link libraries
- `RUNTIMES` + `FORMATS` metadata recorded as CMake GLOBAL properties
  for tooling
- Companion `rac_force_load()` helper for the host binary to keep
  static-archive symbols alive

## Usage pattern

```cmake
include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

rac_add_engine_plugin(llamacpp
    SOURCES
        llamacpp_backend.cpp
        rac_llm_llamacpp.cpp
        rac_plugin_entry_llamacpp.cpp
    LINK_LIBRARIES llama common
    RUNTIMES CPU METAL CUDA
    FORMATS GGUF GGML BIN
)
```

## Current adoption state (v3.1)

### Engines using the macro

| Engine | CMakeLists LOC | Status |
|---|---|---|
| `engines/llamacpp/` | 185 | Uses macro (LLM + VLM) |
| `engines/genie/` | 18 | Uses macro (stub) |
| `engines/sherpa/` | 28 | Uses macro (stub) |
| `engines/diffusion-coreml/` | 24 | Uses macro (stub) |

### Engines using hand-rolled CMake

| Engine | CMakeLists LOC | Reason retained |
|---|---|---|
| `engines/onnx/` | 210+ | Heavy `find_package(ONNX)` + iOS/Android platform branches that don't fit the macro's simple SOURCES/LINK_LIBS shape. |
| `engines/whispercpp/` | 208 | FetchContent for whisper.cpp + ggml + platform-specific GGML_* options + JNI bridge sub-target. |
| `engines/whisperkit_coreml/` | ~100 | SwiftPM integration via `swift build` external step. |
| `engines/metalrt/` | ~130 | Apple-only; Objective-C++ sources; Metal framework links. |

## Migration path

The 4 hand-rolled engines can migrate incrementally:

1. **Keep engine-specific prologue** (FetchContent, find_package,
   platform option setup) as-is ABOVE the macro call.
2. **Replace the `add_library()` + `target_include_directories()` +
   `target_compile_features()` + `target_link_libraries()` block**
   with a single `rac_add_engine_plugin()` call.
3. **Keep engine-specific epilogue** (JNI sub-targets, install rules,
   extra summary `message()` calls) BELOW.

This converges the middle ~40 LOC per engine into ~8-10 LOC.
Platform-specific link libs can still go via
`target_link_libraries(rac_backend_<name> PUBLIC "-framework Foo")`
after the macro call.

## Why not mass-migrate now?

Each hand-rolled engine has subtle per-platform build options
(iOS 16KB page alignment linker flags, Android NEON intrinsics,
Metal embedding, CUDA detection) that need careful re-verification
after the refactor. Mass-migrating risks silently breaking a platform
build that only surfaces in CI. v3.1 ships the normalization
infrastructure + stub-engine adoption as the safe first wave;
per-engine migrations land as their own PRs with platform build
matrix runs.

## Phase 6 deliverable

- Macro is canonical at `cmake/plugins.cmake` (unchanged from GAP 07).
- 4/9 engines actively use it (llamacpp + 3 stubs).
- This document specifies the migration path for the remaining 4.
- GAP 06 criterion "define rac_add_engine_plugin() + document
  adoption" closed.

## Remaining work (tracked as post-v3.1)

- `engines/onnx/` migration (PR: "refactor(onnx): adopt
  rac_add_engine_plugin")
- `engines/whispercpp/` migration
- `engines/whisperkit_coreml/` migration
- `engines/metalrt/` migration

Each ~50-80 LOC net reduction; independently reviewable.
