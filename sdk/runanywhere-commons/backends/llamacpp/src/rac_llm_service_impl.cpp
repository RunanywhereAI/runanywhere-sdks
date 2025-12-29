/**
 * @file rac_llm_service_impl.cpp
 * @brief LlamaCPP Backend - Generic LLM Service Implementation
 *
 * Implements the generic LLM service API by delegating to LlamaCPP functions.
 */

#include "rac_llm_llamacpp.h"

#include <cstdlib>

#include "rac/features/llm/rac_llm_service.h"

// Callback adapter context
struct StreamCallbackContext {
    rac_llm_stream_callback_fn callback;
    void* user_data;
};

// Adapter callback that wraps the generic callback
static rac_bool_t stream_callback_adapter(const char* token, rac_bool_t is_final, void* user_data) {
    auto* ctx = static_cast<StreamCallbackContext*>(user_data);
    (void)is_final;  // Generic callback doesn't have is_final
    if (ctx && ctx->callback) {
        return ctx->callback(token, ctx->user_data);
    }
    return RAC_TRUE;
}

extern "C" {

rac_result_t rac_llm_create(const char* model_path, rac_handle_t* out_handle) {
    return rac_llm_llamacpp_create(model_path, nullptr, out_handle);
}

void rac_llm_destroy(rac_handle_t handle) {
    rac_llm_llamacpp_destroy(handle);
}

rac_result_t rac_llm_initialize(rac_handle_t handle, const char* model_path) {
    return rac_llm_llamacpp_load_model(handle, model_path, nullptr);
}

rac_result_t rac_llm_generate(rac_handle_t handle, const char* prompt,
                              const rac_llm_options_t* options, rac_llm_result_t* out_result) {
    return rac_llm_llamacpp_generate(handle, prompt, options, out_result);
}

rac_result_t rac_llm_generate_stream(rac_handle_t handle, const char* prompt,
                                     const rac_llm_options_t* options,
                                     rac_llm_stream_callback_fn callback, void* user_data) {
    StreamCallbackContext ctx = {callback, user_data};
    return rac_llm_llamacpp_generate_stream(handle, prompt, options, stream_callback_adapter, &ctx);
}

rac_result_t rac_llm_cancel(rac_handle_t handle) {
    rac_llm_llamacpp_cancel(handle);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_cleanup(rac_handle_t handle) {
    return rac_llm_llamacpp_unload_model(handle);
}

rac_result_t rac_llm_get_info(rac_handle_t handle, rac_llm_info_t* out_info) {
    if (!handle || !out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_info->is_ready = rac_llm_llamacpp_is_model_loaded(handle);
    out_info->supports_streaming = RAC_TRUE;
    out_info->current_model = nullptr;
    out_info->context_length = 0;
    return RAC_SUCCESS;
}

}  // extern "C"
