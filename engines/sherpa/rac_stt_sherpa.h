#ifndef RAC_STT_SHERPA_H
#define RAC_STT_SHERPA_H

#include "rac/backends/rac_stt_onnx.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef rac_stt_onnx_model_type_t rac_stt_sherpa_model_type_t;
typedef rac_stt_onnx_config_t rac_stt_sherpa_config_t;

#define RAC_STT_SHERPA_MODEL_WHISPER RAC_STT_ONNX_MODEL_WHISPER
#define RAC_STT_SHERPA_MODEL_ZIPFORMER RAC_STT_ONNX_MODEL_ZIPFORMER
#define RAC_STT_SHERPA_MODEL_PARAFORMER RAC_STT_ONNX_MODEL_PARAFORMER
#define RAC_STT_SHERPA_MODEL_NEMO_CTC RAC_STT_ONNX_MODEL_NEMO_CTC
#define RAC_STT_SHERPA_MODEL_AUTO RAC_STT_ONNX_MODEL_AUTO

rac_result_t rac_stt_sherpa_create(const char *model_path,
                                   const rac_stt_sherpa_config_t *config,
                                   rac_handle_t *out_handle);
rac_result_t rac_stt_sherpa_transcribe(rac_handle_t handle,
                                       const float *audio_samples,
                                       size_t num_samples,
                                       const rac_stt_options_t *options,
                                       rac_stt_result_t *out_result);
rac_bool_t rac_stt_sherpa_supports_streaming(rac_handle_t handle);
rac_result_t rac_stt_sherpa_create_stream(rac_handle_t handle,
                                          rac_handle_t *out_stream);
rac_result_t rac_stt_sherpa_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                       const float *audio_samples,
                                       size_t num_samples, int sample_rate);
rac_bool_t rac_stt_sherpa_stream_is_ready(rac_handle_t handle,
                                          rac_handle_t stream);
rac_result_t rac_stt_sherpa_decode_stream(rac_handle_t handle,
                                          rac_handle_t stream, char **out_text);
void rac_stt_sherpa_input_finished(rac_handle_t handle, rac_handle_t stream);
rac_bool_t rac_stt_sherpa_is_endpoint(rac_handle_t handle, rac_handle_t stream);
void rac_stt_sherpa_destroy_stream(rac_handle_t handle, rac_handle_t stream);
void rac_stt_sherpa_destroy(rac_handle_t handle);
rac_result_t rac_stt_sherpa_get_languages(rac_handle_t handle, char **out_json);
rac_result_t rac_stt_sherpa_detect_language(rac_handle_t handle,
                                            const void *audio_data,
                                            size_t audio_size,
                                            const rac_stt_options_t *options,
                                            char **out_language);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_SHERPA_H */
