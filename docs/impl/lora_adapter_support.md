# LoRA Adapter Support - Implementation Documentation

## Table of Contents

- [Overview](#overview)
- [Kotlin SDK Usage Guide](#kotlin-sdk-usage-guide)
  - [Prerequisites](#prerequisites)
  - [Data Types](#data-types)
  - [Loading a LoRA Adapter](#loading-a-lora-adapter)
  - [Stacking Multiple Adapters](#stacking-multiple-adapters)
  - [Removing Adapters](#removing-adapters)
  - [Querying Loaded Adapters](#querying-loaded-adapters)
  - [Error Handling](#error-handling)
  - [Android ViewModel Example](#android-viewmodel-example)
- [C/C++ API Reference](#cc-api-reference-for-other-sdk-implementations)
  - [Component API (Recommended)](#api-level-1-component-api-recommended)
  - [Backend API (LlamaCPP-specific)](#api-level-2-backend-api-llamacpp-specific)
  - [Vtable Integration](#vtable-integration-for-new-backends)
  - [C Usage Example](#usage-example-c)
  - [Swift Usage Example](#usage-example-swift----ios-sdk-pattern)
  - [Return Codes Reference](#return-codes-reference)
- [Architecture](#architecture)
  - [Layer Diagram](#layer-diagram)
  - [Vtable Dispatch](#vtable-dispatch)
- [llama.cpp LoRA API (b8011)](#llamacpp-lora-api-b8011)
- [Optimizations and Design Decisions](#optimizations-and-design-decisions)
  - [Context Recreation](#context-recreation)
  - [KV Cache Invalidation](#kv-cache-invalidation)
  - [Thread Safety](#thread-safety)
  - [Duplicate Detection](#duplicate-detection)
  - [Rollback on Failure](#rollback-on-failure)
  - [Adapter Memory Lifecycle](#adapter-memory-lifecycle)
- [Files Changed](#files-changed)
- [How to Extend](#how-to-extend)
- [Build Verification](#build-verification)
- [Changelog](#changelog)

---

## Overview

LoRA (Low-Rank Adaptation) adapter support was added to the RunAnywhere SDK across
two modules: `sdk/runanywhere-commons` (C/C++) and `sdk/runanywhere-kotlin` (Kotlin
Multiplatform). This enables users to load fine-tuned LoRA adapters (GGUF format)
alongside a base model, hot-swap adapters without reloading the base model, stack
multiple adapters with individual scales, and remove adapters at runtime.

The implementation spans 6 layers, bottom-up: C++ internal, C API, component,
JNI bridge, Kotlin bridge, and Kotlin public API.

---

## Kotlin SDK Usage Guide

### Prerequisites

Before using LoRA adapters:

1. The RunAnywhere SDK must be initialized
2. The LlamaCPP backend must be registered
3. A base model must be loaded via `RunAnywhere.loadLLMModel()`
4. LoRA adapter files must be in GGUF format

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.loadLoraAdapter
import com.runanywhere.sdk.public.extensions.removeLoraAdapter
import com.runanywhere.sdk.public.extensions.clearLoraAdapters
import com.runanywhere.sdk.public.extensions.getLoadedLoraAdapters
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
```

### Data Types

**LoRAAdapterConfig** -- Configuration passed when loading an adapter.

```kotlin
data class LoRAAdapterConfig(
    val path: String,        // Path to the LoRA GGUF file (must not be blank)
    val scale: Float = 1.0f, // Scale factor: 0.0 = no effect, 1.0 = full effect, >1.0 = amplified
)
```

**LoRAAdapterInfo** -- Read-only info returned when querying loaded adapters.

```kotlin
data class LoRAAdapterInfo(
    val path: String,      // Path used when loading
    val scale: Float,      // Active scale factor
    val applied: Boolean,  // Whether the adapter is currently applied to the context
)
```

### Loading a LoRA Adapter

Load a GGUF LoRA file and apply it to the current model. The SDK recreates the
llama.cpp context internally and clears the KV cache.

```kotlin
// Load with default scale (1.0)
RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path = "/path/to/adapter.gguf"))

// Load with custom scale (0.5 = half strength)
RunAnywhere.loadLoraAdapter(
    LoRAAdapterConfig(path = "/path/to/adapter.gguf", scale = 0.5f)
)
```

All functions are `suspend` -- call them from a coroutine scope.

### Stacking Multiple Adapters

Multiple adapters can be applied simultaneously. Each adapter has its own scale.
The effects combine additively at the weight level.

```kotlin
// Load base writing style adapter
RunAnywhere.loadLoraAdapter(
    LoRAAdapterConfig(path = "/path/to/style.gguf", scale = 1.0f)
)

// Stack a domain knowledge adapter on top
RunAnywhere.loadLoraAdapter(
    LoRAAdapterConfig(path = "/path/to/domain.gguf", scale = 0.7f)
)

// Check what's loaded
val adapters = RunAnywhere.getLoadedLoraAdapters()
// adapters.size == 2
```

### Removing Adapters

```kotlin
// Remove a specific adapter by path
RunAnywhere.removeLoraAdapter("/path/to/style.gguf")

// Remove all adapters at once
RunAnywhere.clearLoraAdapters()
```

After removal, the context is recreated and KV cache is cleared. Any remaining
adapters are re-applied automatically.

### Querying Loaded Adapters

```kotlin
val adapters: List<LoRAAdapterInfo> = RunAnywhere.getLoadedLoraAdapters()

for (adapter in adapters) {
    println("Path: ${adapter.path}")
    println("Scale: ${adapter.scale}")
    println("Applied: ${adapter.applied}")
}
```

Returns an empty list if no adapters are loaded or if no model is loaded.

### Error Handling

All LoRA functions throw `SDKError` on failure:

```kotlin
try {
    RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path = "/invalid/path.gguf"))
} catch (e: SDKError) {
    // SDKError.notInitialized -- SDK not initialized
    // SDKError.llm            -- C++ operation failed (bad path, incompatible adapter, etc.)
    println("LoRA error: ${e.message}")
}
```

Common failure causes:
- SDK not initialized (`SDKError.notInitialized`)
- No model loaded (`SDKError.llm` with "no model loaded")
- Invalid adapter file or path (`SDKError.llm`)
- Adapter already loaded with same path (`SDKError.llm` with duplicate detection)
- Adapter incompatible with base model (`SDKError.llm`)

### Android ViewModel Example

A typical Android integration pattern using ViewModel and Compose:

```kotlin
class LlmViewModel : ViewModel() {

    data class UiState(
        val modelLoaded: Boolean = false,
        val loraAdapters: List<LoRAAdapterInfo> = emptyList(),
        val error: String? = null,
    )

    private val _state = MutableStateFlow(UiState())
    val state = _state.asStateFlow()

    fun loadLoraAdapter(path: String, scale: Float = 1.0f) {
        viewModelScope.launch {
            try {
                RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path, scale))
                refreshAdapterList()
            } catch (e: SDKError) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun clearAdapters() {
        viewModelScope.launch {
            RunAnywhere.clearLoraAdapters()
            refreshAdapterList()
        }
    }

    private suspend fun refreshAdapterList() {
        val adapters = RunAnywhere.getLoadedLoraAdapters()
        _state.update { it.copy(loraAdapters = adapters) }
    }
}
```

For a full working Android app, see `examples/android/RunAnyWhereLora/`.

---

## C/C++ API Reference (for other SDK implementations)

This section documents the C functions that back the JNI layer. Any language
that can call C functions (Swift, Python, Dart, Rust, C#, etc.) can use these
directly to implement LoRA support without going through JNI/Kotlin.

There are two API levels to choose from:

### API Level 1: Component API (Recommended)

Header: `include/rac/features/llm/rac_llm_component.h`
Library: `librac_commons.so` / `RACommons.xcframework`

These are the **high-level** functions. They handle mutex locking, service
lookup, and vtable dispatch internally. Use these unless you have a reason
to call the backend directly.

```c
#include "rac/features/llm/rac_llm_component.h"

// handle = the rac_handle_t returned by rac_llm_component_create()

// ---- Load a LoRA adapter ----
// Loads a GGUF LoRA file and applies it to the current model.
// Context is recreated internally. KV cache is cleared.
// Duplicate paths are rejected.
//
// Returns: RAC_SUCCESS, RAC_ERROR_INVALID_HANDLE, RAC_ERROR_INVALID_ARGUMENT,
//          RAC_ERROR_COMPONENT_NOT_READY, RAC_ERROR_NOT_SUPPORTED,
//          or backend-specific error code
rac_result_t rac_llm_component_load_lora(
    rac_handle_t handle,       // Component handle
    const char* adapter_path,  // Absolute path to LoRA .gguf file
    float scale                // 0.0 = no effect, 1.0 = full, >1.0 = amplified
);

// ---- Remove a specific adapter ----
// Removes the adapter that was loaded from the given path.
// Context is recreated and KV cache is cleared.
//
// Returns: RAC_SUCCESS, RAC_ERROR_NOT_FOUND, RAC_ERROR_COMPONENT_NOT_READY
rac_result_t rac_llm_component_remove_lora(
    rac_handle_t handle,
    const char* adapter_path   // Must match the path used in load_lora
);

// ---- Clear all adapters ----
// Removes every loaded adapter. Safe to call with no adapters loaded.
//
// Returns: RAC_SUCCESS
rac_result_t rac_llm_component_clear_lora(
    rac_handle_t handle
);

// ---- Query loaded adapters ----
// Returns a JSON array string describing all loaded adapters.
// Format: [{"path":"/path/to/file.gguf","scale":1.0,"applied":true}, ...]
// Caller MUST free the returned string with free().
//
// Returns: RAC_SUCCESS, RAC_ERROR_COMPONENT_NOT_READY
rac_result_t rac_llm_component_get_lora_info(
    rac_handle_t handle,
    char** out_json            // Output: heap-allocated JSON string
);
```

**JNI mapping** (for reference -- how the Kotlin bridge calls these):

| JNI Function | C Function | Notes |
|---|---|---|
| `racLlmComponentLoadLora(long handle, String path, float scale)` | `rac_llm_component_load_lora(handle, path, scale)` | Returns `int` (0 = success) |
| `racLlmComponentRemoveLora(long handle, String path)` | `rac_llm_component_remove_lora(handle, path)` | Returns `int` |
| `racLlmComponentClearLora(long handle)` | `rac_llm_component_clear_lora(handle)` | Returns `int` |
| `racLlmComponentGetLoraInfo(long handle)` | `rac_llm_component_get_lora_info(handle, &json)` | Returns `String?` (JSON) |

### API Level 2: Backend API (LlamaCPP-specific)

Header: `include/rac/backends/rac_llm_llamacpp.h`
Library: `librac_backend_llamacpp.so` / `RABackendLLAMACPP.xcframework`

These are **low-level** functions that talk directly to the LlamaCPP backend.
Use these if you want to bypass the component layer (e.g., building a custom
pipeline without the lifecycle manager). You must handle your own locking.

```c
#include "rac/backends/rac_llm_llamacpp.h"

// handle = the backend impl pointer (NOT the component handle).
// Obtained from rac_llm_service_t.impl after creating a service.

// Load and apply a LoRA adapter. Context is recreated internally.
rac_result_t rac_llm_llamacpp_load_lora(
    rac_handle_t handle,
    const char* adapter_path,
    float scale
);

// Remove a specific adapter by path.
rac_result_t rac_llm_llamacpp_remove_lora(
    rac_handle_t handle,
    const char* adapter_path
);

// Clear all adapters.
rac_result_t rac_llm_llamacpp_clear_lora(
    rac_handle_t handle
);

// Get adapter info as JSON. Caller must free(*out_json).
rac_result_t rac_llm_llamacpp_get_lora_info(
    rac_handle_t handle,
    char** out_json
);
```

### Vtable Integration (for new backends)

If you are adding LoRA support to a different backend (not LlamaCPP), implement
these 4 function pointers in your `rac_llm_service_ops_t` vtable:

```c
#include "rac/features/llm/rac_llm_service.h"

typedef struct rac_llm_service_ops {
    // ... existing ops (initialize, generate, generate_stream, etc.) ...

    // LoRA ops -- set to NULL if your backend doesn't support LoRA
    rac_result_t (*load_lora)(void* impl, const char* adapter_path, float scale);
    rac_result_t (*remove_lora)(void* impl, const char* adapter_path);
    rac_result_t (*clear_lora)(void* impl);
    rac_result_t (*get_lora_info)(void* impl, char** out_json);
} rac_llm_service_ops_t;
```

The component layer checks for NULL before calling. If your backend sets
these to NULL, calls return `RAC_ERROR_NOT_SUPPORTED`.

### Usage Example (C)

Complete example of loading a model and applying a LoRA adapter using the
component API:

```c
#include "rac/core/rac_core.h"
#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/features/llm/rac_llm_component.h"

int main() {
    // 1. Initialize SDK
    rac_init(NULL);
    rac_backend_llamacpp_register();

    // 2. Create and load model via component
    rac_handle_t component = 0;
    rac_llm_component_create(&component);
    rac_llm_component_load_model(component, "/path/to/model.gguf",
                                  "my-model", "My Model", NULL);

    // 3. Load LoRA adapter (scale = 0.8)
    rac_result_t r = rac_llm_component_load_lora(
        component, "/path/to/adapter.gguf", 0.8f);
    if (r != RAC_SUCCESS) {
        printf("Failed to load LoRA: %s\n", rac_error_message(r));
        return 1;
    }

    // 4. Stack a second adapter
    rac_llm_component_load_lora(component, "/path/to/adapter2.gguf", 0.5f);

    // 5. Query what's loaded
    char* json = NULL;
    rac_llm_component_get_lora_info(component, &json);
    if (json) {
        printf("Adapters: %s\n", json);
        // Output: [{"path":"/path/to/adapter.gguf","scale":0.8,"applied":true},
        //          {"path":"/path/to/adapter2.gguf","scale":0.5,"applied":true}]
        free(json);
    }

    // 6. Generate text (adapters are applied automatically)
    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    rac_llm_result_t result = {0};
    rac_llm_component_generate(component, "Hello, world!", &opts, &result);
    printf("Response: %s\n", result.text);
    rac_llm_result_free(&result);

    // 7. Remove one adapter
    rac_llm_component_remove_lora(component, "/path/to/adapter.gguf");

    // 8. Clear all adapters
    rac_llm_component_clear_lora(component);

    // 9. Cleanup
    rac_llm_component_destroy(component);
    rac_shutdown();
    return 0;
}
```

### Usage Example (Swift -- iOS SDK pattern)

For Swift SDK implementers, the pattern would be:

```swift
// The C functions are imported via CRACommons module
import CRACommons

// Load adapter
let result = rac_llm_component_load_lora(componentHandle, path, scale)
guard result == RAC_SUCCESS else {
    throw SDKError.llm("LoRA load failed: \(rac_error_message(result))")
}

// Query adapters
var jsonPtr: UnsafeMutablePointer<CChar>? = nil
rac_llm_component_get_lora_info(componentHandle, &jsonPtr)
if let json = jsonPtr {
    let jsonString = String(cString: json)
    free(json)
    // Parse JSON string into Swift structs
}
```

### Return Codes Reference

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `RAC_SUCCESS` | Operation succeeded |
| -1 | `RAC_ERROR_INVALID_HANDLE` | NULL or invalid component handle |
| -2 | `RAC_ERROR_INVALID_ARGUMENT` | NULL adapter_path |
| -236 | `RAC_ERROR_NOT_SUPPORTED` | Backend does not implement LoRA (vtable entry is NULL) |
| -230 | `RAC_ERROR_COMPONENT_NOT_READY` | No model loaded |
| -110 | `RAC_ERROR_MODEL_NOT_FOUND` | Adapter file path doesn't exist |
| -600+ | Backend-specific | Duplicate path, incompatible adapter, context recreation failure |

---

## Architecture

### Layer Diagram

```
Kotlin Public API (RunAnywhere.loadLoraAdapter)
       |
       v
Kotlin Bridge (CppBridgeLLM.loadLoraAdapter)
       |
       v
JNI Native (RunAnywhereBridge.racLlmComponentLoadLora)
       |
       v
Component C API (rac_llm_component_load_lora)
       |
       v  [vtable dispatch: llm_service->ops->load_lora()]
Service Vtable (rac_llm_service_ops_t)
       |
       v
Backend C API (rac_llm_llamacpp_load_lora)
       |
       v
C++ Internal (LlamaCppTextGeneration::load_lora_adapter)
       |
       v
llama.cpp API (llama_adapter_lora_init + llama_set_adapter_lora)
```

Each layer only talks to the one directly below it. No layer skips.

### Vtable Dispatch

The component layer (`llm_component.cpp`) does NOT directly call backend-specific
functions. Instead, it dispatches through the `rac_llm_service_ops_t` vtable:

```c
// Component dispatches through vtable (backend-agnostic)
auto* llm_service = reinterpret_cast<rac_llm_service_t*>(service);
if (!llm_service->ops || !llm_service->ops->load_lora)
    return RAC_ERROR_NOT_SUPPORTED;
return llm_service->ops->load_lora(llm_service->impl, adapter_path, scale);
```

The llamacpp backend registers its LoRA vtable entries during service creation
in `rac_backend_llamacpp_register.cpp`. Backends that do not support LoRA leave
these pointers as NULL, and the component returns `RAC_ERROR_NOT_SUPPORTED`.

This keeps `librac_commons.so` decoupled from `librac_backend_llamacpp.so`.

---

## llama.cpp LoRA API (b8011)

The implementation uses these llama.cpp functions:

| Function | Purpose |
|----------|---------|
| `llama_adapter_lora_init(model, path)` | Load adapter tensors from GGUF file |
| `llama_set_adapter_lora(ctx, adapter, scale)` | Apply adapter to context with scale |
| `llama_rm_adapter_lora(ctx, adapter)` | Remove specific adapter from context |
| `llama_clear_adapter_lora(ctx)` | Remove all adapters from context |
| `llama_memory_clear(memory, true)` | Clear KV cache after adapter changes |

Note: `llama_adapter_lora_free()` is deprecated. Adapters are freed automatically
when the model is freed.

---

## Optimizations and Design Decisions

### Context Recreation

llama.cpp requires all adapters to be loaded before context creation. When a new
adapter is loaded after the model is already running (context exists), the
implementation recreates the context:

1. Free old context and sampler
2. Create new context with same parameters (context_size, num_threads)
3. Rebuild sampler chain (temperature, top_p, top_k, repetition penalty)
4. Re-apply ALL loaded adapters to the new context
5. Clear KV cache

This is handled by `recreate_context()` + `apply_lora_adapters()` in
`llamacpp_backend.cpp`. The approach keeps things simple while ensuring
correctness -- adapter memory overhead is typically 1-5% of the base model,
so the cost of re-applying all adapters is negligible.

### KV Cache Invalidation

After any adapter change (load, remove, clear), the KV cache is always
cleared via `llama_memory_clear(llama_get_memory(context_), true)`. This is
mandatory because cached key-value pairs were computed with the previous
adapter configuration and would produce incorrect results.

### Thread Safety

All LoRA operations acquire the same mutex (`mtx_`) used by the text generation
inference loop. This guarantees that adapters are never modified while inference
is in progress. The lock hierarchy is:

- C++ layer: `std::lock_guard<std::mutex>` on `mtx_` (already used by generate)
- Component layer: `std::lock_guard<std::mutex>` on `component->mtx`
- Kotlin bridge layer: `synchronized(lock)` on the CppBridgeLLM lock object

### Duplicate Detection

`load_lora_adapter()` checks for duplicate adapter paths before loading. If the
same path is already loaded, it returns an error instead of loading twice.

### Rollback on Failure

If context recreation fails after an adapter is loaded, the adapter entry is
popped from the `lora_adapters_` vector. Same if `apply_lora_adapters()` fails.
This prevents the tracking vector from going out of sync with actual context
state.

### Adapter Memory Lifecycle

Adapters are stored in a `std::vector<LoraAdapterEntry>` on the
`LlamaCppTextGeneration` instance. When `unload_model_internal()` is called,
adapters are cleared from the context first, then the vector is cleared, then
the context and model are freed. This ordering prevents use-after-free.

---

## Files Changed

### Layer 1: C++ Internal

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/src/backends/llamacpp/llamacpp_backend.h` | Added `LoraAdapterEntry` struct, 4 public methods (`load_lora_adapter`, `remove_lora_adapter`, `clear_lora_adapters`, `get_lora_info`), 2 private helpers (`recreate_context`, `apply_lora_adapters`), `lora_adapters_` vector member |
| `sdk/runanywhere-commons/src/backends/llamacpp/llamacpp_backend.cpp` | Implemented 6 new methods. Modified `unload_model_internal()` to clear adapters before freeing context/model |

### Layer 2: Backend C API

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/include/rac/backends/rac_llm_llamacpp.h` | Added 4 C function declarations: `rac_llm_llamacpp_load_lora`, `rac_llm_llamacpp_remove_lora`, `rac_llm_llamacpp_clear_lora`, `rac_llm_llamacpp_get_lora_info` |
| `sdk/runanywhere-commons/src/backends/llamacpp/rac_llm_llamacpp.cpp` | Implemented 4 C functions. Pattern: validate handle, cast to impl, call C++ method, return result |

### Layer 3: Vtable + Component Wrappers

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_service.h` | Added 4 optional LoRA function pointers to `rac_llm_service_ops_t` vtable: `load_lora`, `remove_lora`, `clear_lora`, `get_lora_info` |
| `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_component.h` | Added 4 component-level function declarations |
| `sdk/runanywhere-commons/src/features/llm/llm_component.cpp` | Implemented 4 component functions. Dispatches through vtable with NULL checks (returns `RAC_ERROR_NOT_SUPPORTED` if backend doesn't implement LoRA) |
| `sdk/runanywhere-commons/src/backends/llamacpp/rac_backend_llamacpp_register.cpp` | Added 4 vtable wrapper functions and wired them into `g_llamacpp_ops` |

### Layer 4: JNI Bridge

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` | Added 4 JNI functions: `racLlmComponentLoadLora`, `racLlmComponentRemoveLora`, `racLlmComponentClearLora`, `racLlmComponentGetLoraInfo` |

### Layer 5: Kotlin Bridge

| File | Changes |
|------|---------|
| `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../RunAnywhereBridge.kt` | Added 4 `external` JNI method declarations |
| `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../CppBridgeLLM.kt` | Added 4 bridge methods with synchronized access, state validation, and logging |

### Layer 6: Kotlin Public API

| File | Changes |
|------|---------|
| `sdk/runanywhere-kotlin/src/commonMain/.../LLMTypes.kt` | Added `LoRAAdapterConfig` and `LoRAAdapterInfo` data classes |
| `sdk/runanywhere-kotlin/src/commonMain/.../RunAnywhere+LoRA.kt` | NEW file. `expect` declarations for 4 public API functions |
| `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../RunAnywhere+LoRA.jvmAndroid.kt` | NEW file. `actual` implementations with init checks, CppBridgeLLM delegation, JSON parsing for adapter info |

---

## How to Extend

### Adding a new LoRA operation

Follow the same 6-layer pattern:

1. Add C++ method to `LlamaCppTextGeneration` in `llamacpp_backend.h/.cpp`
2. Add C function to `rac_llm_llamacpp.h/.cpp`
3. Add vtable entry to `rac_llm_service_ops_t` in `rac_llm_service.h`
4. Wire vtable entry in `rac_backend_llamacpp_register.cpp`
5. Add component wrapper to `rac_llm_component.h` / `llm_component.cpp` (dispatch through vtable)
6. Add JNI function to `runanywhere_commons_jni.cpp`
7. Add external declaration to `RunAnywhereBridge.kt`, bridge method to `CppBridgeLLM.kt`
8. Add expect/actual declarations to `RunAnywhere+LoRA.kt` / `RunAnywhere+LoRA.jvmAndroid.kt`

### Adding scale adjustment without reload

Could be done by calling `llama_set_adapter_lora(ctx, adapter, new_scale)`
directly without context recreation. Would need a new method at each layer.

---

## Build Verification

Android native build (confirmed passing):
```bash
cd sdk/runanywhere-commons
./scripts/build-android.sh
```

C++ desktop build (confirmed passing):
```bash
cd sdk/runanywhere-commons
cmake -B build/dev -DRAC_BUILD_BACKENDS=ON -DRAC_BUILD_JNI=ON
cmake --build build/dev
```

After Android build, copy `.so` files to jniLibs:
```bash
DIST=sdk/runanywhere-commons/dist/android
JNILIBS=sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/src/androidMain/jniLibs/arm64-v8a
/usr/bin/cp $DIST/llamacpp/arm64-v8a/librac_backend_llamacpp.so $JNILIBS/
/usr/bin/cp $DIST/llamacpp/arm64-v8a/librac_backend_llamacpp_jni.so $JNILIBS/
/usr/bin/cp $DIST/llamacpp/arm64-v8a/librac_commons.so $JNILIBS/
/usr/bin/cp $DIST/llamacpp/arm64-v8a/libc++_shared.so $JNILIBS/
/usr/bin/cp $DIST/llamacpp/arm64-v8a/libomp.so $JNILIBS/
/usr/bin/cp $DIST/jni/arm64-v8a/librunanywhere_jni.so $JNILIBS/
```

Kotlin build:
```bash
cd sdk/runanywhere-kotlin
./scripts/sdk.sh build
```

---

## Changelog

| Date | Author | Description |
|------|--------|-------------|
| 2026-02-19 | Claude | Initial implementation of LoRA adapter support across all 6 layers (C++ through Kotlin public API). C++ desktop build verified. |
| 2026-02-19 | Claude | Fixed architecture: Component layer now dispatches LoRA ops through vtable (`rac_llm_service_ops_t`) instead of calling backend directly. This decouples `librac_commons.so` from `librac_backend_llamacpp.so`. Added 4 vtable entries and wrapper functions. Fixed `AttachCurrentThread` cast for Android NDK C++ build. Android native build verified. |
| 2026-02-19 | Claude | Added detailed Kotlin SDK usage guide with data types, code examples, error handling, Android ViewModel pattern, and table of contents with section links. Updated "How to Extend" to include vtable step. |
