#ifndef RAC_TTS_SHERPA_H
#define RAC_TTS_SHERPA_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_tts_sherpa_config {
    int32_t num_threads;
    rac_bool_t use_coreml;
    int32_t sample_rate;
} rac_tts_sherpa_config_t;

static const rac_tts_sherpa_config_t RAC_TTS_SHERPA_CONFIG_DEFAULT = {
    .num_threads = 0, .use_coreml = RAC_TRUE, .sample_rate = 22050};

rac_result_t rac_tts_sherpa_create(const char* model_path, const rac_tts_sherpa_config_t* config,
                                   rac_handle_t* out_handle);
rac_result_t rac_tts_sherpa_synthesize(rac_handle_t handle, const char* text,
                                       const rac_tts_options_t* options,
                                       rac_tts_result_t* out_result);
rac_result_t rac_tts_sherpa_get_voices(rac_handle_t handle, char*** out_voices, size_t* out_count);

/**
 * @brief Populate `rac_tts_info_t` for the canonical lifecycle voice-list ABI.
 *
 * Mirrors the per-handle `get_voices()` enumeration into
 * `out_info->available_voices` + `num_voices`. The returned pointer array is
 * owned by the handle and remains valid until the next call into
 * `rac_tts_sherpa_get_info` on the same handle, or until the handle is
 * destroyed via `rac_tts_sherpa_destroy`. Callers MUST NOT free the pointers.
 */
rac_result_t rac_tts_sherpa_get_info(rac_handle_t handle, rac_tts_info_t* out_info);
void rac_tts_sherpa_stop(rac_handle_t handle);
void rac_tts_sherpa_destroy(rac_handle_t handle);
rac_result_t rac_tts_sherpa_get_languages(rac_handle_t handle, char** out_json);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_SHERPA_H */
