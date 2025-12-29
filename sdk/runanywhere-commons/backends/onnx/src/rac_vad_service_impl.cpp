/**
 * @file rac_vad_service_impl.cpp
 * @brief ONNX Backend - Generic VAD Service Implementation
 *
 * Implements the generic VAD service API by delegating to ONNX functions.
 */

#include "rac_vad_onnx.h"

#include "rac/features/vad/rac_vad_service.h"

extern "C" {

rac_result_t rac_vad_create(rac_handle_t* out_handle) {
    return rac_vad_onnx_create(nullptr, nullptr, out_handle);
}

void rac_vad_destroy(rac_handle_t handle) {
    rac_vad_onnx_destroy(handle);
}

rac_result_t rac_vad_initialize(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_set_activity_callback(rac_handle_t handle,
                                           rac_vad_activity_callback_fn callback, void* user_data) {
    // ONNX VAD uses synchronous processing; callbacks not directly supported
    (void)handle;
    (void)callback;
    (void)user_data;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_set_audio_callback(rac_handle_t handle, rac_vad_audio_callback_fn callback,
                                        void* user_data) {
    (void)handle;
    (void)callback;
    (void)user_data;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_start(rac_handle_t handle) {
    return rac_vad_onnx_start(handle);
}

rac_result_t rac_vad_stop(rac_handle_t handle) {
    return rac_vad_onnx_stop(handle);
}

rac_result_t rac_vad_reset(rac_handle_t handle) {
    return rac_vad_onnx_reset(handle);
}

rac_result_t rac_vad_pause(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_resume(rac_handle_t handle) {
    (void)handle;
    return RAC_SUCCESS;
}

rac_result_t rac_vad_process_samples(rac_handle_t handle, const float* samples, size_t num_samples,
                                     rac_bool_t* out_is_speech) {
    return rac_vad_onnx_process(handle, samples, num_samples, out_is_speech);
}

rac_result_t rac_vad_set_energy_threshold(rac_handle_t handle, float threshold) {
    return rac_vad_onnx_set_threshold(handle, threshold);
}

rac_result_t rac_vad_get_info(rac_handle_t handle, rac_vad_info_t* out_info) {
    if (!handle || !out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_info->is_speech_active = rac_vad_onnx_is_speech_active(handle);
    out_info->sample_rate = 16000;
    out_info->energy_threshold = 0.5f;
    return RAC_SUCCESS;
}

}  // extern "C"
