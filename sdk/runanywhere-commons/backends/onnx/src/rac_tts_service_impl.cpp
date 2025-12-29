/**
 * @file rac_tts_service_impl.cpp
 * @brief ONNX Backend - Generic TTS Service Implementation
 *
 * Implements the generic TTS service API by delegating to ONNX functions.
 */

#include "rac_tts_onnx.h"

#include <cstdlib>

#include "rac/features/tts/rac_tts_service.h"

extern "C" {

rac_result_t rac_tts_create(const char* model_path, rac_handle_t* out_handle) {
    return rac_tts_onnx_create(model_path, nullptr, out_handle);
}

void rac_tts_destroy(rac_handle_t handle) {
    rac_tts_onnx_destroy(handle);
}

rac_result_t rac_tts_initialize(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_tts_synthesize(rac_handle_t handle, const char* text,
                                const rac_tts_options_t* options, rac_tts_result_t* out_result) {
    return rac_tts_onnx_synthesize(handle, text, options, out_result);
}

rac_result_t rac_tts_synthesize_stream(rac_handle_t handle, const char* text,
                                       const rac_tts_options_t* options,
                                       rac_tts_stream_callback_t callback, void* user_data) {
    rac_tts_result_t result = {};
    rac_result_t status = rac_tts_onnx_synthesize(handle, text, options, &result);

    if (status == RAC_SUCCESS && callback) {
        callback(result.audio_data, result.audio_size, user_data);
    }

    return status;
}

rac_result_t rac_tts_stop(rac_handle_t handle) {
    rac_tts_onnx_stop(handle);
    return RAC_SUCCESS;
}

rac_result_t rac_tts_cleanup(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_tts_get_info(rac_handle_t handle, rac_tts_info_t* out_info) {
    if (!handle || !out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_info->is_ready = RAC_TRUE;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = nullptr;
    out_info->num_voices = 0;
    return RAC_SUCCESS;
}

}  // extern "C"
