# Phase 2: Backend Modularization

**Duration**: 3 weeks
**Objective**: Split each backend into its own library that produces a separate XCFramework/JNILib.

---

## ⚠️ Critical: Backend Factory Pattern

### Problem Identified
`runanywhere-core` exports C++ factories (e.g., `runanywhere::create_llamacpp_backend()`) but the plan assumed C-callable exports.

### Solution
Commons provides **C wrapper functions** that internally call the C++ factories:

```cpp
// In rac_llm_llamacpp.cpp
#include "llamacpp_backend.h"  // C++ header from runanywhere-core

extern "C" {

rac_result_t rac_llm_llamacpp_create(rac_llm_handle_t* out_handle, const rac_llamacpp_config_t* config) {
    // Call C++ factory from runanywhere-core
    auto backend = runanywhere::create_llamacpp_backend();

    // Configure and initialize using the Backend interface
    nlohmann::json cfg;
    cfg["model_path"] = config->model_path;
    cfg["context_length"] = config->context_length;
    // ...

    if (!backend->initialize(cfg)) {
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Store in handle map and return
    *out_handle = store_backend(std::move(backend));
    return RAC_SUCCESS;
}

} // extern "C"
```

---

## ⚠️ Critical: GGML Symbol Conflicts

### Problem Identified
Both `llama.cpp` and `whisper.cpp` include GGML, which can cause symbol conflicts when both backends are enabled.

### Solution
1. **For iOS (static linking)**: Build backends separately, conflicts appear only if both are linked
2. **For Android (shared libs)**: Each backend .so has its own GGML copy
3. **Document limitation**: Apps using BOTH LlamaCpp AND WhisperCpp may see warnings
4. **Future**: Use shared GGML submodule with symbol prefixing

**Verified Combinations:**

| Backend A | Backend B | Compatibility | Notes |
|-----------|-----------|---------------|-------|
| LlamaCpp | ONNX | ✅ Full | No shared dependencies |
| ONNX | WhisperCpp | ✅ Full | No shared dependencies |
| LlamaCpp | WhisperCpp | ⚠️ Warning | GGML duplicate symbols - works but may warn |
| All three | - | ⚠️ Warning | GGML from both LlamaCpp and WhisperCpp |

---

## ⚠️ Capability Matrix (Verified Against Code)

Based on actual `runanywhere-core` implementation:

| Backend | TEXT_GEN | EMBEDDINGS | STT | TTS | VAD | DIARIZATION |
|---------|----------|------------|-----|-----|-----|-------------|
| **LlamaCpp** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **ONNX** | ❌ | ❌ | ✅ | ✅ | ✅ | ❌* |
| **WhisperCpp** | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |

*ONNX diarization is scaffolded in code but marked TODO - **do not advertise until implemented**.

---

## Tasks Overview

| Task ID | Description | Effort | Dependencies |
|---------|-------------|--------|--------------|
| 2.0 | Verify runanywhere-core produces separate backend libs | 1 day | Phase 0 |
| 2.1 | Create LlamaCpp Backend Module | 3 days | Phase 1 |
| 2.2 | Create ONNX Backend Module | 4 days | Phase 1 |
| 2.3 | Create WhisperCpp Backend Module | 2 days | Phase 1 |
| 2.4 | Backend Registration Pattern | 2 days | 2.1, 2.2, 2.3 |
| 2.5 | Separate XCFramework Build | 3 days | 2.1-2.4 |
| 2.6 | Symbol Visibility & Stripping | 2 days | 2.5 |
| 2.7 | Android AAR/JNILib Packaging | 3 days | 2.1-2.4 |

---

## Task 2.1: LlamaCpp Backend Module

### Directory Structure

```
backends/llamacpp/
├── CMakeLists.txt
├── include/
│   └── rac_llm_llamacpp.h
└── src/
    └── rac_llm_llamacpp.cpp
```

### Public Header (rac_llm_llamacpp.h)

```c
// backends/llamacpp/include/rac_llm_llamacpp.h
#ifndef RAC_LLM_LLAMACPP_H
#define RAC_LLM_LLAMACPP_H

#include "rac_core.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Register the LlamaCpp backend with commons.
 * Called automatically when the library is loaded, or manually by wrapper.
 */
RAC_API rac_result_t rac_backend_llamacpp_register(void);

/**
 * Unregister the LlamaCpp backend.
 */
RAC_API rac_result_t rac_backend_llamacpp_unregister(void);

/**
 * Check if LlamaCpp backend is available.
 */
RAC_API bool rac_backend_llamacpp_is_available(void);

// =============================================================================
// LLAMACPP-SPECIFIC CONFIGURATION
// =============================================================================

/**
 * LlamaCpp model configuration
 */
typedef struct {
    uint32_t struct_size;         // sizeof(this struct) for versioning

    // Model loading
    const char* model_path;       // Path to .gguf file
    uint32_t context_length;      // Max context size (default: 2048)
    uint32_t batch_size;          // Batch size for prompt processing (default: 512)

    // Hardware acceleration
    uint32_t gpu_layers;          // Layers to offload to GPU (0 = CPU only)
    bool use_mmap;                // Memory-map model file (default: true)
    bool use_mlock;               // Lock model in memory (default: false)

    // Threading
    uint32_t threads;             // CPU threads (0 = auto)

    // LoRA adapters (optional)
    const char* lora_path;        // Path to LoRA adapter (NULL if none)
    float lora_scale;             // LoRA scale factor (1.0 = full)

} rac_llamacpp_config_t;

/**
 * Initialize default configuration
 */
RAC_API void rac_llamacpp_config_init(rac_llamacpp_config_t* config);

// =============================================================================
// LLM GENERATION OPTIONS
// =============================================================================

typedef struct {
    uint32_t max_tokens;
    float temperature;
    float top_p;
    uint32_t top_k;
    float repeat_penalty;
    const char* stop_sequences;    // JSON array
    const char* system_prompt;
} rac_llm_options_t;

/**
 * Initialize default generation options
 */
RAC_API void rac_llm_options_init(rac_llm_options_t* options);

// =============================================================================
// LLM RESULT
// =============================================================================

typedef struct {
    char* text;                    // Generated text (caller must free via rac_llm_result_free)
    uint32_t prompt_tokens;
    uint32_t completion_tokens;
    float time_to_first_token_ms;
    float total_time_ms;
    float tokens_per_second;
    bool finished;
    const char* finish_reason;     // "stop", "length", "cancelled"
} rac_llm_result_t;

/**
 * Free LLM result (must be called after using rac_llm_result_t)
 */
RAC_API void rac_llm_result_free(rac_llm_result_t* result);

// =============================================================================
// STREAMING CALLBACK
// =============================================================================

/**
 * Streaming callback for token-by-token generation.
 *
 * @param token The generated token
 * @param is_complete True if generation is complete
 * @param result Partial result (may be NULL until complete)
 * @param context User context
 */
typedef void (*rac_llm_stream_callback_t)(
    const char* token,
    bool is_complete,
    const rac_llm_result_t* result,
    void* context
);

// =============================================================================
// LLM OPERATIONS
// =============================================================================

/**
 * Create a LlamaCpp LLM instance
 */
RAC_API rac_result_t rac_llm_llamacpp_create(
    rac_llm_handle_t* out_handle,
    const rac_llamacpp_config_t* config
);

/**
 * Generate text (blocking)
 */
RAC_API rac_result_t rac_llm_llamacpp_generate(
    rac_llm_handle_t handle,
    const char* prompt,
    const rac_llm_options_t* options,
    rac_llm_result_t* out_result
);

/**
 * Generate text with streaming
 */
RAC_API rac_result_t rac_llm_llamacpp_generate_stream(
    rac_llm_handle_t handle,
    const char* prompt,
    const rac_llm_options_t* options,
    rac_llm_stream_callback_t callback,
    void* context
);

/**
 * Cancel ongoing generation
 */
RAC_API rac_result_t rac_llm_llamacpp_cancel(rac_llm_handle_t handle);

/**
 * Destroy LLM instance
 */
RAC_API rac_result_t rac_llm_llamacpp_destroy(rac_llm_handle_t handle);

/**
 * Get model info as JSON
 */
RAC_API rac_result_t rac_llm_llamacpp_get_model_info(
    rac_llm_handle_t handle,
    char** out_json
);

#ifdef __cplusplus
}
#endif

#endif // RAC_LLM_LLAMACPP_H
```

### Implementation (rac_llm_llamacpp.cpp)

```cpp
// backends/llamacpp/src/rac_llm_llamacpp.cpp

#include "rac_llm_llamacpp.h"
#include "rac_core.h"
#include "rac_events.h"

// Include runanywhere-core's llamacpp backend (C++ header)
#include "llamacpp_backend.h"
#include "capabilities/backend.h"

#include <mutex>
#include <unordered_map>
#include <atomic>
#include <memory>
#include <cstring>

namespace runanywhere {
namespace commons {
namespace llamacpp {

// =============================================================================
// Handle Management
// =============================================================================

static std::mutex g_mutex;
static std::unordered_map<rac_llm_handle_t, std::unique_ptr<runanywhere::Backend>> g_instances;
static std::atomic<uint64_t> g_next_handle{1};

static rac_llm_handle_t store_backend(std::unique_ptr<runanywhere::Backend> backend) {
    rac_llm_handle_t handle = reinterpret_cast<rac_llm_handle_t>(g_next_handle++);
    std::lock_guard<std::mutex> lock(g_mutex);
    g_instances[handle] = std::move(backend);
    return handle;
}

static runanywhere::Backend* get_backend(rac_llm_handle_t handle) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_instances.find(handle);
    if (it == g_instances.end()) return nullptr;
    return it->second.get();
}

// =============================================================================
// Service Provider Implementation
// =============================================================================

static bool can_handle(const char* model_id, void* context) {
    // LlamaCpp handles .gguf models
    if (model_id) {
        std::string id(model_id);
        return id.find(".gguf") != std::string::npos ||
               id.find("llamacpp") != std::string::npos ||
               id.find("llama") != std::string::npos;
    }
    return true; // Default LLM provider
}

static rac_result_t create_service(
    const char* model_id,
    void* config,
    void** out_service,
    void* context
) {
    if (!out_service) return RAC_ERROR_NULL_POINTER;

    rac_llamacpp_config_t default_config;
    rac_llamacpp_config_init(&default_config);

    if (model_id) {
        default_config.model_path = model_id;
    }

    rac_llm_handle_t handle;
    rac_result_t result = rac_llm_llamacpp_create(
        &handle,
        config ? static_cast<rac_llamacpp_config_t*>(config) : &default_config
    );

    if (result == RAC_SUCCESS) {
        *out_service = handle;
    }

    return result;
}

static void destroy_service(void* service, void* context) {
    if (service) {
        rac_llm_llamacpp_destroy(static_cast<rac_llm_handle_t>(service));
    }
}

} // namespace llamacpp
} // namespace commons
} // namespace runanywhere

// =============================================================================
// C API Implementation
// =============================================================================

extern "C" {

void rac_llamacpp_config_init(rac_llamacpp_config_t* config) {
    if (!config) return;

    memset(config, 0, sizeof(*config));
    config->struct_size = sizeof(rac_llamacpp_config_t);
    config->context_length = 2048;
    config->batch_size = 512;
    config->gpu_layers = 0;
    config->use_mmap = true;
    config->use_mlock = false;
    config->threads = 0; // Auto
    config->lora_scale = 1.0f;
}

void rac_llm_options_init(rac_llm_options_t* options) {
    if (!options) return;

    memset(options, 0, sizeof(*options));
    options->max_tokens = 256;
    options->temperature = 0.7f;
    options->top_p = 0.9f;
    options->top_k = 40;
    options->repeat_penalty = 1.1f;
}

rac_result_t rac_backend_llamacpp_register(void) {
    // Register with service registry
    rac_capability_provider_t provider = {
        .capability_type = RAC_CAPABILITY_TEXT_GENERATION,
        .provider_name = "llamacpp",
        .priority = 100,
        .can_handle = runanywhere::commons::llamacpp::can_handle,
        .create = runanywhere::commons::llamacpp::create_service,
        .destroy = runanywhere::commons::llamacpp::destroy_service,
        .context = nullptr
    };

    rac_result_t result = rac_service_register_provider(&provider);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // Register module
    rac_module_info_t module = {
        .module_id = "llamacpp",
        .module_name = "LlamaCPP",
        .version = "1.0.0",
        .capabilities = (1 << RAC_CAPABILITY_TEXT_GENERATION),
        .priority = 100
    };

    return rac_module_register(&module);
}

rac_result_t rac_backend_llamacpp_unregister(void) {
    return rac_module_unregister("llamacpp");
}

bool rac_backend_llamacpp_is_available(void) {
    return true; // Always available if linked
}

rac_result_t rac_llm_llamacpp_create(
    rac_llm_handle_t* out_handle,
    const rac_llamacpp_config_t* config
) {
    if (!out_handle || !config) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (!config->model_path) {
        rac_set_last_error_details("model_path is required");
        return RAC_ERROR_INVALID_PARAM;
    }

    // Create backend using runanywhere-core C++ factory
    auto backend = runanywhere::create_llamacpp_backend();
    if (!backend) {
        rac_set_last_error_details("Failed to create LlamaCpp backend");
        return RAC_ERROR_BACKEND_LOAD_FAILED;
    }

    // Configure and initialize
    nlohmann::json cfg;
    cfg["model_path"] = config->model_path;
    cfg["context_length"] = config->context_length;
    cfg["batch_size"] = config->batch_size;
    cfg["gpu_layers"] = config->gpu_layers;
    cfg["use_mmap"] = config->use_mmap;
    cfg["use_mlock"] = config->use_mlock;
    if (config->threads > 0) {
        cfg["threads"] = config->threads;
    }
    if (config->lora_path) {
        cfg["lora_path"] = config->lora_path;
        cfg["lora_scale"] = config->lora_scale;
    }

    if (!backend->initialize(cfg)) {
        rac_set_last_error_details("Failed to initialize LlamaCpp backend");
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Store and return handle
    *out_handle = runanywhere::commons::llamacpp::store_backend(std::move(backend));

    // Publish event
    rac_event_t event = {
        .category = RAC_EVENT_MODEL,
        .type = "model.loaded",
        .payload_json = "{\"backend\":\"llamacpp\"}",
        .destination = RAC_EVENT_DEST_BOTH,
        .timestamp_ms = 0, // Auto-populate
        .session_id = nullptr
    };
    rac_event_publish(&event);

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_generate(
    rac_llm_handle_t handle,
    const char* prompt,
    const rac_llm_options_t* options,
    rac_llm_result_t* out_result
) {
    if (!handle || !prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = runanywhere::commons::llamacpp::get_backend(handle);
    if (!backend) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Get text generation capability
    auto* text_gen = backend->get_capability<runanywhere::ITextGeneration>();
    if (!text_gen) {
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    // Build request
    runanywhere::TextGenerationRequest request;
    request.prompt = prompt;
    if (options) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        request.top_k = options->top_k;
        if (options->system_prompt) {
            request.system_prompt = options->system_prompt;
        }
    }

    // Generate
    auto result = text_gen->generate(request);

    // Convert result
    memset(out_result, 0, sizeof(*out_result));
    out_result->text = strdup(result.text.c_str());
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->completion_tokens = result.completion_tokens;
    out_result->time_to_first_token_ms = result.time_to_first_token_ms;
    out_result->total_time_ms = result.total_time_ms;
    out_result->tokens_per_second = result.tokens_per_second;
    out_result->finished = result.finished;
    out_result->finish_reason = result.stop_reason.c_str();

    return result.success ? RAC_SUCCESS : RAC_ERROR_COMPONENT_FAILED;
}

rac_result_t rac_llm_llamacpp_generate_stream(
    rac_llm_handle_t handle,
    const char* prompt,
    const rac_llm_options_t* options,
    rac_llm_stream_callback_t callback,
    void* context
) {
    if (!handle || !prompt || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = runanywhere::commons::llamacpp::get_backend(handle);
    if (!backend) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* text_gen = backend->get_capability<runanywhere::ITextGeneration>();
    if (!text_gen) {
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    // Build request
    runanywhere::TextGenerationRequest request;
    request.prompt = prompt;
    if (options) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        request.top_k = options->top_k;
        if (options->system_prompt) {
            request.system_prompt = options->system_prompt;
        }
    }

    // Stream with callback
    bool success = text_gen->generate_stream(request, [callback, context](const std::string& token) {
        callback(token.c_str(), false, nullptr, context);
        return true; // Continue generation
    });

    // Final callback
    rac_llm_result_t final_result = {};
    final_result.finished = true;
    final_result.finish_reason = success ? "stop" : "error";
    callback(nullptr, true, &final_result, context);

    return success ? RAC_SUCCESS : RAC_ERROR_COMPONENT_FAILED;
}

rac_result_t rac_llm_llamacpp_cancel(rac_llm_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = runanywhere::commons::llamacpp::get_backend(handle);
    if (!backend) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* text_gen = backend->get_capability<runanywhere::ITextGeneration>();
    if (text_gen) {
        text_gen->cancel();
    }

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_destroy(rac_llm_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    {
        std::lock_guard<std::mutex> lock(runanywhere::commons::llamacpp::g_mutex);
        auto it = runanywhere::commons::llamacpp::g_instances.find(handle);
        if (it == runanywhere::commons::llamacpp::g_instances.end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        runanywhere::commons::llamacpp::g_instances.erase(it);
    }

    // Publish event
    rac_event_t event = {
        .category = RAC_EVENT_MODEL,
        .type = "model.unloaded",
        .payload_json = "{\"backend\":\"llamacpp\"}",
        .destination = RAC_EVENT_DEST_BOTH,
        .timestamp_ms = 0,
        .session_id = nullptr
    };
    rac_event_publish(&event);

    return RAC_SUCCESS;
}

void rac_llm_result_free(rac_llm_result_t* result) {
    if (result && result->text) {
        free(result->text);
        result->text = nullptr;
    }
}

rac_result_t rac_llm_llamacpp_get_model_info(
    rac_llm_handle_t handle,
    char** out_json
) {
    if (!handle || !out_json) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = runanywhere::commons::llamacpp::get_backend(handle);
    if (!backend) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* text_gen = backend->get_capability<runanywhere::ITextGeneration>();
    if (!text_gen) {
        return RAC_ERROR_COMPONENT_NOT_READY;
    }

    auto info = text_gen->get_model_info();
    *out_json = strdup(info.dump().c_str());

    return RAC_SUCCESS;
}

} // extern "C"
```

---

## Task 2.2: ONNX Backend Module

### Capabilities
- STT (Speech-to-Text) via Whisper/Sherpa models
- TTS (Text-to-Speech) via Piper models
- VAD (Voice Activity Detection) via Silero
- ~~DIARIZATION~~ (TODO - not implemented yet)

### Directory Structure

```
backends/onnx/
├── CMakeLists.txt
├── include/
│   ├── rac_stt_onnx.h
│   ├── rac_tts_onnx.h
│   └── rac_vad_onnx.h
└── src/
    ├── rac_stt_onnx.cpp
    ├── rac_tts_onnx.cpp
    ├── rac_vad_onnx.cpp
    └── onnx_registration.cpp
```

### Registration (onnx_registration.cpp)

```cpp
// backends/onnx/src/onnx_registration.cpp

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"
#include "rac_core.h"

// Forward declarations for provider functions
extern bool onnx_stt_can_handle(const char* model_id, void* context);
extern rac_result_t onnx_stt_create_service(const char* model_id, void* config, void** out_service, void* context);
extern void onnx_stt_destroy_service(void* service, void* context);

extern bool onnx_tts_can_handle(const char* model_id, void* context);
extern rac_result_t onnx_tts_create_service(const char* model_id, void* config, void** out_service, void* context);
extern void onnx_tts_destroy_service(void* service, void* context);

extern bool onnx_vad_can_handle(const char* model_id, void* context);
extern rac_result_t onnx_vad_create_service(const char* model_id, void* config, void** out_service, void* context);
extern void onnx_vad_destroy_service(void* service, void* context);

extern "C" {

rac_result_t rac_backend_onnx_register(void) {
    rac_result_t result;

    // Register STT provider
    rac_capability_provider_t stt_provider = {
        .capability_type = RAC_CAPABILITY_STT,
        .provider_name = "onnx-whisper",
        .priority = 100,
        .can_handle = onnx_stt_can_handle,
        .create = onnx_stt_create_service,
        .destroy = onnx_stt_destroy_service,
        .context = nullptr
    };

    result = rac_service_register_provider(&stt_provider);
    if (result != RAC_SUCCESS) return result;

    // Register TTS provider
    rac_capability_provider_t tts_provider = {
        .capability_type = RAC_CAPABILITY_TTS,
        .provider_name = "onnx-piper",
        .priority = 100,
        .can_handle = onnx_tts_can_handle,
        .create = onnx_tts_create_service,
        .destroy = onnx_tts_destroy_service,
        .context = nullptr
    };

    result = rac_service_register_provider(&tts_provider);
    if (result != RAC_SUCCESS) return result;

    // Register VAD provider
    rac_capability_provider_t vad_provider = {
        .capability_type = RAC_CAPABILITY_VAD,
        .provider_name = "onnx-silero",
        .priority = 100,
        .can_handle = onnx_vad_can_handle,
        .create = onnx_vad_create_service,
        .destroy = onnx_vad_destroy_service,
        .context = nullptr
    };

    result = rac_service_register_provider(&vad_provider);
    if (result != RAC_SUCCESS) return result;

    // NOTE: DIARIZATION is NOT registered - it's marked TODO in runanywhere-core

    // Register module with actual capabilities (excluding DIARIZATION)
    rac_module_info_t module = {
        .module_id = "onnx",
        .module_name = "ONNX Runtime",
        .version = "1.0.0",
        .capabilities = (1 << RAC_CAPABILITY_STT) |
                       (1 << RAC_CAPABILITY_TTS) |
                       (1 << RAC_CAPABILITY_VAD),
        .priority = 100
    };

    return rac_module_register(&module);
}

rac_result_t rac_backend_onnx_unregister(void) {
    return rac_module_unregister("onnx");
}

bool rac_backend_onnx_is_available(void) {
    return true;
}

} // extern "C"
```

---

## Task 2.3: WhisperCpp Backend Module

### Capabilities
- STT (Speech-to-Text) - native Whisper inference

### Why Both ONNX and WhisperCpp for STT?

| Feature | ONNX Backend | WhisperCpp Backend |
|---------|--------------|-------------------|
| **Models** | Multiple (Whisper, Sherpa, etc.) | Whisper only |
| **Binary Size** | ~50MB (ONNX Runtime) | ~8MB (native) |
| **Performance** | Good | Excellent (optimized C++) |
| **Streaming** | Yes (via Sherpa) | Limited |
| **Use Case** | Full voice pipeline | LLM apps needing lightweight STT |

### Directory Structure

```
backends/whispercpp/
├── CMakeLists.txt
├── include/
│   └── rac_stt_whispercpp.h
└── src/
    └── rac_stt_whispercpp.cpp
```

### Header (rac_stt_whispercpp.h)

```c
// backends/whispercpp/include/rac_stt_whispercpp.h
#ifndef RAC_STT_WHISPERCPP_H
#define RAC_STT_WHISPERCPP_H

#include "rac_core.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

RAC_API rac_result_t rac_backend_whispercpp_register(void);
RAC_API rac_result_t rac_backend_whispercpp_unregister(void);
RAC_API bool rac_backend_whispercpp_is_available(void);

// =============================================================================
// WHISPERCPP CONFIGURATION
// =============================================================================

typedef struct {
    uint32_t struct_size;
    const char* model_path;       // Path to .bin model file
    const char* language;         // Language code (NULL for auto-detect)
    uint32_t threads;             // CPU threads (0 = auto)
    bool translate;               // Translate to English
    bool use_gpu;                 // Use Metal acceleration (iOS/macOS)
} rac_whispercpp_config_t;

RAC_API void rac_whispercpp_config_init(rac_whispercpp_config_t* config);

// =============================================================================
// STT RESULT
// =============================================================================

typedef struct {
    char* text;                   // Transcribed text (free with rac_stt_result_free)
    float confidence;             // Confidence score [0.0, 1.0]
    float duration_ms;            // Audio duration processed
    const char* language;         // Detected language
} rac_stt_result_t;

RAC_API void rac_stt_result_free(rac_stt_result_t* result);

// =============================================================================
// STT OPERATIONS
// =============================================================================

RAC_API rac_result_t rac_stt_whispercpp_create(
    rac_stt_handle_t* out_handle,
    const rac_whispercpp_config_t* config
);

RAC_API rac_result_t rac_stt_whispercpp_transcribe(
    rac_stt_handle_t handle,
    const float* audio_samples,
    size_t num_samples,
    int sample_rate,
    rac_stt_result_t* out_result
);

RAC_API rac_result_t rac_stt_whispercpp_destroy(rac_stt_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif // RAC_STT_WHISPERCPP_H
```

---

## Task 2.5: Separate XCFramework Build

### XCFramework Naming

| Framework | Contents | Est. Size | Capabilities |
|-----------|----------|-----------|--------------|
| `RACommons.xcframework` | Core commons, registry, events | ~1 MB | Core only |
| `RABackendLlamaCPP.xcframework` | LlamaCpp + llama.cpp | ~15 MB | TEXT_GENERATION |
| `RABackendONNX.xcframework` | ONNX + onnxruntime | ~50 MB | STT, TTS, VAD |
| `RABackendWhisperCPP.xcframework` | WhisperCpp + whisper.cpp | ~8 MB | STT |

---

## Task 2.6: Symbol Visibility & Linker Settings

### Export List (RACommons.exports)

```
# Public symbols for RACommons.xcframework

_rac_init
_rac_shutdown
_rac_is_initialized
_rac_get_version
_rac_get_api_version
_rac_config_init

_rac_module_register
_rac_module_unregister
_rac_module_is_registered
_rac_module_list
_rac_module_list_free
_rac_modules_for_capability

_rac_service_register_provider
_rac_service_create
_rac_service_destroy

_rac_event_subscribe
_rac_event_subscribe_all
_rac_event_unsubscribe
_rac_event_publish

_rac_error_message
_rac_get_last_error_details
_rac_set_last_error_details

_rac_free
_rac_strdup
_rac_get_current_time_ms

_rac_set_platform_adapter
_rac_get_platform_adapter
```

### CMake Symbol Visibility

```cmake
# In CMakeLists.txt for each target

# Hide all symbols by default
set_target_properties(rac_commons PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

# Export only public API
if(APPLE)
    set_target_properties(rac_commons PROPERTIES
        XCODE_ATTRIBUTE_EXPORTED_SYMBOLS_FILE "${CMAKE_CURRENT_SOURCE_DIR}/exports/RACommons.exports"
    )
endif()
```

### Linker Settings for Size Optimization

```cmake
# Size optimization flags
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    target_compile_options(rac_commons PRIVATE
        -Os                      # Optimize for size
        -ffunction-sections      # Separate function sections
        -fdata-sections          # Separate data sections
    )

    if(APPLE)
        target_link_options(rac_commons PRIVATE
            -Wl,-dead_strip      # Strip unused symbols
        )
    else()
        target_link_options(rac_commons PRIVATE
            -Wl,--gc-sections    # GC unused sections
        )
    endif()
endif()
```

---

## Task 2.7: Android AAR/JNILib Packaging

### Singleton Strategy for Android

Android has a challenge with modular `.so` files - each gets its own static variables.

**Solution: Commons owns the registry, backends register via exported function**

```kotlin
// RunAnywhereLoader.kt
object RunAnywhereLoader {
    private val loadedBackends = mutableSetOf<String>()

    init {
        // Always load commons first - it owns the registry
        System.loadLibrary("rac_commons")
    }

    fun loadBackend(backend: String) {
        if (backend !in loadedBackends) {
            System.loadLibrary("rac_backend_$backend")
            loadedBackends.add(backend)
        }
    }
}

// Usage
RunAnywhereLoader.loadBackend("llamacpp")  // Loads librac_backend_llamacpp.so
RunAnywhereLoader.loadBackend("onnx")       // Loads librac_backend_onnx.so
```

### Auto-Registration via Constructor

Each backend library registers itself when loaded:

```cpp
// In backend .so (e.g., rac_backend_llamacpp.so)

#ifdef __ANDROID__
__attribute__((constructor))
static void auto_register_llamacpp_backend() {
    rac_backend_llamacpp_register();
}
#endif
```

### Gradle Dependency Pattern

```kotlin
// Consumer app build.gradle.kts
dependencies {
    // Always required
    implementation("ai.runanywhere:runanywhere-commons:1.0.0")

    // Choose backends
    implementation("ai.runanywhere:runanywhere-backend-llamacpp:1.0.0")
    // implementation("ai.runanywhere:runanywhere-backend-onnx:1.0.0")  // Optional
}
```

---

## Definition of Done

- [ ] LlamaCpp backend compiles with C wrappers calling C++ factories
- [ ] ONNX backend provides STT, TTS, VAD (NOT diarization)
- [ ] WhisperCpp backend provides native STT
- [ ] Each backend registers itself with commons
- [ ] Build script produces 4 separate XCFrameworks
- [ ] Each XCFramework works independently
- [ ] Combined XCFrameworks work together
- [ ] GGML conflict documented for LlamaCpp + WhisperCpp
- [ ] Android AAR packaging with auto-registration
- [ ] Symbols properly hidden/exported

---

*Phase 2 Duration: 3 weeks*
