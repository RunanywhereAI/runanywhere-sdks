/**
 * @file rac_vlm_metalrt.cpp
 * @brief MetalRT VLM backend — wraps metalrt_vision_* for vision-language inference
 */

#include "rac_vlm_metalrt.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "metalrt_c_api.h"

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "VLM.MetalRT";

struct rac_vlm_metalrt_impl {
    void* handle;  // metalrt_vision_create() handle
    bool loaded;
};

extern "C" {

rac_result_t rac_vlm_metalrt_create(const char* model_path, rac_handle_t* out_handle) {
    if (!out_handle) return RAC_ERROR_NULL_POINTER;

    auto* impl = new (std::nothrow) rac_vlm_metalrt_impl();
    if (!impl) return RAC_ERROR_OUT_OF_MEMORY;

    impl->handle = metalrt_vision_create();
    if (!impl->handle) {
        delete impl;
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    if (model_path && model_path[0] != '\0') {
        if (!metalrt_vision_load(impl->handle, model_path)) {
            metalrt_vision_destroy(impl->handle);
            delete impl;
            rac_error_set_details("metalrt_vision_load() failed");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        impl->loaded = true;
        RAC_LOG_INFO(LOG_CAT, "Vision model loaded: %s", model_path);
    }

    *out_handle = static_cast<rac_handle_t>(impl);
    return RAC_SUCCESS;
}

void rac_vlm_metalrt_destroy(rac_handle_t handle) {
    if (!handle) return;
    auto* impl = static_cast<rac_vlm_metalrt_impl*>(handle);
    if (impl->handle) {
        metalrt_vision_destroy(impl->handle);
    }
    delete impl;
}

rac_result_t rac_vlm_metalrt_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                      const char* prompt, const rac_vlm_options_t* options,
                                      rac_vlm_result_t* out_result) {
    if (!handle || !image || !prompt || !out_result) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_vlm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;

    // MetalRT needs a file path — handle different image formats
    const char* image_path = nullptr;
    char tmp_path[256] = {};

    if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH) {
        image_path = image->file_path;
    } else {
        // For non-file formats, write to a temp file
        // This is a simplification — production code would handle RGB/base64 properly
        RAC_LOG_ERROR(LOG_CAT, "MetalRT VLM only supports FILE_PATH image format");
        return RAC_ERROR_VALIDATION_FAILED;
    }

    if (!image_path || image_path[0] == '\0') {
        return RAC_ERROR_NULL_POINTER;
    }

    struct MetalRTVisionOptions vopts = {};
    vopts.max_tokens = options ? options->max_tokens : 256;
    vopts.temperature = options ? options->temperature : 0.0f;
    vopts.top_k = 40;
    vopts.think = false;

    struct MetalRTVisionResult result = metalrt_vision_analyze(impl->handle, image_path, prompt, &vopts);

    out_result->text = result.text ? strdup(result.text) : nullptr;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->image_tokens = 0;  // MetalRT doesn't separate image token count
    out_result->completion_tokens = result.generated_tokens;
    out_result->total_tokens = result.prompt_tokens + result.generated_tokens;
    out_result->time_to_first_token_ms = static_cast<int64_t>(result.prefill_ms);
    out_result->image_encode_time_ms = static_cast<int64_t>(result.vision_encode_ms);
    out_result->total_time_ms = static_cast<int64_t>(
        result.vision_encode_ms + result.prefill_ms + result.decode_ms);
    out_result->tokens_per_second = static_cast<float>(result.tps);

    metalrt_vision_free_result(result);
    return RAC_SUCCESS;
}

// Stream adapter
struct VLMStreamCtx {
    rac_vlm_stream_callback_fn callback;
    void* user_data;
};

static bool vlm_stream_bridge(const char* piece, void* ctx) {
    auto* adapter = static_cast<VLMStreamCtx*>(ctx);
    if (!adapter || !adapter->callback) return false;
    return adapter->callback(piece, adapter->user_data) == RAC_TRUE;
}

rac_result_t rac_vlm_metalrt_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                             const char* prompt, const rac_vlm_options_t* options,
                                             rac_vlm_stream_callback_fn callback,
                                             void* user_data) {
    if (!handle || !image || !prompt || !callback) return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_vlm_metalrt_impl*>(handle);
    if (!impl->loaded) return RAC_ERROR_BACKEND_NOT_READY;

    if (image->format != RAC_VLM_IMAGE_FORMAT_FILE_PATH || !image->file_path) {
        RAC_LOG_ERROR(LOG_CAT, "MetalRT VLM only supports FILE_PATH image format");
        return RAC_ERROR_VALIDATION_FAILED;
    }

    struct MetalRTVisionOptions vopts = {};
    vopts.max_tokens = options ? options->max_tokens : 256;
    vopts.temperature = options ? options->temperature : 0.0f;
    vopts.top_k = 40;
    vopts.think = false;

    VLMStreamCtx ctx = {callback, user_data};
    struct MetalRTVisionResult result = metalrt_vision_analyze_stream(
        impl->handle, image->file_path, prompt, vlm_stream_bridge, &ctx, &vopts);

    metalrt_vision_free_result(result);
    return RAC_SUCCESS;
}

void rac_vlm_metalrt_reset(rac_handle_t handle) {
    if (!handle) return;
    auto* impl = static_cast<rac_vlm_metalrt_impl*>(handle);
    if (impl->handle) {
        metalrt_vision_reset(impl->handle);
    }
}

}  // extern "C"
