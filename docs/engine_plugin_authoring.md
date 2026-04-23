# Engine Plugin Authoring Guide

_The definitive "how do I add a new engine to RunAnywhere?" reference.
Updated for v3.1 (`RAC_PLUGIN_API_VERSION = 3u`)._

## Status

- **Current ABI**: `RAC_PLUGIN_API_VERSION = 3u` (v3.0.0+)
- **Legacy `rac_service_*` registry**: DELETED in v3.0.0. There is no
  longer a "legacy path" — the unified plugin registry is the only path.
- **Every per-primitive ops struct** (`rac_llm_service_ops_t`,
  `rac_stt_service_ops_t`, `rac_tts_service_ops_t`, `rac_vad_service_ops_t`,
  `rac_vlm_service_ops_t`, `rac_diffusion_service_ops_t`,
  `rac_embeddings_service_ops_t`) requires a `create` op pointer.
- **CMake**: use [`cmake/plugins.cmake`](../cmake/plugins.cmake)'s
  `rac_add_engine_plugin()` macro for the target. See
  [`plugins/PLUGIN_AUTHORING.md`](plugins/PLUGIN_AUTHORING.md) for
  third-party packaging (static archive vs `dlopen`-able shared library).

## When to use this guide

| You are... | Read |
|---|---|
| Adding a new engine to the in-tree set | This guide. |
| Adding a NEW primitive to an existing backend (e.g. add `embed` to ONNX) | This guide §1 + edit existing `rac_plugin_entry_<name>.cpp`. |
| Fixing a bug in existing primitive ops | Edit `rac_backend_<name>_register.cpp`; ops struct is shared. |
| Packaging a third-party plugin out-of-tree | [`plugins/PLUGIN_AUTHORING.md`](plugins/PLUGIN_AUTHORING.md). |

## Unified path — 4 steps

### 1. Implement the primitive ops struct

Each primitive has a `rac_X_service_ops_t` struct with function pointers
including a v3.0+ mandatory `create` op:

```cpp
// src/backends/mlx/rac_llm_mlx.cpp
#include "rac/features/llm/rac_llm_service.h"

// v3.0+: create op allocates a backend instance and returns it as
// out_impl. The plugin registry calls this when a consumer requests
// the LLM primitive routed to your engine.
static rac_result_t mlx_llm_create_impl(const char* model_id,
                                        const char* config_json,
                                        void** out_impl) {
    auto* mlx = new MlxLLMHandle{};
    // ... your engine init ...
    *out_impl = mlx;
    return RAC_SUCCESS;
}

static rac_result_t mlx_llm_load(void* impl, const char* model_path) {
    auto* mlx = static_cast<MlxLLMHandle*>(impl);
    // ... load weights ...
    return RAC_SUCCESS;
}

// ... generate, generate_stream, unload, destroy, etc.

extern "C" const rac_llm_service_ops_t g_mlx_ops = {
    .create        = mlx_llm_create_impl,   // v3.0+ mandatory
    .load          = mlx_llm_load,
    .generate      = mlx_llm_generate,
    .generate_stream = mlx_llm_generate_stream,
    .unload        = mlx_llm_unload,
    .destroy       = mlx_llm_destroy,
    // ... fill all required ops; nullptr only for optional ops ...
};
```

### 2. Define the engine vtable + plugin entry point

```cpp
// src/backends/mlx/rac_plugin_entry_mlx.cpp
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/llm/rac_llm_service.h"

extern "C" {
extern const rac_llm_service_ops_t g_mlx_ops;

static const rac_engine_vtable_t g_mlx_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,  // currently 3u
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

    /* llm_ops          */ &g_mlx_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    /* embeddings_ops   */ nullptr,

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
- `metadata.abi_version` MUST equal `RAC_PLUGIN_API_VERSION` (currently `3u`).
- `metadata.name` MUST be unique across all registered engines.
- Fill exactly the primitive slots you serve; leave everything else `nullptr`.
- `capability_check` returning non-zero rejects the plugin silently
  (no error log) — useful for hardware/OS gating.

### 3. Declare the entry in a public header

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

### 4. Hook CMake via `rac_add_engine_plugin()`

The canonical macro lives at [`cmake/plugins.cmake`](../cmake/plugins.cmake)
(landed in GAP 07 Phase 4). It handles STATIC vs SHARED branching, the
`RAC_STATIC_PLUGINS` toggle, and emits engine metadata for tooling.

```cmake
# engines/mlx/CMakeLists.txt
include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

option(RAC_BACKEND_MLX "Build the Apple MLX LLM engine plugin" ON)

if(RAC_BACKEND_MLX)
    # ... engine-specific FetchContent / find_package above the macro call ...

    rac_add_engine_plugin(mlx
        SOURCES
            rac_llm_mlx.cpp
            rac_plugin_entry_mlx.cpp
        LINK_LIBRARIES mlx_runtime
        RUNTIMES METAL CPU
        FORMATS GGUF SAFETENSORS
    )
endif()
```

Static-build apps additionally need `rac_force_load(my_app PLUGINS mlx)`
to keep the static-init Registrar alive; see
[`plugins/PLUGIN_AUTHORING.md`](plugins/PLUGIN_AUTHORING.md).

## Registering at startup

Pick the simplest path:

```cpp
// C++ app: static-init register (most common).
#include "rac/plugin/rac_plugin_entry_mlx.h"
RAC_STATIC_PLUGIN_REGISTER(mlx);
```

```c
// Manual register (explicit ordering).
#include "rac/plugin/rac_plugin_entry_mlx.h"

int main(void) {
    rac_plugin_registry_register(rac_plugin_entry_mlx());
    // ... app code ...
}
```

```c
// Dynamic load (dlopen).
void* h = dlopen("librunanywhere_mlx.dylib", RTLD_NOW);
rac_plugin_entry_fn entry =
    (rac_plugin_entry_fn)dlsym(h, "rac_plugin_entry_mlx");
rac_plugin_registry_register(entry());
```

## Testing your plugin

Add a test that asserts ABI version, vtable shape, and registration:

```cpp
// sdk/runanywhere-commons/tests/test_plugin_entry_mlx.cpp
#include <cassert>
#include "rac/plugin/rac_plugin_entry_mlx.h"
#include "rac/plugin/rac_engine_vtable.h"

int main() {
    const rac_engine_vtable_t* vt = rac_plugin_entry_mlx();
    assert(vt->metadata.abi_version == RAC_PLUGIN_API_VERSION);  // 3u
    assert(vt->llm_ops != nullptr);
    assert(vt->llm_ops->create != nullptr);  // v3.0+ mandatory

    rac_plugin_registry_register(vt);
    // ... assert plugin appears in the registry, route to it, etc. ...
    return 0;
}
```

Hook into `sdk/runanywhere-commons/tests/CMakeLists.txt` following the
pattern of `test_plugin_entry_llamacpp` and `test_plugin_entry_onnx`.

## Priority ladder (current as of v3.1)

| Priority | Name              | Primitives served            | Platforms  |
|----------|-------------------|------------------------------|------------|
| 120      | metalrt           | LLM + STT + TTS + VLM        | Apple      |
| 110      | whisperkit_coreml | STT                          | Apple      |
| 100      | llamacpp          | LLM (vlm via llamacpp_vlm)   | All        |
| 100      | llamacpp_vlm      | VLM                          | All        |
| 100      | platform          | LLM + TTS + Diffusion        | Apple (FoundationModels, AVSpeech, CoreML) |
|  95      | mlx (example)     | LLM                          | Apple only |
|  90      | whispercpp        | STT                          | All        |
|  80      | onnx              | STT + TTS + VAD + Embeddings + Wakeword | All |

Pick your priority within the existing range:
- 0–40: experimental / CPU fallback engines
- 40–80: standard CPU implementations
- 80–110: optimized / hardware-accelerated implementations
- 110+: Apple-specific hardware paths (Neural Engine, MetalRT)

## Bumping the plugin API version

Bump `RAC_PLUGIN_API_VERSION` in
[`sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h`](../sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h)
when any of:

- `rac_engine_vtable_t` field layout changes (reserved slot promotion,
  new primitive slot).
- A new primitive lands in `rac_primitive.h`.
- Any per-primitive ops struct (`rac_llm_service_ops_t`, etc.) grows or
  shrinks an existing field.

Old plugins loaded against a newer host fail the ABI check and are
rejected with `RAC_ERROR_ABI_VERSION_MISMATCH` — a safe outcome.
Do **not** bump for additive metadata fields (new `capability_flags`
bits, etc.).

### Version history

- `1u` — pre-GAP 02; no unified vtable
- `2u` — GAP 02 Phase 9: unified `rac_engine_vtable_t` shipped alongside
  legacy `rac_service_*` registry
- `3u` — v3.0.0: legacy registry deleted; `create` op added to every
  primitive ops struct; VAD `initialize` op added for symmetry

## Streaming consistency (proto callback pattern)

Engines that produce server-streamed data (voice events, LLM tokens,
download progress) MUST emit serialized proto bytes via the per-feature
`rac_<feature>_set_proto_callback(...)` C API. Frontend SDKs wrap the
callback in their idiomatic stream type (`AsyncStream<T>` / `Flow<T>` /
`Stream<T>` / `AsyncIterable<T>`) using the codegen'd transport at
`idl/codegen/templates/ts_async_iterable.njk` (TS) and the hand-written
adapters under each SDK's `Adapters/` directory.

Example (voice agent, GAP 09):

```cpp
// engines/<name>/<your_voice_engine>.cpp
rac_voice_event_serialize_to_bytes(/* ... */, &bytes, &len);
rac_voice_agent_dispatch_proto_event(handle, bytes, len);
```

Frontend wraps the same handle:

```swift
// Swift
let stream = VoiceAgentStreamAdapter(handle: handle).stream()
for await event in stream { handle(event) }
```

## Loading a third-party plugin from a frontend

Vendor-shipped engine `.dylib` / `.so` / `.dll` libraries can be loaded
at runtime on platforms that allow `dlopen` (macOS, Linux, Android,
Windows). On iOS / WASM the App Store / browser ban dynamic loading;
link the engine at compile time instead.

```swift
// Swift (RunAnywhere+PluginLoader.swift)
try RunAnywhere.PluginLoader.load(at:
    URL(fileURLWithPath: "/opt/runanywhere/plugins/librunanywhere_acme.dylib"))
print("loaded:", RunAnywhere.PluginLoader.registeredNames())
```

```c
// C / C++ (any host)
rac_registry_load_plugin("/opt/runanywhere/plugins/librunanywhere_acme.so");
```

The loader resolves `rac_plugin_entry_<stem>` via `dlsym`, ABI-checks
the returned vtable against the host's `RAC_PLUGIN_API_VERSION`, runs
`capability_check` on the host's `HardwareProfile`, and only then
registers the plugin with the central registry.

## See also

- [`plugins/PLUGIN_AUTHORING.md`](plugins/PLUGIN_AUTHORING.md) —
  third-party plugin packaging (CMake recipes, dlopen vs static, security)
- [`graph_primitives.md`](graph_primitives.md) — DAG primitives
  (`CancelToken`, `RingBuffer`, `StreamEdge`) for engines that need
  pipeline-style fan-out
- [`v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md`](../../v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md)
  — unified plugin ABI spec
- [`v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md`](../../v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md)
  — `dlopen` loader + `RAC_STATIC_PLUGIN_REGISTER` companion
- [`v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md`](../../v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md)
  — `engines/<name>/` layout + `rac_add_engine_plugin()` macro spec
- [`v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md`](../../v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md)
  — proto-encoded streams + per-SDK adapter pattern
