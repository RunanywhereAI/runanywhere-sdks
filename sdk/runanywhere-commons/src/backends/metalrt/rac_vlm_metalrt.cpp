/**
 * @file rac_vlm_metalrt.cpp
 * @brief MetalRT VLM backend — wraps metalrt_vision_* for vision-language inference
 */

#include "rac_vlm_metalrt.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "metalrt_c_api.h"

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "VLM.MetalRT";

// Expand 3-byte RGB to 4-byte RGBA (alpha=0xFF) for MetalRT's pixel API.
static std::vector<uint8_t> rgb_to_rgba(const uint8_t* rgb, uint32_t w, uint32_t h) {
    size_t n_pixels = (size_t)w * h;
    std::vector<uint8_t> rgba(n_pixels * 4);
    for (size_t i = 0; i < n_pixels; i++) {
        rgba[i * 4 + 0] = rgb[i * 3 + 0];
        rgba[i * 4 + 1] = rgb[i * 3 + 1];
        rgba[i * 4 + 2] = rgb[i * 3 + 2];
        rgba[i * 4 + 3] = 0xFF;
    }
    return rgba;
}

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

    struct MetalRTVisionOptions vopts = {};
    vopts.max_tokens = options ? options->max_tokens : 256;
    vopts.temperature = options ? options->temperature : 0.0f;
    vopts.top_k = 40;
    vopts.think = false;

    struct MetalRTVisionResult result = {};

    if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
        result = metalrt_vision_analyze(impl->handle, image->file_path, prompt, &vopts);
    } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
        auto rgba = rgb_to_rgba(image->pixel_data, image->width, image->height);
        result = metalrt_vision_analyze_pixels(impl->handle, rgba.data(),
                                                (int)image->width, (int)image->height,
                                                prompt, &vopts);
    } else {
        RAC_LOG_ERROR(LOG_CAT, "Unsupported image format: %d", image->format);
        return RAC_ERROR_VALIDATION_FAILED;
    }

    out_result->text = result.text ? strdup(result.text) : nullptr;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->image_tokens = 0;
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

    struct MetalRTVisionOptions vopts = {};
    vopts.max_tokens = options ? options->max_tokens : 256;
    vopts.temperature = options ? options->temperature : 0.0f;
    vopts.top_k = 40;
    vopts.think = false;

    VLMStreamCtx ctx = {callback, user_data};
    struct MetalRTVisionResult result = {};

    if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
        result = metalrt_vision_analyze_stream(
            impl->handle, image->file_path, prompt, vlm_stream_bridge, &ctx, &vopts);
    } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
        auto rgba = rgb_to_rgba(image->pixel_data, image->width, image->height);
        result = metalrt_vision_analyze_pixels_stream(
            impl->handle, rgba.data(), (int)image->width, (int)image->height,
            prompt, vlm_stream_bridge, &ctx, &vopts);
    } else {
        RAC_LOG_ERROR(LOG_CAT, "Unsupported image format for streaming: %d", image->format);
        return RAC_ERROR_VALIDATION_FAILED;
    }

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
