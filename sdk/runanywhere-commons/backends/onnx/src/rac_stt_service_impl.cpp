/**
 * @file rac_stt_service_impl.cpp
 * @brief ONNX Backend - Generic STT Service Implementation
 *
 * Implements the generic STT service API by delegating to ONNX functions.
 */

#include "rac/features/stt/rac_stt_service.h"
#include "rac_stt_onnx.h"

#include <cstdlib>

extern "C" {

rac_result_t rac_stt_create(const char* model_path, rac_handle_t* out_handle) {
    return rac_stt_onnx_create(model_path, nullptr, out_handle);
}

void rac_stt_destroy(rac_handle_t handle) {
    rac_stt_onnx_destroy(handle);
}

rac_result_t rac_stt_initialize(rac_handle_t handle, const char* model_path) {
    // ONNX handles initialization during create
    (void)handle;
    (void)model_path;
    return RAC_SUCCESS;
}

rac_result_t rac_stt_transcribe(rac_handle_t handle, const void* audio_data,
                                size_t audio_size, const rac_stt_options_t* options,
                                rac_stt_result_t* out_result) {
    const float* samples = static_cast<const float*>(audio_data);
    size_t num_samples = audio_size / sizeof(float);
    return rac_stt_onnx_transcribe(handle, samples, num_samples, options, out_result);
}

rac_result_t rac_stt_transcribe_stream(rac_handle_t handle, const void* audio_data,
                                       size_t audio_size, const rac_stt_options_t* options,
                                       rac_stt_stream_callback_t callback, void* user_data) {
    rac_handle_t stream = nullptr;
    rac_result_t result = rac_stt_onnx_create_stream(handle, &stream);
    if (result != RAC_SUCCESS) {
        return result;
    }

    const float* samples = static_cast<const float*>(audio_data);
    size_t num_samples = audio_size / sizeof(float);

    result = rac_stt_onnx_feed_audio(handle, stream, samples, num_samples);
    if (result != RAC_SUCCESS) {
        rac_stt_onnx_destroy_stream(handle, stream);
        return result;
    }

    rac_stt_onnx_input_finished(handle, stream);

    char* text = nullptr;
    result = rac_stt_onnx_decode_stream(handle, stream, &text);
    if (result == RAC_SUCCESS && callback && text) {
        callback(text, RAC_TRUE, user_data);
    }

    rac_stt_onnx_destroy_stream(handle, stream);
    if (text) free(text);

    (void)options;
    return result;
}

rac_result_t rac_stt_cleanup(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_stt_get_info(rac_handle_t handle, rac_stt_info_t* out_info) {
    if (!handle || !out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_info->is_ready = RAC_TRUE;
    out_info->supports_streaming = rac_stt_onnx_supports_streaming(handle);
    out_info->current_model = nullptr;
    return RAC_SUCCESS;
}

}  // extern "C"
