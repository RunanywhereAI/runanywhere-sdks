/**
 * @file rac_llm_llamacpp.cpp
 * @brief RunAnywhere Core - LlamaCPP Backend RAC API Implementation
 *
 * Direct RAC API implementation that calls C++ classes.
 * No intermediate ra_* layer - this is the final C API export.
 */

#include "rac_llm_llamacpp.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "llamacpp_backend.h"

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_events.h"

// =============================================================================
// INTERNAL HANDLE STRUCTURE
// =============================================================================

// Internal handle - wraps C++ objects directly (no intermediate ra_* layer)
struct rac_llm_llamacpp_handle_impl {
    std::unique_ptr<runanywhere::LlamaCppBackend> backend;
    runanywhere::LlamaCppTextGeneration* text_gen;  // Owned by backend

    rac_llm_llamacpp_handle_impl() : backend(nullptr), text_gen(nullptr) {}
};

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

    auto* handle = new (std::nothrow) rac_llm_llamacpp_handle_impl();
    if (!handle) {
        rac_error_set_details("Out of memory allocating handle");
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create backend
    handle->backend = std::make_unique<runanywhere::LlamaCppBackend>();

    // Build init config
    nlohmann::json init_config;
    if (config != nullptr && config->num_threads > 0) {
        init_config["num_threads"] = config->num_threads;
    }

    // Initialize backend
    if (!handle->backend->initialize(init_config)) {
        delete handle;
        rac_error_set_details("Failed to initialize LlamaCPP backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Get text generation component
    handle->text_gen = handle->backend->get_text_generation();
    if (!handle->text_gen) {
        delete handle;
        rac_error_set_details("Failed to get text generation component");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Build model config
    nlohmann::json model_config;
    if (config != nullptr) {
        if (config->context_size > 0) {
            model_config["context_size"] = config->context_size;
        }
        if (config->gpu_layers != 0) {
            model_config["gpu_layers"] = config->gpu_layers;
        }
        if (config->batch_size > 0) {
            model_config["batch_size"] = config->batch_size;
        }
    }

    // Load model
    if (!handle->text_gen->load_model(model_path, model_config)) {
        delete handle;
        rac_error_set_details("Failed to load model");
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    *out_handle = static_cast<rac_handle_t>(handle);

    // Publish event
    rac_event_track("llm.backend.created", RAC_EVENT_CATEGORY_LLM, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"llamacpp"})");

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_load_model(rac_handle_t handle, const char* model_path,
                                         const rac_llm_llamacpp_config_t* config) {
    // LlamaCPP loads model during rac_llm_llamacpp_create(), so this is a no-op.
    // This matches the pattern used by ONNX backends (STT/TTS) where initialize is a no-op.
    (void)handle;
    (void)model_path;
    (void)config;
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

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_FALSE;
    }

    return h->text_gen->is_model_loaded() ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_llm_llamacpp_generate(rac_handle_t handle, const char* prompt,
                                       const rac_llm_options_t* options,
                                       rac_llm_result_t* out_result) {
    if (handle == nullptr || prompt == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Build request from RAC options
    runanywhere::TextGenerationRequest request;
    request.prompt = prompt;
    float confidence_threshold = 0.0f;
    if (options != nullptr) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        confidence_threshold = options->confidence_threshold;
        // Handle stop sequences if available
        if (options->stop_sequences != nullptr && options->num_stop_sequences > 0) {
            for (int32_t i = 0; i < options->num_stop_sequences; i++) {
                if (options->stop_sequences[i]) {
                    request.stop_sequences.push_back(options->stop_sequences[i]);
                }
            }
        }
    }

    // Generate using C++ class
    auto result = h->text_gen->generate(request, confidence_threshold);

    // Fill RAC result struct
    out_result->text = result.text.empty() ? nullptr : strdup(result.text.c_str());
    out_result->completion_tokens = result.tokens_generated;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->total_tokens = result.prompt_tokens + result.tokens_generated;
    out_result->time_to_first_token_ms = 0;
    out_result->total_time_ms = result.inference_time_ms;
    out_result->tokens_per_second = result.tokens_generated > 0 && result.inference_time_ms > 0
                                        ? (float)result.tokens_generated /
                                              (result.inference_time_ms / 1000.0f)
                                        : 0.0f;

    // Confidence and cloud handoff fields
    out_result->confidence = result.confidence;
    out_result->cloud_handoff = result.cloud_handoff ? RAC_TRUE : RAC_FALSE;
    out_result->handoff_reason = static_cast<rac_handoff_reason_t>(result.handoff_reason);

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

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    runanywhere::TextGenerationRequest request;
    request.prompt = prompt;
    float confidence_threshold = 0.0f;
    if (options != nullptr) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        confidence_threshold = options->confidence_threshold;
        if (options->stop_sequences != nullptr && options->num_stop_sequences > 0) {
            for (int32_t i = 0; i < options->num_stop_sequences; i++) {
                if (options->stop_sequences[i]) {
                    request.stop_sequences.push_back(options->stop_sequences[i]);
                }
            }
        }
    }

    runanywhere::TextGenerationResult confidence_result;

    // Stream using C++ class
    bool success =
        h->text_gen->generate_stream(
            request,
            [callback, user_data](const std::string& token) -> bool {
                return callback(token.c_str(), RAC_FALSE, user_data) == RAC_TRUE;
            },
            nullptr, confidence_threshold, &confidence_result);

    if (success && !confidence_result.cloud_handoff) {
        callback("", RAC_TRUE, user_data);  // Final token
    }

    return success ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
}

void rac_llm_llamacpp_cancel(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (h->text_gen) {
        h->text_gen->cancel();
    }

    rac_event_track("llm.generation.cancelled", RAC_EVENT_CATEGORY_LLM, RAC_EVENT_DESTINATION_ALL,
                    nullptr);
}

rac_result_t rac_llm_llamacpp_get_model_info(rac_handle_t handle, char** out_json) {
    if (handle == nullptr || out_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto info = h->text_gen->get_model_info();
    if (info.empty()) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    std::string json_str = info.dump();
    *out_json = strdup(json_str.c_str());

    return RAC_SUCCESS;
}

void rac_llm_llamacpp_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (h->text_gen) {
        h->text_gen->unload_model();
    }
    if (h->backend) {
        h->backend->cleanup();
    }
    delete h;

    rac_event_track("llm.backend.destroyed", RAC_EVENT_CATEGORY_LLM, RAC_EVENT_DESTINATION_ALL,
                    R"({"backend":"llamacpp"})");
}

}  // extern "C"
