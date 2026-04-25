#ifndef RAC_TTS_SHERPA_H
#define RAC_TTS_SHERPA_H

#include "rac/backends/rac_tts_onnx.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(RAC_SHERPA_BUILDING)
#if defined(_WIN32)
#define RAC_SHERPA_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_SHERPA_API __attribute__((visibility("default")))
#else
#define RAC_SHERPA_API
#endif
#else
#define RAC_SHERPA_API
#endif

typedef rac_tts_onnx_config_t rac_tts_sherpa_config_t;

RAC_SHERPA_API rac_result_t rac_tts_sherpa_create(const char* model_path,
                                                  const rac_tts_sherpa_config_t* config,
                                                  rac_handle_t* out_handle);
RAC_SHERPA_API rac_result_t rac_tts_sherpa_synthesize(rac_handle_t handle, const char* text,
                                                      const rac_tts_options_t* options,
                                                      rac_tts_result_t* out_result);
RAC_SHERPA_API rac_result_t rac_tts_sherpa_get_voices(rac_handle_t handle, char*** out_voices,
                                                      size_t* out_count);
RAC_SHERPA_API void rac_tts_sherpa_stop(rac_handle_t handle);
RAC_SHERPA_API void rac_tts_sherpa_destroy(rac_handle_t handle);
RAC_SHERPA_API rac_result_t rac_tts_sherpa_get_languages(rac_handle_t handle, char** out_json);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_SHERPA_H */
