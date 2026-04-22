# Engine Plugin Authoring Guide

_Closes GAP 02 Phase 10. The definitive "how do I add a new engine to RunAnywhere?" reference._

Use this guide when you want RunAnywhere to route a new primitive (LLM, STT, TTS, VAD, embedding, reranker, VLM, diffusion) through your engine. After Phase 10 of
[`v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md`](../v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md) there are **two** registration paths. Most authors should pick the unified path; the legacy path only stays around for binary-compatibility with releases ≤ v0.19.

## Which path should I pick?

```
Are you adding a brand-new engine?
│
├─ Yes ────────────────────────────────────── Unified path (this guide).
│
└─ No (you're modifying an existing backend)
   │
   ├─ Add a NEW primitive to an existing backend?
   │     (e.g. add `embed` to ONNX)
   │     ────────────────────────────────────── Edit the existing
   │                                           rac_plugin_entry_<name>.cpp.
   │
   ├─ Fix a bug in existing ops?
   │     ────────────────────────────────────── Edit the existing
   │                                           rac_backend_<name>_register.cpp.
   │                                           Both registration paths share
   │                                           the same ops-struct; fixing
   │                                           there fixes both.
   │
   └─ Deprecate an engine?
         ─────────────────────────────────────── Add `on_unload` hook in the
                                                rac_plugin_entry_<name>.cpp
                                                for cleanup, then drop the
                                                rac_plugin_register() call at
                                                consumer sites.
```

## Unified path — 4 steps

### 1. Fill in a `rac_engine_vtable_t`

Reserve a short stable name (e.g. `mlx`). Put the vtable in a new
`src/backends/<name>/rac_plugin_entry_<name>.cpp`:

```cpp
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/llm/rac_llm_service.h"

extern "C" {
extern const rac_llm_service_ops_t g_mlx_ops;  // <- your ops struct

static const rac_engine_vtable_t g_mlx_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "mlx",
        .display_name     = "Apple MLX",
        .engine_version   = "0.1.0",
        .priority         = 95,   // higher wins for same primitive
        .capability_flags = 0,
        .reserved_0       = 0,
        .reserved_1       = 0,
    },
    /* capability_check */ [](){
        #if defined(__APPLE__)
        return RAC_SUCCESS;
        #else
        return RAC_ERROR_CAPABILITY_UNSUPPORTED;  // silent reject
        #endif
    },
    /* on_unload */ nullptr,

    /* llm_ops       */ &g_mlx_ops,
    /* other slots   */ nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,

    /* reserved_slot_0..9 */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(mlx) {
    return &g_mlx_engine_vtable;
}
}  // extern "C"
```

Rules:
  - `metadata.abi_version` MUST equal `RAC_PLUGIN_API_VERSION` (currently 1).
  - `metadata.name` MUST be unique across all registered engines.
  - Fill exactly the primitive slots you serve; leave everything else NULL.
  - `capability_check` returning non-zero rejects the plugin silently (no error log).

### 2. Declare the entry in a public header

`sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry_mlx.h`:

```c
#ifndef RAC_PLUGIN_ENTRY_MLX_H
#define RAC_PLUGIN_ENTRY_MLX_H
#include "rac/plugin/rac_plugin_entry.h"
#ifdef __cplusplus
extern "C" {
#endif
RAC_PLUGIN_ENTRY_DECL(mlx);
#ifdef __cplusplus
}
#endif
#endif
```

The install rule already picks it up via `install(DIRECTORY include/)`.

### 3. Hook CMake

In `sdk/runanywhere-commons/src/backends/mlx/CMakeLists.txt`:

```cmake
set(MLX_BACKEND_SOURCES
    rac_llm_mlx.cpp
    rac_backend_mlx_register.cpp    # optional — legacy path
    rac_plugin_entry_mlx.cpp        # unified path
)
```

### 4. Register at startup

Pick the simplest of:

```cpp
// C++ app or library: uses static-init.
#include "rac/plugin/rac_plugin_entry_mlx.h"
RAC_STATIC_PLUGIN_REGISTER(mlx);
```

```c
// C app or explicit ordering: call manually.
#include "rac/plugin/rac_plugin_entry_mlx.h"
int main(void) {
    rac_plugin_register(rac_plugin_entry_mlx());
    // ... your code ...
}
```

```c
// Dynamic plugin (dlopen): load then call by symbol name.
void* h = dlopen("libmlx.so", RTLD_NOW);
rac_plugin_entry_fn entry = (rac_plugin_entry_fn)dlsym(h, "rac_plugin_entry_mlx");
rac_plugin_register(entry());
```

## Testing your plugin

```cpp
// test_plugin_entry_mlx.cpp
#include "rac/plugin/rac_plugin_entry_mlx.h"
int main() {
    const rac_engine_vtable_t* vt = rac_plugin_entry_mlx();
    assert(vt->metadata.abi_version == RAC_PLUGIN_API_VERSION);
    assert(vt->llm_ops != nullptr);
    rac_plugin_register(vt);
    assert(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == vt);
    rac_plugin_unregister("mlx");
}
```

Hook it into `sdk/runanywhere-commons/tests/CMakeLists.txt` following the
pattern established by `test_plugin_entry_llamacpp` and
`test_plugin_entry_onnx` in Phase 10.

## Priority ladder (as of GAP 02 Phase 9)

| Priority | Name              | Primitives served                  | Platforms  |
|----------|-------------------|-----------------------------------|------------|
| 120      | metalrt            | LLM + STT + TTS + VLM             | Apple      |
| 110      | whisperkit_coreml  | STT                               | Apple      |
| 100      | llamacpp           | LLM  (vlm via llamacpp_vlm)       | All        |
| 100      | llamacpp_vlm       | VLM                               | All        |
| 90       | whispercpp         | STT                               | All        |
| 80       | onnx               | STT + TTS + VAD                   | All        |
| 95       | mlx (example)      | LLM                               | Apple only |

Pick your priority within the existing range. Reserve 0–40 for
experimental / CPU fallback engines, 40–80 for standard CPU
implementations, 80–110 for optimized / hardware-accelerated
implementations, 110+ for Apple-specific hardware paths.

## Bumping the plugin API version

Bump `RAC_PLUGIN_API_VERSION` in
`sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h` when any of:

  - `rac_engine_vtable_t` field layout changes (reserved slot promotion, new primitive).
  - A new primitive lands in `rac_primitive.h`.
  - Any per-domain ops struct (`rac_llm_service_ops_t`, …) grows or shrinks.

Old plugins loaded against a newer host will fail the ABI check and be
rejected with `RAC_ERROR_ABI_VERSION_MISMATCH` — a safe outcome. Do **not**
bump for additive metadata fields (new `capability_flags` bits).

## Relationship to the legacy path

Every existing backend (`llamacpp`, `onnx`, `whispercpp`, `whisperkit_coreml`,
`metalrt`) now exposes BOTH:

  - `rac_backend_<name>_register()` — registers via the legacy per-domain
    `rac_service_register_provider()` path used by the C ABI + Swift /
    Kotlin / Dart bridges pre-GAP-02.
  - `rac_plugin_entry_<name>()` — returns a `const rac_engine_vtable_t*` for
    the unified registry.

Both paths share the same ops-struct (e.g. `g_llamacpp_ops`); a bug fix in
that struct shows up in both registries automatically.

## Migrating off the legacy service registry (GAP 11 Phase 29)

The legacy `rac_service_*` API in `rac/core/rac_core.h`
(`rac_service_register_provider`, `rac_service_unregister_provider`,
`rac_service_create`, `rac_service_list_providers`) is **deprecated as of
GAP 11** and will be removed in v3 (`RAC_PLUGIN_API_VERSION 3u`). Both
the compile-time `[[deprecated]]` attribute and a runtime one-time
`RAC_LOG_WARNING` from `service_registry.cpp` flag every call.

### Migration map

| Legacy call                                | Replacement                                                |
|--------------------------------------------|------------------------------------------------------------|
| `rac_service_register_provider(provider)`  | `rac_plugin_registry_register(vtable)` (`rac_plugin_entry.h`) |
| `rac_service_unregister_provider(name)`    | `rac_plugin_registry_unregister(name)`                     |
| `rac_service_create(cap, req, &handle)`    | `rac_plugin_route(&request, &result)` (`rac/router/rac_route.h`) |
| `rac_service_list_providers(cap, ...)`     | `rac_registry_list_plugins(...)` (`rac/plugin/rac_plugin_loader.h`) |

The unified path is **strictly more capable**: per-primitive metadata,
runtime/format hints for the GAP 04 router, ABI version validation, and
dynamic loading via the GAP 03 `rac_registry_load_plugin()` API.

### Removal timing

- **v2 (GAP 11 Phase 29, this commit):** `[[deprecated]]` warning +
  one-time runtime log.
- **v2 (GAP 11 Phase 30):** every call site repointed to the unified
  API; SDKs verified to NOT call the legacy entry points.
- **v3 (GAP 11 Phase 31):** `git rm sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp`
  + `RAC_PLUGIN_API_VERSION` bumped to `3u`.
