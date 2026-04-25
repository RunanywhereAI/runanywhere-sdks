/**
 * @file rac_onnx_compat.cpp
 * @brief Legacy rac_*_onnx_* speech symbols re-exported by Sherpa.
 *
 * Sherpa owns the actual STT / TTS / VAD / wakeword implementation. These
 * wrappers keep older SDK binaries that still call the ONNX-named speech ABI
 * working without leaving speech shims inside engines/onnx.
 */

#include "rac_stt_sherpa.h"
#include "rac_tts_sherpa.h"
#include "rac_vad_sherpa.h"

extern "C" {

rac_result_t rac_stt_onnx_create(const char* model_path,
                                 const rac_stt_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    return rac_stt_sherpa_create(model_path, config, out_handle);
}

rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples,
                                     size_t num_samples, const rac_stt_options_t* options,
                                     rac_stt_result_t* out_result) {
    return rac_stt_sherpa_transcribe(handle, audio_samples, num_samples, options, out_result);
}

rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle) {
    return rac_stt_sherpa_supports_streaming(handle);
}

rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream) {
    return rac_stt_sherpa_create_stream(handle, out_stream);
}

rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                     const float* audio_samples, size_t num_samples) {
    return rac_stt_sherpa_feed_audio(handle, stream, audio_samples, num_samples);
}

rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream) {
    return rac_stt_sherpa_stream_is_ready(handle, stream);
}

rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream,
                                        char** out_text) {
    return rac_stt_sherpa_decode_stream(handle, stream, out_text);
}

void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream) {
    rac_stt_sherpa_input_finished(handle, stream);
}

rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream) {
    return rac_stt_sherpa_is_endpoint(handle, stream);
}

void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream) {
    rac_stt_sherpa_destroy_stream(handle, stream);
}

void rac_stt_onnx_destroy(rac_handle_t handle) {
    rac_stt_sherpa_destroy(handle);
}

rac_result_t rac_stt_onnx_get_languages(rac_handle_t handle, char** out_json) {
    return rac_stt_sherpa_get_languages(handle, out_json);
}

rac_result_t rac_stt_onnx_detect_language(rac_handle_t handle, const void* audio_data,
                                          size_t audio_size,
                                          const rac_stt_options_t* options,
                                          char** out_language) {
    return rac_stt_sherpa_detect_language(handle, audio_data, audio_size, options, out_language);
}

rac_result_t rac_tts_onnx_create(const char* model_path,
                                 const rac_tts_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    return rac_tts_sherpa_create(model_path, config, out_handle);
}

rac_result_t rac_tts_onnx_synthesize(rac_handle_t handle, const char* text,
                                     const rac_tts_options_t* options,
                                     rac_tts_result_t* out_result) {
    return rac_tts_sherpa_synthesize(handle, text, options, out_result);
}

rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices,
                                     size_t* out_count) {
    return rac_tts_sherpa_get_voices(handle, out_voices, out_count);
}

rac_result_t rac_tts_onnx_get_languages(rac_handle_t handle, char** out_json) {
    return rac_tts_sherpa_get_languages(handle, out_json);
}

void rac_tts_onnx_stop(rac_handle_t handle) {
    rac_tts_sherpa_stop(handle);
}

void rac_tts_onnx_destroy(rac_handle_t handle) {
    rac_tts_sherpa_destroy(handle);
}

rac_result_t rac_vad_onnx_create(const char* model_path,
                                 const rac_vad_onnx_config_t* config,
                                 rac_handle_t* out_handle) {
    return rac_vad_sherpa_create(model_path, config, out_handle);
}

rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples,
                                  size_t num_samples, rac_bool_t* out_is_speech) {
    return rac_vad_sherpa_process(handle, samples, num_samples, out_is_speech);
}

rac_result_t rac_vad_onnx_start(rac_handle_t handle) {
    return rac_vad_sherpa_start(handle);
}

rac_result_t rac_vad_onnx_stop(rac_handle_t handle) {
    return rac_vad_sherpa_stop(handle);
}

rac_result_t rac_vad_onnx_reset(rac_handle_t handle) {
    return rac_vad_sherpa_reset(handle);
}

rac_result_t rac_vad_onnx_set_threshold(rac_handle_t handle, float threshold) {
    return rac_vad_sherpa_set_threshold(handle, threshold);
}

rac_bool_t rac_vad_onnx_is_speech_active(rac_handle_t handle) {
    return rac_vad_sherpa_is_speech_active(handle);
}

void rac_vad_onnx_destroy(rac_handle_t handle) {
    rac_vad_sherpa_destroy(handle);
}

}  // extern "C"
