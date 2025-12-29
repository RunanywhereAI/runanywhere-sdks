/**
 * @file rac_stt_service_impl.cpp
 * @brief ONNX Backend - Generic STT Service Implementation
 *
 * Implements the generic STT service API by delegating to ONNX functions.
 */

#include "rac/features/stt/rac_stt_service.h"
#include "rac_stt_onnx.h"

#include <cstdint>
#include <cstdlib>
#include <vector>

// =============================================================================
// AUDIO FORMAT CONVERSION
// =============================================================================

/**
 * Convert Int16 PCM audio to Float32 normalized to [-1.0, 1.0].
 * This is needed because Swift sends Int16 audio but Sherpa-ONNX expects Float32.
 *
 * @param int16_data Raw Int16 PCM audio bytes
 * @param byte_count Number of bytes (not samples!)
 * @return Vector of Float32 samples normalized to [-1.0, 1.0]
 */
static std::vector<float> convert_int16_to_float32(const void* int16_data, size_t byte_count) {
    const int16_t* samples = static_cast<const int16_t*>(int16_data);
    size_t num_samples = byte_count / sizeof(int16_t);

    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        // Normalize Int16 [-32768, 32767] to Float32 [-1.0, 1.0]
        float_samples[i] = static_cast<float>(samples[i]) / 32768.0f;
    }

    return float_samples;
}

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
    // Convert Int16 PCM to Float32 (Swift sends Int16, Sherpa-ONNX expects Float32)
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);

    return rac_stt_onnx_transcribe(handle, float_samples.data(), float_samples.size(), options,
                                   out_result);
}

rac_result_t rac_stt_transcribe_stream(rac_handle_t handle, const void* audio_data,
                                       size_t audio_size, const rac_stt_options_t* options,
                                       rac_stt_stream_callback_t callback, void* user_data) {
    rac_handle_t stream = nullptr;
    rac_result_t result = rac_stt_onnx_create_stream(handle, &stream);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // Convert Int16 PCM to Float32 (Swift sends Int16, Sherpa-ONNX expects Float32)
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);

    result = rac_stt_onnx_feed_audio(handle, stream, float_samples.data(), float_samples.size());
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
