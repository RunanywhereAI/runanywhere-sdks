/**
 * @file rac_llm_llamacpp.cpp
 * @brief RunAnywhere Core - LlamaCPP Backend RAC API Implementation
 *
 * Direct RAC API implementation that calls C++ classes.
 * No intermediate ra_* layer - this is the final C API export.
 */

#include "rac_llm_llamacpp.h"

#include "llamacpp_backend.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#define LLAMA_ALOG(...) __android_log_print(ANDROID_LOG_INFO, "LLM.LlamaCpp.JNI", __VA_ARGS__)
#else
#define LLAMA_ALOG(...) ((void)0)
#endif
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
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
// CALLER STOP SEQUENCE HELPERS
// =============================================================================
//
// Mirrors the VLM helpers in engines/llamacpp/rac_vlm_llamacpp.cpp:797-841
// (collect_stop_sequences / find_first_stop_sequence / max_stop_length). The
// inner llama.cpp text-generation loop only honours a built-in static stop list
// (engines/llamacpp/llamacpp_backend.cpp:931, :1275), so caller-supplied stops
// passed via rac_llm_options_t::stop_sequences are enforced here at the C-API
// boundary.
namespace {

std::vector<std::string> collect_user_stop_sequences(const rac_llm_options_t* options) {
    std::vector<std::string> result;
    if (options == nullptr || options->stop_sequences == nullptr ||
        options->num_stop_sequences == 0) {
        return result;
    }
    result.reserve(options->num_stop_sequences);
    for (size_t i = 0; i < options->num_stop_sequences; ++i) {
        const char* seq = options->stop_sequences[i];
        if (seq != nullptr && seq[0] != '\0') {
            result.emplace_back(seq);
        }
    }
    return result;
}

size_t find_first_stop_sequence(const std::string& window,
                                const std::vector<std::string>& stops) {
    size_t earliest = std::string::npos;
    for (const auto& stop_seq : stops) {
        const size_t pos = window.find(stop_seq);
        if (pos != std::string::npos && (earliest == std::string::npos || pos < earliest)) {
            earliest = pos;
        }
    }
    return earliest;
}

size_t max_stop_length(const std::vector<std::string>& stops) {
    size_t m = 0;
    for (const auto& s : stops) {
        if (s.size() > m) {
            m = s.size();
        }
    }
    return m;
}

}  // namespace

// =============================================================================
// LLAMACPP API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_llm_llamacpp_create(const char* model_path,
                                     const rac_llm_llamacpp_config_t* config,
                                     rac_handle_t* out_handle) {
    if (out_handle == nullptr || model_path == nullptr) {
        // Matches the sherpa STT/TTS/VAD wrappers (e.g.
        // engines/sherpa/rac_stt_sherpa.cpp:67) — refuse a NULL path instead of
        // letting std::string construction at engines/llamacpp/llamacpp_backend.cpp:267
        // hit undefined behaviour.
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
    LLAMA_ALOG("rac_llm_llamacpp_create: initializing backend for %s", model_path);
    if (!handle->backend->initialize(init_config)) {
        LLAMA_ALOG("rac_llm_llamacpp_create: backend init FAILED");
        delete handle;
        rac_error_set_details("Failed to initialize LlamaCPP backend");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Get text generation component
    handle->text_gen = handle->backend->get_text_generation();
    if (!handle->text_gen) {
        LLAMA_ALOG("rac_llm_llamacpp_create: get_text_generation FAILED");
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
    LLAMA_ALOG("rac_llm_llamacpp_create: calling load_model(%s)", model_path);
    if (!handle->text_gen->load_model(model_path, model_config)) {
        LLAMA_ALOG("rac_llm_llamacpp_create: load_model FAILED");
        delete handle;
        rac_error_set_details("Failed to load model");
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }
    LLAMA_ALOG("rac_llm_llamacpp_create: load_model SUCCESS");

    *out_handle = static_cast<rac_handle_t>(handle);

    // DUP-06: "llm.backend.created" now emitted once by the commons LLM
    // service layer
    // (sdk/runanywhere-commons/src/features/llm/rac_llm_service.cpp) so future
    // backends inherit the emit without duplicating it per plugin.

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_unload_model(rac_handle_t handle) {
    // ENG-LLAMA-05: teardown is owned by rac_llm_llamacpp_destroy; cleanup()
    // is a no-op so the commons vtable cleanup slot doesn't report a spurious
    // NOT_SUPPORTED for every LLM teardown.
    (void)handle;
    return RAC_SUCCESS;
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
    RAC_LOG_DEBUG("LLM.LlamaCpp", "rac_llm_llamacpp_generate: START handle=%p", handle);

    if (handle == nullptr || prompt == nullptr || out_result == nullptr) {
        RAC_LOG_ERROR("LLM.LlamaCpp",
                      "rac_llm_llamacpp_generate: NULL pointer! handle=%p, "
                      "prompt=%p, out_result=%p",
                      handle, (void*)prompt, (void*)out_result);
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);

    if (!h->text_gen) {
        RAC_LOG_ERROR("LLM.LlamaCpp", "rac_llm_llamacpp_generate: text_gen is null!");
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Build request from RAC options
    RAC_LOG_DEBUG("LLM.LlamaCpp", "rac_llm_llamacpp_generate: building request, prompt_len=%zu",
                  strlen(prompt));
    runanywhere::TextGenerationRequest request;
    request.prompt = prompt;
    if (options != nullptr) {
        request.max_tokens = options->max_tokens;
        request.temperature = options->temperature;
        request.top_p = options->top_p;
        RAC_LOG_INFO("LLM.LlamaCpp",
                     "rac_llm_llamacpp_generate: options max_tokens=%d, temp=%.2f, "
                     "top_p=%.2f",
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
        RAC_LOG_INFO("LLM.LlamaCpp.C-API",
                     "[PARAMS] LLM C-API (from caller options): max_tokens=%d, "
                     "temperature=%.4f, "
                     "top_p=%.4f, system_prompt=%s",
                     request.max_tokens, request.temperature, request.top_p,
                     request.system_prompt.empty() ? "(none)" : "(set)");
    } else {
        RAC_LOG_INFO("LLM.LlamaCpp.C-API",
                     "[PARAMS] LLM C-API (using struct defaults): max_tokens=%d, "
                     "temperature=%.4f, "
                     "top_p=%.4f, system_prompt=(none)",
                     request.max_tokens, request.temperature, request.top_p);
    }

    // Generate using C++ class.
    // Wrap in try-catch because llama.cpp's internal template parsing
    // (minja/Jinja engine) and tokenization can throw C++ exceptions for certain
    // model chat templates that use unsupported features. Without this catch, the
    // exception propagates through the extern "C" boundary causing undefined
    // behavior in WASM (Emscripten returns the exception pointer as the function
    // return value).
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
    RAC_LOG_DEBUG("LLM.LlamaCpp", "rac_llm_llamacpp_generate: generate() returned, tokens=%d",
                  result.tokens_generated);

    // finish_reason is std::string; TODO: migrate to enum if TextGenerationResult
    // gains one
    if (result.finish_reason == "error") {
        RAC_LOG_ERROR("LLM.LlamaCpp",
                      "rac_llm_llamacpp_generate: generation "
                      "failed (e.g. llama_decode error)");
        rac_error_set_details("Generation failed: llama_decode returned non-zero");
        return RAC_ERROR_GENERATION_FAILED;
    }

    // Caller-supplied stop sequences are collected into request.stop_sequences
    // above but the inner generate loop (engines/llamacpp/llamacpp_backend.cpp)
    // only honours a built-in static list. Truncate the buffered text at the
    // first caller stop so non-streaming callers see consistent semantics.
    const std::vector<std::string> user_stops = collect_user_stop_sequences(options);
    if (!user_stops.empty() && !result.text.empty()) {
        const size_t cut = find_first_stop_sequence(result.text, user_stops);
        if (cut != std::string::npos) {
            result.text.resize(cut);
        }
    }

    // Fill RAC result struct
    if (!result.text.empty()) {
        out_result->text = strdup(result.text.c_str());
        if (!out_result->text) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    } else {
        out_result->text = nullptr;
    }
    out_result->completion_tokens = result.tokens_generated;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->total_tokens = result.prompt_tokens + result.tokens_generated;
    out_result->time_to_first_token_ms = 0;
    out_result->total_time_ms = result.inference_time_ms;
    out_result->tokens_per_second =
        result.tokens_generated > 0 && result.inference_time_ms > 0
            ? (float)result.tokens_generated / (result.inference_time_ms / 1000.0f)
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
        RAC_LOG_INFO("LLM.LlamaCpp.C-API",
                     "[PARAMS] LLM C-API (from caller options): max_tokens=%d, "
                     "temperature=%.4f, "
                     "top_p=%.4f, system_prompt=%s",
                     request.max_tokens, request.temperature, request.top_p,
                     request.system_prompt.empty() ? "(none)" : "(set)");
    } else {
        RAC_LOG_INFO("LLM.LlamaCpp.C-API",
                     "[PARAMS] LLM C-API (using struct defaults): max_tokens=%d, "
                     "temperature=%.4f, "
                     "top_p=%.4f, system_prompt=(none)",
                     request.max_tokens, request.temperature, request.top_p);
    }

    // Stream using C++ class (see generate for rationale on try-catch).
    //
    // Caller-supplied stop sequences are not honoured by the inner backend
    // loop, so we wrap the per-token callback with the same rolling stop_window
    // pattern used by the VLM streaming path
    // (engines/llamacpp/rac_vlm_llamacpp.cpp:1390-1444): emit only bytes that
    // cannot still form part of a pending stop match, halt as soon as a stop is
    // matched, and never leak the stop prefix through.
    const std::vector<std::string> user_stops = collect_user_stop_sequences(options);
    const size_t user_stop_max_len = max_stop_length(user_stops);
    std::string stop_window;
    if (user_stop_max_len > 0) {
        stop_window.reserve(user_stop_max_len * 2);
    }
    bool stop_hit = false;

    // Mirrors the terminal_emitted guard in
    // engines/llamacpp/rac_vlm_llamacpp.cpp:1445-1583: the documented streaming
    // contract is that callers ALWAYS receive exactly one callback with
    // is_final=RAC_TRUE before this function returns. Without this guard,
    // exception paths and the prompt-too-long / decode-failure backend paths
    // would surface as RAC_ERROR_INFERENCE_FAILED with no terminal marker and
    // wedge the per-stream synthesizer (Swift AsyncStream, Kotlin Flow, Dart
    // StreamController, TS AsyncIterable) that the SDKs build on top.
    bool terminal_emitted = false;

    bool success = false;
    try {
        success = h->text_gen->generate_stream(
            request, [&](const std::string& token) -> bool {
                if (user_stops.empty()) {
                    return callback(token.c_str(), RAC_FALSE, user_data) == RAC_TRUE;
                }
                stop_window.append(token);
                const size_t found_pos = find_first_stop_sequence(stop_window, user_stops);
                if (found_pos != std::string::npos) {
                    if (found_pos > 0) {
                        const std::string prefix = stop_window.substr(0, found_pos);
                        callback(prefix.c_str(), RAC_FALSE, user_data);
                    }
                    stop_window.clear();
                    stop_hit = true;
                    return false;  // Cancels the backend generation loop.
                }
                if (stop_window.size() > user_stop_max_len) {
                    const size_t safe_len = stop_window.size() - user_stop_max_len;
                    const std::string safe_chunk = stop_window.substr(0, safe_len);
                    stop_window.erase(0, safe_len);
                    return callback(safe_chunk.c_str(), RAC_FALSE, user_data) == RAC_TRUE;
                }
                return true;
            });
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        if (!terminal_emitted) {
            callback("", RAC_TRUE, user_data);
            terminal_emitted = true;
        }
        return RAC_ERROR_INFERENCE_FAILED;
    } catch (...) {
        rac_error_set_details("Unknown C++ exception during streaming LLM generation");
        if (!terminal_emitted) {
            callback("", RAC_TRUE, user_data);
            terminal_emitted = true;
        }
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Treat a caller-stop hit as a successful terminal exit so the final marker
    // is still emitted to the caller's accumulator. Without this, an early
    // backend cancel from our wrapper would surface as RAC_ERROR_INFERENCE_FAILED
    // and the stream would never see is_final=true.
    if (stop_hit || success) {
        if (!stop_hit && !stop_window.empty()) {
            // Flush any tail bytes held back as potential stop prefix.
            callback(stop_window.c_str(), RAC_FALSE, user_data);
            stop_window.clear();
        }
        callback("", RAC_TRUE, user_data);  // Final token
        terminal_emitted = true;
        return RAC_SUCCESS;
    }

    // generate_stream returned false on a non-stop-hit path (prompt-too-long at
    // engines/llamacpp/llamacpp_backend.cpp:824-834, prefill decode failure at
    // :861-871, or mid-generation decode failure at :1034-1038). Emit the
    // terminal marker so direct C-API consumers can close their iterators
    // before we surface the inference error.
    if (!terminal_emitted) {
        callback("", RAC_TRUE, user_data);
        terminal_emitted = true;
    }
    return RAC_ERROR_INFERENCE_FAILED;
}

rac_result_t
rac_llm_llamacpp_generate_stream_with_timing(rac_handle_t handle, const char* prompt,
                                             const rac_llm_options_t* options,
                                             rac_llm_llamacpp_stream_callback_fn callback,
                                             void* user_data, rac_benchmark_timing_t* timing_out) {
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
    }

    // Stream using C++ class with timing (see generate for rationale on
    // try-catch). Caller stop-sequence handling mirrors
    // rac_llm_llamacpp_generate_stream above.
    const std::vector<std::string> user_stops = collect_user_stop_sequences(options);
    const size_t user_stop_max_len = max_stop_length(user_stops);
    std::string stop_window;
    if (user_stop_max_len > 0) {
        stop_window.reserve(user_stop_max_len * 2);
    }
    bool stop_hit = false;
    // See is_final-terminal-marker rationale on rac_llm_llamacpp_generate_stream
    // above; the timed variant has the exact same streaming contract.
    bool terminal_emitted = false;

    int prompt_tokens = 0;
    bool success = false;
    try {
        success = h->text_gen->generate_stream(
            request,
            [&](const std::string& token) -> bool {
                if (user_stops.empty()) {
                    return callback(token.c_str(), RAC_FALSE, user_data) == RAC_TRUE;
                }
                stop_window.append(token);
                const size_t found_pos = find_first_stop_sequence(stop_window, user_stops);
                if (found_pos != std::string::npos) {
                    if (found_pos > 0) {
                        const std::string prefix = stop_window.substr(0, found_pos);
                        callback(prefix.c_str(), RAC_FALSE, user_data);
                    }
                    stop_window.clear();
                    stop_hit = true;
                    return false;
                }
                if (stop_window.size() > user_stop_max_len) {
                    const size_t safe_len = stop_window.size() - user_stop_max_len;
                    const std::string safe_chunk = stop_window.substr(0, safe_len);
                    stop_window.erase(0, safe_len);
                    return callback(safe_chunk.c_str(), RAC_FALSE, user_data) == RAC_TRUE;
                }
                return true;
            },
            &prompt_tokens, timing_out);
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        if (!terminal_emitted) {
            callback("", RAC_TRUE, user_data);
            terminal_emitted = true;
        }
        return RAC_ERROR_INFERENCE_FAILED;
    } catch (...) {
        rac_error_set_details("Unknown C++ exception during timed streaming LLM generation");
        if (!terminal_emitted) {
            callback("", RAC_TRUE, user_data);
            terminal_emitted = true;
        }
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Capture prompt token count in timing struct
    if (timing_out != nullptr && prompt_tokens > 0) {
        timing_out->prompt_tokens = static_cast<int32_t>(prompt_tokens);
    }

    if (stop_hit || success) {
        if (!stop_hit && !stop_window.empty()) {
            callback(stop_window.c_str(), RAC_FALSE, user_data);
            stop_window.clear();
        }
        callback("", RAC_TRUE, user_data);  // Final token
        terminal_emitted = true;
        return RAC_SUCCESS;
    }

    if (!terminal_emitted) {
        callback("", RAC_TRUE, user_data);
        terminal_emitted = true;
    }
    return RAC_ERROR_INFERENCE_FAILED;
}

void rac_llm_llamacpp_cancel(rac_handle_t handle) {
    // Cancel is intentionally lock-free: LlamaCppTextGeneration::cancel() only
    // stores an atomic flag (engines/llamacpp/llamacpp_backend.cpp:1079).
    //
    // PRECONDITION: callers MUST guarantee `handle` is not concurrently being
    // destroyed via rac_llm_llamacpp_destroy(). Commons-routed callers are
    // protected by the lifecycle service refcount
    // (rac_lifecycle_acquire_service / release_service); direct C-API
    // consumers (benchmarks, tests) own the same invariant. Racing cancel
    // against destroy is undefined behaviour and is the caller's
    // responsibility to prevent.
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
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    return RAC_SUCCESS;
}

// =============================================================================
// LORA ADAPTER API IMPLEMENTATION
// =============================================================================

rac_result_t rac_llm_llamacpp_load_lora(rac_handle_t handle, const char* adapter_path,
                                        float scale) {
    if (handle == nullptr || adapter_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* h = static_cast<rac_llm_llamacpp_handle_impl*>(handle);
    if (!h->text_gen) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    if (!h->text_gen->load_lora_adapter(adapter_path, scale)) {
        std::string detail = std::string("Failed to load LoRA adapter: ") + adapter_path;
        rac_error_set_details(detail.c_str());
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_llm_llamacpp_remove_lora(rac_handle_t handle, const char* adapter_path) {
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
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

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

    runanywhere::TextGenerationRequest request;
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

        // Same caller-stop truncation as rac_llm_llamacpp_generate above —
        // the inner generate_from_context loop in
        // engines/llamacpp/llamacpp_backend.cpp:1275 only honours its built-in
        // static stop list.
        const std::vector<std::string> user_stops = collect_user_stop_sequences(options);
        if (!user_stops.empty() && !result.text.empty()) {
            const size_t cut = find_first_stop_sequence(result.text, user_stops);
            if (cut != std::string::npos) {
                result.text.resize(cut);
            }
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
