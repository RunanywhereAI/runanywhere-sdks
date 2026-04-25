/**
 * @file rac_onnx.cpp
 * @brief Legacy ONNX speech C API compatibility shims.
 *
 * Sherpa-ONNX speech primitives moved to engines/sherpa. These exported
 * rac_*_onnx_* symbols are kept temporarily for downstream SDKs that still
 * call the old names; they forward to the Sherpa implementation when the
 * Sherpa backend target is built.
 */

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

#include "rac/core/rac_error.h"

#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
#include "rac_stt_sherpa.h"
#include "rac_tts_sherpa.h"
#include "rac_vad_sherpa.h"
#endif

extern "C" {

rac_result_t rac_stt_onnx_create(const char* model_path, const rac_stt_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_create(model_path, config, out_handle);
#else
    (void)model_path;
    (void)config;
    if (out_handle) *out_handle = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples,
                                     size_t num_samples, const rac_stt_options_t* options,
                                     rac_stt_result_t* out_result) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_transcribe(handle, audio_samples, num_samples, options, out_result);
#else
    (void)handle; (void)audio_samples; (void)num_samples; (void)options; (void)out_result;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_supports_streaming(handle);
#else
    (void)handle;
    return RAC_FALSE;
#endif
}

rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_create_stream(handle, out_stream);
#else
    (void)handle;
    if (out_stream) *out_stream = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                     const float* audio_samples, size_t num_samples) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_feed_audio(handle, stream, audio_samples, num_samples);
#else
    (void)handle; (void)stream; (void)audio_samples; (void)num_samples;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_stream_is_ready(handle, stream);
#else
    (void)handle; (void)stream;
    return RAC_FALSE;
#endif
}

rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream, char** out_text) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_decode_stream(handle, stream, out_text);
#else
    (void)handle; (void)stream;
    if (out_text) *out_text = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    rac_stt_sherpa_input_finished(handle, stream);
#else
    (void)handle; (void)stream;
#endif
}

rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_is_endpoint(handle, stream);
#else
    (void)handle; (void)stream;
    return RAC_FALSE;
#endif
}

void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    rac_stt_sherpa_destroy_stream(handle, stream);
#else
    (void)handle; (void)stream;
#endif
}

void rac_stt_onnx_destroy(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    rac_stt_sherpa_destroy(handle);
#else
    (void)handle;
#endif
}

rac_result_t rac_stt_onnx_get_languages(rac_handle_t handle, char** out_json) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_get_languages(handle, out_json);
#else
    (void)handle;
    if (out_json) *out_json = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_stt_onnx_detect_language(rac_handle_t handle, const void* audio_data,
                                          size_t audio_size, const rac_stt_options_t* options,
                                          char** out_language) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_stt_sherpa_detect_language(handle, audio_data, audio_size, options, out_language);
#else
    (void)handle; (void)audio_data; (void)audio_size; (void)options;
    if (out_language) *out_language = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_tts_onnx_create(const char* model_path, const rac_tts_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_tts_sherpa_create(model_path, config, out_handle);
#else
    (void)model_path; (void)config;
    if (out_handle) *out_handle = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_tts_onnx_synthesize(rac_handle_t handle, const char* text,
                                     const rac_tts_options_t* options,
                                     rac_tts_result_t* out_result) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_tts_sherpa_synthesize(handle, text, options, out_result);
#else
    (void)handle; (void)text; (void)options; (void)out_result;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices, size_t* out_count) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_tts_sherpa_get_voices(handle, out_voices, out_count);
#else
    (void)handle;
    if (out_voices) *out_voices = nullptr;
    if (out_count) *out_count = 0;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_tts_onnx_get_languages(rac_handle_t handle, char** out_json) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_tts_sherpa_get_languages(handle, out_json);
#else
    (void)handle;
    if (out_json) *out_json = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

void rac_tts_onnx_stop(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    rac_tts_sherpa_stop(handle);
#else
    (void)handle;
#endif
}

void rac_tts_onnx_destroy(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    rac_tts_sherpa_destroy(handle);
#else
    (void)handle;
#endif
}

rac_result_t rac_vad_onnx_create(const char* model_path, const rac_vad_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_vad_sherpa_create(model_path, config, out_handle);
#else
    (void)model_path; (void)config;
    if (out_handle) *out_handle = nullptr;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples, size_t num_samples,
                                  rac_bool_t* out_is_speech) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_vad_sherpa_process(handle, samples, num_samples, out_is_speech);
#else
    (void)handle; (void)samples; (void)num_samples; (void)out_is_speech;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_vad_onnx_start(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_vad_sherpa_start(handle);
#else
    (void)handle;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_vad_onnx_stop(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_vad_sherpa_stop(handle);
#else
    (void)handle;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_vad_onnx_reset(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_vad_sherpa_reset(handle);
#else
    (void)handle;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_vad_onnx_set_threshold(rac_handle_t handle, float threshold) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_vad_sherpa_set_threshold(handle, threshold);
#else
    (void)handle; (void)threshold;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_bool_t rac_vad_onnx_is_speech_active(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    return rac_vad_sherpa_is_speech_active(handle);
#else
    (void)handle;
    return RAC_FALSE;
#endif
}

void rac_vad_onnx_destroy(rac_handle_t handle) {
#if defined(RAC_ONNX_SHERPA_COMPAT) && RAC_ONNX_SHERPA_COMPAT
    rac_vad_sherpa_destroy(handle);
#else
    (void)handle;
#endif
}

}  // extern "C"
