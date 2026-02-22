# LoRA Adapter Support - Implementation Documentation

## Table of Contents

- [Overview](#overview)
- [Kotlin SDK Usage Guide](#kotlin-sdk-usage-guide)
  - [Prerequisites](#prerequisites)
  - [Data Types](#data-types)
  - [Loading a LoRA Adapter](#loading-a-lora-adapter)
  - [Compatibility Checking](#compatibility-checking)
  - [Stacking Multiple Adapters](#stacking-multiple-adapters)
  - [Removing Adapters](#removing-adapters)
  - [Querying Loaded Adapters](#querying-loaded-adapters)
  - [Downloading Adapters](#downloading-adapters)
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
  - [Compatibility Check Flow](#compatibility-check-flow)
  - [Download Flow](#download-flow)
- [llama.cpp LoRA API (b8011)](#llamacpp-lora-api-b8011)
- [Optimizations and Design Decisions](#optimizations-and-design-decisions)
  - [Context Recreation](#context-recreation)
  - [KV Cache Invalidation](#kv-cache-invalidation)
  - [Thread Safety](#thread-safety)
  - [Duplicate Detection](#duplicate-detection)
  - [Rollback on Failure](#rollback-on-failure)
  - [Adapter Memory Lifecycle](#adapter-memory-lifecycle)
  - [GGUF Metadata-Only Reading](#gguf-metadata-only-reading)
  - [Atomic Downloads](#atomic-downloads)
- [Files Changed](#files-changed)
- [How to Extend](#how-to-extend)
- [Build Verification](#build-verification)
- [Changelog](#changelog)

---

## Overview

LoRA (Low-Rank Adaptation) adapter support was added to the RunAnywhere SDK across
two modules: `sdk/runanywhere-commons` (C/C++) and `sdk/runanywhere-kotlin` (Kotlin
Multiplatform). This enables users to:

- Load fine-tuned LoRA adapters (GGUF format) alongside a base model
- Hot-swap adapters without reloading the base model
- Stack multiple adapters with individual scales
- Remove adapters at runtime
- Check adapter compatibility before loading (architecture match validation)
- Download adapters from URLs or a built-in catalog

The implementation spans 6 layers, bottom-up: C++ internal, C API, component,
JNI bridge, Kotlin bridge, and Kotlin public API. Compatibility checking and
downloading add additional functionality at each layer.

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
import com.runanywhere.sdk.public.extensions.checkLoraCompatibility
import com.runanywhere.sdk.public.extensions.downloadLoraAdapter
import com.runanywhere.sdk.public.extensions.downloadLoraFromCatalog
import com.runanywhere.sdk.public.extensions.availableLoraAdapters
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import com.runanywhere.sdk.public.extensions.LoraCompatibilityResult
import com.runanywhere.sdk.public.extensions.LoraDownloadProgress
import com.runanywhere.sdk.public.extensions.LoraDownloadState
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

**LoraCompatibilityResult** -- Returned by the compatibility check.

```kotlin
data class LoraCompatibilityResult(
    val isCompatible: Boolean,  // true if the adapter matches the loaded model
    val error: String? = null,  // Human-readable reason if incompatible
)
```

**LoraDownloadProgress** -- Emitted during adapter downloads.

```kotlin
enum class LoraDownloadState { PENDING, DOWNLOADING, COMPLETED, ERROR }

data class LoraDownloadProgress(
    val progress: Float,           // 0.0 to 1.0
    val bytesDownloaded: Long,
    val totalBytes: Long?,         // null if server doesn't provide Content-Length
    val state: LoraDownloadState,
    val localPath: String? = null, // Set when state == COMPLETED
    val error: String? = null,     // Set when state == ERROR
)
```

**LoraAdapterEntry** -- A catalog entry describing a downloadable adapter.

```kotlin
data class LoraAdapterEntry(
    val id: String,
    val name: String,
    val description: String,
    val url: String,
    val sizeBytes: Long = 0,
    val filename: String = "$id.gguf",
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

### Compatibility Checking

Before loading an adapter, you can verify that its architecture matches the
loaded base model. This reads GGUF metadata from the adapter file without
loading weights, so it is fast and safe to call at any time.

```kotlin
val result = RunAnywhere.checkLoraCompatibility("/path/to/adapter.gguf")

if (!result.isCompatible) {
    println("Adapter incompatible: ${result.error}")
    // e.g. "Architecture mismatch: LoRA targets 'llama' but model is 'phi3'"
} else {
    // Safe to load
    RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path = "/path/to/adapter.gguf"))
}
```

The check compares the `general.architecture` GGUF metadata key between the
adapter and the currently loaded model. If either file is missing this key,
compatibility is assumed (returns `isCompatible = true`).

Note: `checkLoraCompatibility` is a regular function (not `suspend`) since
the GGUF metadata read is lightweight. The C++ layer also runs this check
automatically inside `load_lora_adapter()`, so loading an incompatible
adapter will fail with an error even without an explicit check.

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

### Downloading Adapters

There are three ways to obtain LoRA adapter files:

**1. Load from a local file** -- If the `.gguf` file is already on device,
pass its path directly to `loadLoraAdapter`.

**2. Download from a URL** -- Downloads any GGUF file from a URL into the
SDK's managed `lora/` directory.

```kotlin
RunAnywhere.downloadLoraAdapter(
    url = "https://huggingface.co/user/repo/resolve/main/adapter.gguf",
    filename = "my-adapter.gguf"
).collect { progress ->
    when (progress.state) {
        LoraDownloadState.DOWNLOADING -> {
            println("Progress: ${(progress.progress * 100).toInt()}%")
        }
        LoraDownloadState.COMPLETED -> {
            val path = progress.localPath!!
            println("Downloaded to: $path")
            // Now load it
            RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path = path))
        }
        LoraDownloadState.ERROR -> {
            println("Download failed: ${progress.error}")
        }
        else -> {}
    }
}
```

The filename is sanitized to end with `.gguf`. Downloads use a temp file with
atomic rename to prevent partial files from being used.

**3. Download from the built-in catalog** -- The SDK ships with a hardcoded
catalog of known adapters.

```kotlin
// List available adapters
val catalog: List<LoraAdapterEntry> = RunAnywhere.availableLoraAdapters()

for (entry in catalog) {
    println("${entry.name}: ${entry.description}")
}

// Download a catalog entry
RunAnywhere.downloadLoraFromCatalog(catalog.first()).collect { progress ->
    if (progress.state == LoraDownloadState.COMPLETED) {
        RunAnywhere.loadLoraAdapter(
            LoRAAdapterConfig(path = progress.localPath!!)
        )
    }
}
```

Downloads are stored in `{SDK models dir}/lora/`.

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
- Adapter incompatible with base model architecture (`SDKError.llm`)

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
                // Check compatibility first
                val compat = withContext(Dispatchers.IO) {
                    RunAnywhere.checkLoraCompatibility(path)
                }
                if (!compat.isCompatible) {
                    _state.update { it.copy(error = "Incompatible LoRA: ${compat.error}") }
                    return@launch
                }

                withContext(Dispatchers.IO) {
                    RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path, scale))
                }
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
// Runs an architecture compatibility check before loading.
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

// ---- Check compatibility ----
// Reads GGUF metadata from the adapter and compares general.architecture
// with the loaded model. Does NOT load the adapter.
// out_error is set to a heap-allocated error string if incompatible.
// Caller MUST free *out_error if non-NULL.
//
// Returns: RAC_SUCCESS if compatible, RAC_ERROR_VALIDATION_FAILED if not
rac_result_t rac_llm_component_check_lora_compat(
    rac_handle_t handle,
    const char* lora_path,     // Path to the LoRA GGUF file
    char** out_error           // Output: NULL if compatible, error string if not
);
```

**JNI mapping** (for reference -- how the Kotlin bridge calls these):

| JNI Function | C Function | Notes |
|---|---|---|
| `racLlmComponentLoadLora(long handle, String path, float scale)` | `rac_llm_component_load_lora(handle, path, scale)` | Returns `int` (0 = success) |
| `racLlmComponentRemoveLora(long handle, String path)` | `rac_llm_component_remove_lora(handle, path)` | Returns `int` |
| `racLlmComponentClearLora(long handle)` | `rac_llm_component_clear_lora(handle)` | Returns `int` |
| `racLlmComponentGetLoraInfo(long handle)` | `rac_llm_component_get_lora_info(handle, &json)` | Returns `String?` (JSON) |
| `racLlmComponentCheckLoraCompat(long handle, String path)` | `rac_llm_component_check_lora_compat(handle, path, &error)` | Returns `String?` (null = compatible, string = error) |

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

// Check compatibility. Returns RAC_TRUE if compatible.
// out_error is set to a heap-allocated string if incompatible. Caller frees.
rac_bool_t rac_llm_llamacpp_check_lora_compat(
    rac_handle_t handle,
    const char* lora_path,
    char** out_error
);

// Read all GGUF metadata as JSON (static -- does not require a loaded model).
// Caller must free(*out_json).
rac_result_t rac_llm_llamacpp_read_gguf_info(
    const char* path,
    char** out_json
);
```

### Vtable Integration (for new backends)

If you are adding LoRA support to a different backend (not LlamaCPP), implement
these 5 function pointers in your `rac_llm_service_ops_t` vtable:

```c
#include "rac/features/llm/rac_llm_service.h"

typedef struct rac_llm_service_ops {
    // ... existing ops (initialize, generate, generate_stream, etc.) ...

    // LoRA ops -- set to NULL if your backend doesn't support LoRA
    rac_result_t (*load_lora)(void* impl, const char* adapter_path, float scale);
    rac_result_t (*remove_lora)(void* impl, const char* adapter_path);
    rac_result_t (*clear_lora)(void* impl);
    rac_result_t (*get_lora_info)(void* impl, char** out_json);
    rac_result_t (*check_lora_compat)(void* impl, const char* lora_path, char** out_error);
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

    // 3. Check adapter compatibility
    char* compat_error = NULL;
    rac_result_t cr = rac_llm_component_check_lora_compat(
        component, "/path/to/adapter.gguf", &compat_error);
    if (cr != RAC_SUCCESS) {
        printf("Incompatible: %s\n", compat_error);
        free(compat_error);
        return 1;
    }

    // 4. Load LoRA adapter (scale = 0.8)
    rac_result_t r = rac_llm_component_load_lora(
        component, "/path/to/adapter.gguf", 0.8f);
    if (r != RAC_SUCCESS) {
        printf("Failed to load LoRA: %s\n", rac_error_message(r));
        return 1;
    }

    // 5. Stack a second adapter
    rac_llm_component_load_lora(component, "/path/to/adapter2.gguf", 0.5f);

    // 6. Query what's loaded
    char* json = NULL;
    rac_llm_component_get_lora_info(component, &json);
    if (json) {
        printf("Adapters: %s\n", json);
        // Output: [{"path":"/path/to/adapter.gguf","scale":0.8,"applied":true},
        //          {"path":"/path/to/adapter2.gguf","scale":0.5,"applied":true}]
        free(json);
    }

    // 7. Generate text (adapters are applied automatically)
    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    rac_llm_result_t result = {0};
    rac_llm_component_generate(component, "Hello, world!", &opts, &result);
    printf("Response: %s\n", result.text);
    rac_llm_result_free(&result);

    // 8. Remove one adapter
    rac_llm_component_remove_lora(component, "/path/to/adapter.gguf");

    // 9. Clear all adapters
    rac_llm_component_clear_lora(component);

    // 10. Cleanup
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

// Check compatibility
var compatError: UnsafeMutablePointer<CChar>? = nil
let compatResult = rac_llm_component_check_lora_compat(
    componentHandle, path, &compatError)
if compatResult != RAC_SUCCESS {
    let errorMsg = String(cString: compatError!)
    free(compatError)
    throw SDKError.llm("Incompatible LoRA: \(errorMsg)")
}

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
| -2 | `RAC_ERROR_INVALID_ARGUMENT` | NULL adapter_path or lora_path |
| -236 | `RAC_ERROR_NOT_SUPPORTED` | Backend does not implement LoRA (vtable entry is NULL) |
| -230 | `RAC_ERROR_COMPONENT_NOT_READY` | No model loaded |
| -110 | `RAC_ERROR_MODEL_NOT_FOUND` | Adapter file path doesn't exist |
| -250 | `RAC_ERROR_VALIDATION_FAILED` | Compatibility check failed (architecture mismatch) |
| -600+ | Backend-specific | Duplicate path, context recreation failure |

---

## Architecture

### Layer Diagram

```
Kotlin Public API (RunAnywhere.loadLoraAdapter / checkLoraCompatibility)
       |
       v
Kotlin Bridge (CppBridgeLLM.loadLoraAdapter / checkLoraCompatibility)
       |
       v
JNI Native (RunAnywhereBridge.racLlmComponentLoadLora / racLlmComponentCheckLoraCompat)
       |
       v
Component C API (rac_llm_component_load_lora / rac_llm_component_check_lora_compat)
       |
       v  [vtable dispatch: llm_service->ops->load_lora() / check_lora_compat()]
Service Vtable (rac_llm_service_ops_t)
       |
       v
Backend C API (rac_llm_llamacpp_load_lora / rac_llm_llamacpp_check_lora_compat)
       |
       v
C++ Internal (LlamaCppTextGeneration::load_lora_adapter / check_lora_compatibility)
       |
       v
llama.cpp / GGUF API (llama_adapter_lora_init + gguf_init_from_file)
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

### Compatibility Check Flow

```
1. Kotlin calls RunAnywhere.checkLoraCompatibility(path)
2. CppBridgeLLM.checkLoraCompatibility(path)
   - synchronized(lock), validates LLM state == READY
3. JNI: racLlmComponentCheckLoraCompat(handle, path)
   - Returns null (compatible) or error string (incompatible)
4. rac_llm_component_check_lora_compat(handle, path, &out_error)
   - Dispatches through vtable: ops->check_lora_compat()
5. Backend wrapper converts rac_bool_t to rac_result_t
6. rac_llm_llamacpp_check_lora_compat(handle, path, &out_error)
   - Casts to C++ impl
7. LlamaCppTextGeneration::check_lora_compatibility(path, error_msg)
   - gguf_init_from_file(lora_path, {.no_alloc=true})
   - gguf_find_key() for "general.architecture"
   - llama_model_meta_val_str() for model architecture
   - Compare strings, return false with error if mismatch
```

### Download Flow

Downloads are handled entirely in Kotlin (no C++ involvement):

```
1. RunAnywhere.downloadLoraAdapter(url, filename) returns Flow<LoraDownloadProgress>
2. Opens HttpURLConnection to the URL
3. Streams to temp file: {models_dir}/lora/{filename}.tmp
4. Emits progress updates every 150ms
5. On completion, atomic rename: .tmp -> .gguf
6. Final emission with state=COMPLETED and localPath set

For catalog downloads:
1. RunAnywhere.availableLoraAdapters() returns hardcoded catalog
2. RunAnywhere.downloadLoraFromCatalog(entry) delegates to downloadLoraAdapter(entry.url, entry.filename)
```

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
| `llama_model_meta_val_str(model, key, buf, len)` | Read model metadata (for compat check) |

For GGUF metadata reading (compatibility check):

| Function | Purpose |
|----------|---------|
| `gguf_init_from_file(path, params)` | Open GGUF file (metadata-only with `no_alloc=true`) |
| `gguf_get_n_kv(ctx)` | Get number of KV metadata entries |
| `gguf_get_key(ctx, i)` | Get key name at index |
| `gguf_get_kv_type(ctx, i)` | Get value type at index |
| `gguf_get_val_str(ctx, i)` | Get string value at index |
| `gguf_find_key(ctx, key)` | Find index of a specific key |
| `gguf_free(ctx)` | Free GGUF context |

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

### GGUF Metadata-Only Reading

The compatibility check uses `gguf_init_from_file()` with
`{.no_alloc = true, .ctx = nullptr}`. This reads only the GGUF header and
KV metadata -- no tensor data is loaded into memory. This makes the check
fast (< 1ms for typical LoRA files) and safe to call repeatedly.

The `read_gguf_metadata()` static method reads all scalar KV pairs (strings,
integers, floats, booleans) and returns them as a JSON object. It also includes
a `_tensor_count` field. This is exposed via `rac_llm_llamacpp_read_gguf_info()`
for future use (e.g., displaying adapter metadata in a UI).

### Atomic Downloads

The download implementation writes to a `.tmp` file first, then renames to the
final filename on completion. This prevents partially downloaded files from
being accidentally loaded as adapters.

---

## Files Changed

### Layer 1: C++ Internal

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/src/backends/llamacpp/llamacpp_backend.h` | Added `LoraAdapterEntry` struct, 4 public LoRA management methods, 2 private helpers (`recreate_context`, `apply_lora_adapters`), `lora_adapters_` vector member, `check_lora_compatibility()` method, `read_gguf_metadata()` static method |
| `sdk/runanywhere-commons/src/backends/llamacpp/llamacpp_backend.cpp` | Added `#include <gguf.h>`. Implemented `read_gguf_metadata()` (GGUF KV reading), `check_lora_compatibility()` (architecture comparison), and integrated compat check into `load_lora_adapter()`. Modified `unload_model_internal()` to clear adapters before freeing context/model |

### Layer 2: Backend C API

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/include/rac/backends/rac_llm_llamacpp.h` | Added 6 C function declarations: `rac_llm_llamacpp_load_lora`, `_remove_lora`, `_clear_lora`, `_get_lora_info`, `_check_lora_compat`, `_read_gguf_info` |
| `sdk/runanywhere-commons/src/backends/llamacpp/rac_llm_llamacpp.cpp` | Implemented 6 C functions. `check_lora_compat` returns `rac_bool_t` with optional error string. `read_gguf_info` is static (no handle needed) |

### Layer 3: Vtable + Component Wrappers

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_service.h` | Added 5 optional LoRA function pointers to `rac_llm_service_ops_t` vtable: `load_lora`, `remove_lora`, `clear_lora`, `get_lora_info`, `check_lora_compat` |
| `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_component.h` | Added 5 component-level function declarations |
| `sdk/runanywhere-commons/src/features/llm/llm_component.cpp` | Implemented 5 component functions. Dispatches through vtable with NULL checks (returns `RAC_ERROR_NOT_SUPPORTED` if backend doesn't implement LoRA). `check_lora_compat` returns `RAC_SUCCESS` when vtable entry is NULL (assumes compatible) |
| `sdk/runanywhere-commons/src/backends/llamacpp/rac_backend_llamacpp_register.cpp` | Added 5 vtable wrapper functions and wired them into `g_llamacpp_ops`. `check_lora_compat` wrapper converts `rac_bool_t` to `RAC_SUCCESS`/`RAC_ERROR_VALIDATION_FAILED` |

### Layer 4: JNI Bridge

| File | Changes |
|------|---------|
| `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` | Added 5 JNI functions: `racLlmComponentLoadLora`, `racLlmComponentRemoveLora`, `racLlmComponentClearLora`, `racLlmComponentGetLoraInfo`, `racLlmComponentCheckLoraCompat`. Compat check returns `null` (compatible) or error string |

### Layer 5: Kotlin Bridge

| File | Changes |
|------|---------|
| `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../RunAnywhereBridge.kt` | Added 5 `external` JNI method declarations including `racLlmComponentCheckLoraCompat` |
| `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../CppBridgeLLM.kt` | Added 5 bridge methods with synchronized access, state validation, and logging. `checkLoraCompatibility()` returns null (compatible) or error string |

### Layer 6: Kotlin Public API

| File | Changes |
|------|---------|
| `sdk/runanywhere-kotlin/src/commonMain/.../LLMTypes.kt` | Added `LoRAAdapterConfig` and `LoRAAdapterInfo` data classes |
| `sdk/runanywhere-kotlin/src/commonMain/.../RunAnywhere+LoRA.kt` | `expect` declarations for 5 public API functions (4 suspend + `checkLoraCompatibility`). Added `LoraCompatibilityResult` data class |
| `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../RunAnywhere+LoRA.jvmAndroid.kt` | `actual` implementations with init checks, CppBridgeLLM delegation, JSON parsing for adapter info. `checkLoraCompatibility` wraps JNI null/string into `LoraCompatibilityResult` |

### Layer 7: Kotlin Download API

| File | Changes |
|------|---------|
| `sdk/runanywhere-kotlin/src/commonMain/.../RunAnywhere+LoRADownload.kt` | `LoraDownloadState` enum, `LoraDownloadProgress` data class, `expect fun downloadLoraAdapter()`, `fun availableLoraAdapters()`, `fun downloadLoraFromCatalog()` |
| `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../RunAnywhere+LoRADownload.jvmAndroid.kt` | `actual` implementation using `HttpURLConnection`. Downloads to `{models_dir}/lora/`. Temp file + atomic rename. 150ms progress throttling |
| `sdk/runanywhere-kotlin/src/commonMain/.../temp/LoraAdapterCatalog.kt` | `LoraAdapterEntry` data class and `LoraAdapterCatalog` object with hardcoded catalog entries |

### Example App

| File | Changes |
|------|---------|
| `examples/android/RunAnyWhereLora/app/src/main/java/.../LoraViewModel.kt` | Added compatibility check before loading in `loadLoraAdapter()`. Added download support with `downloadLoraFromUrl()`, `downloadLoraFromCatalog()`, `loadCatalog()`. Added `LoraDownloadUiState` and catalog state |

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

### Adding new catalog entries

Add new `LoraAdapterEntry` instances to `LoraAdapterCatalog.entries` in
`sdk/runanywhere-kotlin/src/commonMain/.../temp/LoraAdapterCatalog.kt`.

### iOS compatibility checking

The C functions (`rac_llm_component_check_lora_compat`, `rac_llm_llamacpp_read_gguf_info`)
are available in `RACommons.xcframework`. The Swift SDK would need:

1. A wrapper in the Swift bridge layer
2. A public API function matching the Kotlin `checkLoraCompatibility`

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
| 2026-02-22 | Claude | Added LoRA compatibility checking: C++ reads GGUF metadata via `gguf_init_from_file()` (no_alloc) and compares `general.architecture` with loaded model. Full stack: C++ method, C API (`rac_llm_llamacpp_check_lora_compat` + `rac_llm_llamacpp_read_gguf_info`), vtable entry, component API, JNI, Kotlin bridge, public API (`checkLoraCompatibility`). Integrated into `load_lora_adapter()` for automatic early-fail. |
| 2026-02-22 | Claude | Added LoRA download support: `downloadLoraAdapter()` (from URL), `downloadLoraFromCatalog()` (from built-in catalog), `availableLoraAdapters()`. Kotlin-only implementation using `HttpURLConnection` with temp file + atomic rename. Added `LoraDownloadProgress`, `LoraDownloadState`, `LoraAdapterEntry` types. |
| 2026-02-22 | Claude | Updated documentation with compatibility checking and download sections, updated architecture diagrams, vtable info (5 entries), files changed tables, and extension guide. |
