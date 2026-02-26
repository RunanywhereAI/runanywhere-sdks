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
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/events/rac_events.h"

// Use the RAC logging system
#define LOGI(...) RAC_LOG_INFO("LLM.LlamaCpp.C-API", __VA_ARGS__)

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
    RAC_LOG_INFO("LLM.LlamaCpp", "rac_llm_llamacpp_generate: START handle=%p", handle);

    if (handle == nullptr || prompt == nullptr || out_result == nullptr) {
        RAC_LOG_ERROR("LLM.LlamaCpp", "rac_llm_llamacpp_generate: NULL pointer! handle=%p, prompt=%p, out_result=%p",
                      handle, (void*)prompt, (void*)out_result);
        return RAC_ERROR_NULL_POINTER;
    }

    RAC_LOG_INFO("LLM.LlamaCpp", "rac_llm_llamacpp_generate: casting handle...");
    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    RAC_LOG_INFO("LLM.LlamaCpp", "rac_llm_llamacpp_generate: handle cast ok, text_gen=%p", (void*)h->text_gen);

    if (!h->text_gen) {
        RAC_LOG_ERROR("LLM.LlamaCpp", "rac_llm_llamacpp_generate: text_gen is null!");
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Build request from RAC options
    RAC_LOG_INFO("LLM.LlamaCpp", "rac_llm_llamacpp_generate: building request, prompt_len=%zu", strlen(prompt));
    runanywhere::TextGenerationRequest request;
    request.prompt = prompt;
    if (options != nullptr) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        RAC_LOG_INFO("LLM.LlamaCpp", "rac_llm_llamacpp_generate: options max_tokens=%d, temp=%.2f, top_p=%.2f",
                     options->max_tokens, options->temperature, options->top_p);
        if (options->system_prompt != nullptr) {
            request.system_prompt = options->system_prompt;
        }
        // Handle stop sequences if available
        if (options->stop_sequences != nullptr && options->num_stop_sequences > 0) {
            for (int32_t i = 0; i < options->num_stop_sequences; i++) {
                if (options->stop_sequences[i]) {
                    request.stop_sequences.push_back(options->stop_sequences[i]);
                }
            }
        }
        LOGI("[PARAMS] LLM C-API (from caller options): max_tokens=%d, temperature=%.4f, "
             "top_p=%.4f, system_prompt=%s",
             request.max_tokens, request.temperature, request.top_p,
             request.system_prompt.empty() ? "(none)" : "(set)");
    } else {
        LOGI("[PARAMS] LLM C-API (using struct defaults): max_tokens=%d, temperature=%.4f, "
             "top_p=%.4f, system_prompt=(none)",
             request.max_tokens, request.temperature, request.top_p);
    }

    // Generate using C++ class.
    // Wrap in try-catch because llama.cpp's internal template parsing (minja/Jinja
    // engine) and tokenization can throw C++ exceptions for certain model chat
    // templates that use unsupported features. Without this catch, the exception
    // propagates through the extern "C" boundary causing undefined behavior in WASM
    // (Emscripten returns the exception pointer as the function return value).
    RAC_LOG_INFO("LLM.LlamaCpp", "rac_llm_llamacpp_generate: calling text_gen->generate()...");
    runanywhere::TextGenerationResult result;
    try {
        result = h->text_gen->generate(request);
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    } catch (...) {
        rac_error_set_details("Unknown C++ exception during LLM generation");
        return RAC_ERROR_INFERENCE_FAILED;
    }
    RAC_LOG_INFO("LLM.LlamaCpp", "rac_llm_llamacpp_generate: generate() returned, tokens=%d", result.tokens_generated);

    // finish_reason is std::string; TODO: migrate to enum if TextGenerationResult gains one
    if (result.finish_reason == "error") {
        RAC_LOG_ERROR("LLM.LlamaCpp", "rac_llm_llamacpp_generate: generation failed (e.g. llama_decode error)");
        rac_error_set_details("Generation failed: llama_decode returned non-zero");
        return RAC_ERROR_GENERATION_FAILED;
    }

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
    if (options != nullptr) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        if (options->system_prompt != nullptr) {
            request.system_prompt = options->system_prompt;
        }
        if (options->stop_sequences != nullptr && options->num_stop_sequences > 0) {
            for (int32_t i = 0; i < options->num_stop_sequences; i++) {
                if (options->stop_sequences[i]) {
                    request.stop_sequences.push_back(options->stop_sequences[i]);
                }
            }
        }
        LOGI("[PARAMS] LLM C-API (from caller options): max_tokens=%d, temperature=%.4f, "
             "top_p=%.4f, system_prompt=%s",
             request.max_tokens, request.temperature, request.top_p,
             request.system_prompt.empty() ? "(none)" : "(set)");
    } else {
        LOGI("[PARAMS] LLM C-API (using struct defaults): max_tokens=%d, temperature=%.4f, "
             "top_p=%.4f, system_prompt=(none)",
             request.max_tokens, request.temperature, request.top_p);
    }

    // Stream using C++ class (see generate for rationale on try-catch)
    bool success = false;
    try {
        success =
            h->text_gen->generate_stream(request, [callback, user_data](const std::string& token) -> bool {
                return callback(token.c_str(), RAC_FALSE, user_data) == RAC_TRUE;
            });
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    } catch (...) {
        rac_error_set_details("Unknown C++ exception during streaming LLM generation");
        return RAC_ERROR_INFERENCE_FAILED;
    }

    if (success) {
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

// =============================================================================
// LORA ADAPTER API IMPLEMENTATION
// =============================================================================

rac_result_t rac_llm_llamacpp_load_lora(rac_handle_t handle,
                                         const char* adapter_path,
                                         float scale) {
    if (handle == nullptr || adapter_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    if (!h->text_gen->load_lora_adapter(adapter_path, scale)) {
        rac_error_set_details("Failed to load LoRA adapter");
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_remove_lora(rac_handle_t handle,
                                           const char* adapter_path) {
    if (handle == nullptr || adapter_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    if (!h->text_gen->remove_lora_adapter(adapter_path)) {
        return RAC_ERROR_NOT_FOUND;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_clear_lora(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    h->text_gen->clear_lora_adapters();
    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_get_lora_info(rac_handle_t handle, char** out_json) {
    if (handle == nullptr || out_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto info = h->text_gen->get_lora_info();
    std::string json_str = info.dump();
    *out_json = strdup(json_str.c_str());

    return RAC_SUCCESS;
}

// =============================================================================
// ADAPTIVE CONTEXT API IMPLEMENTATION
// =============================================================================

rac_result_t rac_llm_llamacpp_inject_system_prompt(rac_handle_t handle, const char* prompt) {
    if (handle == nullptr || prompt == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    try {
        return h->text_gen->inject_system_prompt(prompt) ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t rac_llm_llamacpp_append_context(rac_handle_t handle, const char* text) {
    if (handle == nullptr || text == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    try {
        return h->text_gen->append_context(text) ? RAC_SUCCESS : RAC_ERROR_INFERENCE_FAILED;
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t rac_llm_llamacpp_probe_confidence(rac_handle_t handle, const char* context,
                                                const char* query, float* out_confidence) {
    if (handle == nullptr || query == nullptr || out_confidence == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    try {
        *out_confidence = h->text_gen->probe_confidence(context ? context : "", query);
        return RAC_SUCCESS;
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        *out_confidence = 0.5f;
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t rac_llm_llamacpp_generate_from_context(rac_handle_t handle, const char* query,
                                                     const rac_llm_options_t* options,
                                                     rac_llm_result_t* out_result) {
    if (handle == nullptr || query == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    TextGenerationRequest request;
    request.prompt = query;
    if (options != nullptr) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        if (options->system_prompt != nullptr) {
            request.system_prompt = options->system_prompt;
        }
        if (options->stop_sequences != nullptr && options->num_stop_sequences > 0) {
            for (int32_t i = 0; i < options->num_stop_sequences; i++) {
                if (options->stop_sequences[i]) {
                    request.stop_sequences.push_back(options->stop_sequences[i]);
                }
            }
        }
    }

    try {
        auto result = h->text_gen->generate_from_context(request);

        if (result.finish_reason == "error") {
            rac_error_set_details("generate_from_context failed");
            return RAC_ERROR_GENERATION_FAILED;
        }

        out_result->text = result.text.empty() ? nullptr : strdup(result.text.c_str());
        out_result->completion_tokens = result.tokens_generated;
        out_result->prompt_tokens = result.prompt_tokens;
        out_result->total_tokens = result.prompt_tokens + result.tokens_generated;
        out_result->time_to_first_token_ms = 0;
        out_result->total_time_ms = result.inference_time_ms;
        out_result->tokens_per_second =
            result.tokens_generated > 0 && result.inference_time_ms > 0
                ? static_cast<float>(result.tokens_generated) /
                      static_cast<float>(result.inference_time_ms / 1000.0)
                : 0.0f;

        return RAC_SUCCESS;
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t rac_llm_llamacpp_clear_context(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    h->text_gen->clear_context();
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
