/**
 * @file rac_llm_llamacpp.cpp
 * @brief RunAnywhere Commons - LlamaCPP Backend Implementation
 *
 * Wraps runanywhere-core's LlamaCPP backend (ra_llamacpp_* functions).
 * Mirrors Swift's LlamaCPPService implementation pattern.
 */

#include "rac_llm_llamacpp.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

// Forward declarations for runanywhere-core C API
// These are defined in runanywhere-core/src/backends/llamacpp/llamacpp_backend.h
extern "C" {

typedef struct ra_llamacpp_handle_t* ra_llamacpp_handle;

typedef struct ra_llamacpp_config {
    int context_size;
    int num_threads;
    int gpu_layers;
    int batch_size;
    float temperature;
    float top_p;
    float min_p;
    int top_k;
} ra_llamacpp_config_t;

typedef struct ra_llamacpp_generate_options {
    int max_tokens;
    float temperature;
    float top_p;
    int top_k;
    const char* stop_sequence;
} ra_llamacpp_generate_options_t;

typedef void (*ra_llamacpp_stream_callback)(const char* token, int is_final, void* user_data);

int ra_llamacpp_create(const char* model_path, const ra_llamacpp_config_t* config,
                       ra_llamacpp_handle* out_handle);
void ra_llamacpp_destroy(ra_llamacpp_handle handle);
int ra_llamacpp_generate(ra_llamacpp_handle handle, const char* prompt,
                         const ra_llamacpp_generate_options_t* options, char** out_text,
                         int* out_tokens_generated);
int ra_llamacpp_generate_stream(ra_llamacpp_handle handle, const char* prompt,
                                const ra_llamacpp_generate_options_t* options,
                                ra_llamacpp_stream_callback callback, void* user_data);
void ra_llamacpp_cancel(ra_llamacpp_handle handle);
int ra_llamacpp_is_ready(ra_llamacpp_handle handle);
char* ra_llamacpp_get_model_info(ra_llamacpp_handle handle);
void ra_llamacpp_free_string(char* str);
void ra_llamacpp_get_default_config(ra_llamacpp_config_t* out_config);
void ra_llamacpp_get_default_options(ra_llamacpp_generate_options_t* out_options);

}  // extern "C"

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

namespace {

// Convert rac config to ra config
ra_llamacpp_config_t to_core_config(const rac_llm_llamacpp_config_t* rac_config) {
    ra_llamacpp_config_t config = {};
    ra_llamacpp_get_default_config(&config);

    if (rac_config != nullptr) {
        config.context_size = rac_config->context_size;
        config.num_threads = rac_config->num_threads;
        config.gpu_layers = rac_config->gpu_layers;
        config.batch_size = rac_config->batch_size;
    }

    return config;
}

// Convert rac options to ra options
ra_llamacpp_generate_options_t to_core_options(const rac_llm_options_t* rac_options) {
    ra_llamacpp_generate_options_t options = {};
    ra_llamacpp_get_default_options(&options);

    if (rac_options != nullptr) {
        options.max_tokens = rac_options->max_tokens;
        options.temperature = rac_options->temperature;
        options.top_p = rac_options->top_p;
        // Note: stop_sequences[0] is used if available
        if (rac_options->stop_sequences != nullptr && rac_options->num_stop_sequences > 0) {
            options.stop_sequence = rac_options->stop_sequences[0];
        }
    }

    return options;
}

// Convert core error codes to RAC error codes
rac_result_t from_core_result(int core_result) {
    if (core_result >= 0) {
        return RAC_SUCCESS;
    }

    // Map common error codes
    // Note: Core uses ra_result_code values, map to RAC range
    switch (core_result) {
        case -1:  // RA_ERROR_INIT_FAILED
            return RAC_ERROR_BACKEND_INIT_FAILED;
        case -2:  // RA_ERROR_MODEL_LOAD_FAILED
            return RAC_ERROR_MODEL_LOAD_FAILED;
        case -3:  // RA_ERROR_INFERENCE_FAILED
            return RAC_ERROR_INFERENCE_FAILED;
        case -4:  // RA_ERROR_INVALID_HANDLE
            return RAC_ERROR_INVALID_HANDLE;
        case -5:  // RA_ERROR_CANCELLED
            return RAC_ERROR_CANCELLED;
        default:
            return RAC_ERROR_BACKEND_INIT_FAILED;
    }
}

// Streaming callback adapter
struct StreamContext {
    rac_llm_llamacpp_stream_callback_fn callback;
    void* user_data;
};

void stream_callback_adapter(const char* token, int is_final, void* user_data) {
    auto* ctx = static_cast<StreamContext*>(user_data);
    if (ctx != nullptr && ctx->callback != nullptr) {
        ctx->callback(token, (is_final != 0) ? RAC_TRUE : RAC_FALSE, ctx->user_data);
    }
}

}  // namespace

// =============================================================================
// LLAMACPP API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_llm_llamacpp_create(const char* model_path,
                                     const rac_llm_llamacpp_config_t* config,
                                     rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    ra_llamacpp_config_t core_config = to_core_config(config);
    ra_llamacpp_handle core_handle = nullptr;

    int result = ra_llamacpp_create(model_path, &core_config, &core_handle);
    if (result != 0) {
        rac_error_set_details("Failed to create LlamaCPP backend");
        return from_core_result(result);
    }

    *out_handle = static_cast<rac_handle_t>(core_handle);

    // Publish event
    rac_event_track("llm.backend.created", RAC_EVENT_CATEGORY_LLM, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"llamacpp"})");

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_load_model(rac_handle_t handle, const char* model_path,
                                         const rac_llm_llamacpp_config_t* config) {
    if (handle == nullptr || model_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // LlamaCPP loads model during create, so we need to destroy and recreate
    // This matches Swift's pattern where loadModel creates a new handle internally
    rac_llm_llamacpp_destroy(handle);

    rac_handle_t new_handle = nullptr;
    rac_result_t result = rac_llm_llamacpp_create(model_path, config, &new_handle);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // Note: The handle value changes, caller should use the result of create instead
    // This is a limitation of the C API - in Swift we have objects with internal state
    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_unload_model(rac_handle_t handle) {
    // LlamaCPP doesn't support unloading without destroying
    // Caller should call destroy instead
    (void)handle;
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_bool_t rac_llm_llamacpp_is_model_loaded(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto core_handle = static_cast<ra_llamacpp_handle>(handle);
    return (ra_llamacpp_is_ready(core_handle) != 0) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_llm_llamacpp_generate(rac_handle_t handle, const char* prompt,
                                       const rac_llm_options_t* options,
                                       rac_llm_result_t* out_result) {
    if (handle == nullptr || prompt == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto core_handle = static_cast<ra_llamacpp_handle>(handle);
    ra_llamacpp_generate_options_t core_options = to_core_options(options);

    char* generated_text = nullptr;
    int tokens_generated = 0;

    int result = ra_llamacpp_generate(core_handle, prompt, &core_options, &generated_text,
                                      &tokens_generated);

    if (result != 0) {
        rac_error_set_details("LlamaCPP generation failed");
        return from_core_result(result);
    }

    // Fill result struct
    out_result->text = generated_text;  // Caller must free with rac_free
    out_result->completion_tokens = tokens_generated;
    out_result->prompt_tokens = 0;  // Not available from core API
    out_result->total_tokens = tokens_generated;
    out_result->time_to_first_token_ms = 0;  // Not available
    out_result->total_time_ms = 0;           // Not available
    out_result->tokens_per_second = 0.0f;    // Not available

    // Publish event
    rac_event_track("llm.generation.completed", RAC_EVENT_CATEGORY_LLM, RAC_EVENT_DESTINATION_ALL,
                    nullptr);

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_generate_stream(rac_handle_t handle, const char* prompt,
                                              const rac_llm_options_t* options,
                                              rac_llm_llamacpp_stream_callback_fn callback,
                                              void* user_data) {
    if (handle == nullptr || prompt == nullptr || callback == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto core_handle = static_cast<ra_llamacpp_handle>(handle);
    ra_llamacpp_generate_options_t core_options = to_core_options(options);

    // Set up callback adapter
    StreamContext ctx{};
    ctx.callback = callback;
    ctx.user_data = user_data;

    int result = ra_llamacpp_generate_stream(core_handle, prompt, &core_options,
                                             stream_callback_adapter, &ctx);

    if (result != 0) {
        rac_error_set_details("LlamaCPP streaming generation failed");
        return from_core_result(result);
    }

    return RAC_SUCCESS;
}

void rac_llm_llamacpp_cancel(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto core_handle = static_cast<ra_llamacpp_handle>(handle);
    ra_llamacpp_cancel(core_handle);

    rac_event_track("llm.generation.cancelled", RAC_EVENT_CATEGORY_LLM, RAC_EVENT_DESTINATION_ALL,
                    nullptr);
}

rac_result_t rac_llm_llamacpp_get_model_info(rac_handle_t handle, char** out_json) {
    if (handle == nullptr || out_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto core_handle = static_cast<ra_llamacpp_handle>(handle);
    char* json = ra_llamacpp_get_model_info(core_handle);

    if (json == nullptr) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    *out_json = json;  // Caller must free with rac_free
    return RAC_SUCCESS;
}

void rac_llm_llamacpp_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto core_handle = static_cast<ra_llamacpp_handle>(handle);
    ra_llamacpp_destroy(core_handle);

    rac_event_track("llm.backend.destroyed", RAC_EVENT_CATEGORY_LLM, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"llamacpp"})");
}

}  // extern "C"
