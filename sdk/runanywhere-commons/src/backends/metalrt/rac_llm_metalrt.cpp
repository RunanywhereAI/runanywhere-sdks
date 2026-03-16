/**
 * @file rac_llm_metalrt.cpp
 * @brief MetalRT LLM backend — wraps metalrt_c_api.h for LLM inference
 */

#include "rac_llm_metalrt.h"

#include <cstdlib>
#include <cstring>

#include "metalrt_c_api.h"

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "LLM.MetalRT";

// =============================================================================
// INTERNAL HANDLE
// =============================================================================

struct rac_llm_metalrt_impl {
    void* handle;  // metalrt_create() handle
    bool loaded;
};

// =============================================================================
// API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_llm_metalrt_create(const char* model_path, rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* impl = new (std::nothrow) rac_llm_metalrt_impl();
    if (!impl) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    impl->handle = metalrt_create();
    if (!impl->handle) {
        delete impl;
        rac_error_set_details("metalrt_create() returned null");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    if (model_path && model_path[0] != '\0') {
        if (!metalrt_load(impl->handle, model_path)) {
            metalrt_destroy(impl->handle);
            delete impl;
            rac_error_set_details("metalrt_load() failed");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        impl->loaded = true;
        RAC_LOG_INFO(LOG_CAT, "Model loaded: %s", model_path);
    }

    *out_handle = static_cast<rac_handle_t>(impl);
    return RAC_SUCCESS;
}

void rac_llm_metalrt_destroy(rac_handle_t handle) {
    if (!handle) return;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (impl->handle) {
        metalrt_destroy(impl->handle);
    }
    delete impl;
}

rac_bool_t rac_llm_metalrt_is_loaded(rac_handle_t handle) {
    if (!handle) return RAC_FALSE;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    return impl->loaded ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_llm_metalrt_generate(rac_handle_t handle, const char* prompt,
                                       const rac_llm_options_t* options,
                                       rac_llm_result_t* out_result) {
    if (!handle || !prompt || !out_result) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;

    struct MetalRTOptions opts = {};
    opts.max_tokens = options ? options->max_tokens : 100;
    opts.temperature = options ? options->temperature : 0.8f;
    opts.top_k = 40;
    opts.think = false;
    opts.reset_cache = true;
    opts.ignore_eos = false;

    struct MetalRTResult result = metalrt_generate(impl->handle, prompt, &opts);

    out_result->text = result.text ? strdup(result.text) : nullptr;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->completion_tokens = result.generated_tokens;
    out_result->total_tokens = result.prompt_tokens + result.generated_tokens;
    out_result->time_to_first_token_ms = static_cast<int64_t>(result.prefill_ms);
    out_result->total_time_ms = static_cast<int64_t>(result.prefill_ms + result.decode_ms);
    out_result->tokens_per_second = static_cast<float>(result.tps);

    metalrt_free_result(result);
    return RAC_SUCCESS;
}

// Adapter to bridge MetalRT's callback to RAC's callback
struct MetalRTStreamCtx {
    rac_llm_metalrt_stream_cb callback;
    void* user_data;
};

static bool metalrt_stream_bridge(const char* piece, void* ctx) {
    auto* adapter = static_cast<MetalRTStreamCtx*>(ctx);
    if (!adapter || !adapter->callback) return false;
    return adapter->callback(piece, RAC_FALSE, adapter->user_data) == RAC_TRUE;
}

rac_result_t rac_llm_metalrt_generate_stream(rac_handle_t handle, const char* prompt,
                                              const rac_llm_options_t* options,
                                              rac_llm_metalrt_stream_cb callback,
                                              void* user_data) {
    if (!handle || !prompt || !callback) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;

    struct MetalRTOptions opts = {};
    opts.max_tokens = options ? options->max_tokens : 100;
    opts.temperature = options ? options->temperature : 0.8f;
    opts.top_k = 40;
    opts.think = false;
    opts.reset_cache = true;
    opts.ignore_eos = false;

    MetalRTStreamCtx ctx = {callback, user_data};
    struct MetalRTResult result = metalrt_generate_stream(
        impl->handle, prompt, metalrt_stream_bridge, &ctx, &opts);

    // Send final token
    callback("", RAC_TRUE, user_data);

    metalrt_free_result(result);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_inject_system_prompt(rac_handle_t handle, const char* prompt) {
    if (!handle || !prompt) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;
    metalrt_set_system_prompt(impl->handle, prompt);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_append_context(rac_handle_t handle, const char* text) {
    if (!handle || !text) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;
    metalrt_cache_prompt(impl->handle, text);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_generate_from_context(rac_handle_t handle, const char* query,
                                                    const rac_llm_options_t* options,
                                                    rac_llm_result_t* out_result) {
    if (!handle || !query || !out_result) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;

    struct MetalRTOptions opts = {};
    opts.max_tokens = options ? options->max_tokens : 100;
    opts.temperature = options ? options->temperature : 0.8f;
    opts.top_k = 40;
    opts.think = false;
    opts.reset_cache = false;
    opts.ignore_eos = false;

    struct MetalRTResult result = metalrt_generate_raw_continue(impl->handle, query, &opts);

    out_result->text = result.text ? strdup(result.text) : nullptr;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->completion_tokens = result.generated_tokens;
    out_result->total_tokens = result.prompt_tokens + result.generated_tokens;
    out_result->time_to_first_token_ms = static_cast<int64_t>(result.prefill_ms);
    out_result->total_time_ms = static_cast<int64_t>(result.prefill_ms + result.decode_ms);
    out_result->tokens_per_second = static_cast<float>(result.tps);

    metalrt_free_result(result);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_clear_context(rac_handle_t handle) {
    if (!handle) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;
    metalrt_clear_kv(impl->handle);
    return RAC_SUCCESS;
}

void rac_llm_metalrt_reset(rac_handle_t handle) {
    if (!handle) return;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (impl->handle) {
        metalrt_reset(impl->handle);
    }
}

int rac_llm_metalrt_context_size(rac_handle_t handle) {
    if (!handle) return 0;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->handle) return 0;
    return metalrt_context_size(impl->handle);
}

const char* rac_llm_metalrt_model_name(rac_handle_t handle) {
    if (!handle) return nullptr;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    if (!impl->handle) return nullptr;
    return metalrt_model_name(impl->handle);
}

}  // extern "C"
