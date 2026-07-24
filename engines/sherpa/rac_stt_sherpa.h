#ifndef RAC_STT_SHERPA_H
#define RAC_STT_SHERPA_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rac_stt_sherpa_model_type {
    RAC_STT_SHERPA_MODEL_WHISPER = 0,
    RAC_STT_SHERPA_MODEL_ZIPFORMER = 1,
    RAC_STT_SHERPA_MODEL_PARAFORMER = 2,
    RAC_STT_SHERPA_MODEL_NEMO_CTC = 3,
    RAC_STT_SHERPA_MODEL_TRANSDUCER = 4,
    RAC_STT_SHERPA_MODEL_CANARY = 5,
    RAC_STT_SHERPA_MODEL_AUTO = 99
} rac_stt_sherpa_model_type_t;

typedef struct rac_stt_sherpa_config {
    rac_stt_sherpa_model_type_t model_type;
    int32_t num_threads;
    rac_bool_t use_coreml;
} rac_stt_sherpa_config_t;

static const rac_stt_sherpa_config_t RAC_STT_SHERPA_CONFIG_DEFAULT = {
    .model_type = RAC_STT_SHERPA_MODEL_AUTO, .num_threads = 0, .use_coreml = RAC_TRUE};

rac_result_t rac_stt_sherpa_create(const char* model_path, const rac_stt_sherpa_config_t* config,
                                   rac_handle_t* out_handle);
rac_result_t rac_stt_sherpa_transcribe(rac_handle_t handle, const float* audio_samples,
                                       size_t num_samples, const rac_stt_options_t* options,
                                       rac_stt_result_t* out_result);
rac_bool_t rac_stt_sherpa_supports_streaming(rac_handle_t handle);
rac_bool_t rac_stt_sherpa_supports_persistent_streaming(rac_handle_t handle);
rac_result_t rac_stt_sherpa_create_stream(rac_handle_t handle, rac_handle_t* out_stream);
rac_result_t rac_stt_sherpa_create_stream_with_options(rac_handle_t handle,
                                                       const rac_stt_options_t* options,
                                                       rac_handle_t* out_stream);
rac_result_t rac_stt_sherpa_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                       const float* audio_samples, size_t num_samples,
                                       int sample_rate);
rac_result_t rac_stt_sherpa_feed_stream_audio_chunk(rac_handle_t handle, rac_handle_t stream,
                                                    const int16_t* samples, size_t count,
                                                    rac_stt_stream_callback_t callback,
                                                    void* user_data);
rac_bool_t rac_stt_sherpa_stream_is_ready(rac_handle_t handle, rac_handle_t stream);
rac_result_t rac_stt_sherpa_decode_stream(rac_handle_t handle, rac_handle_t stream,
                                          char** out_text);
void rac_stt_sherpa_input_finished(rac_handle_t handle, rac_handle_t stream);
rac_bool_t rac_stt_sherpa_is_endpoint(rac_handle_t handle, rac_handle_t stream);
void rac_stt_sherpa_destroy_stream(rac_handle_t handle, rac_handle_t stream);
void rac_stt_sherpa_destroy(rac_handle_t handle);
rac_result_t rac_stt_sherpa_get_languages(rac_handle_t handle, char** out_json);
rac_result_t rac_stt_sherpa_detect_language(rac_handle_t handle, const void* audio_data,
                                            size_t audio_size, const rac_stt_options_t* options,
                                            char** out_language);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_SHERPA_H */
