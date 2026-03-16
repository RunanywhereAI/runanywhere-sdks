/**
 * @file rac_tts_metalrt.h
 * @brief MetalRT TTS backend — internal header (Kokoro)
 */

#ifndef RAC_TTS_METALRT_H
#define RAC_TTS_METALRT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_types.h"

#ifdef __cplusplus
extern "C" {
#endif

rac_result_t rac_tts_metalrt_create(const char* model_path, rac_handle_t* out_handle);
void rac_tts_metalrt_destroy(rac_handle_t handle);

rac_result_t rac_tts_metalrt_synthesize(rac_handle_t handle, const char* text,
                                         const rac_tts_options_t* options,
                                         rac_tts_result_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_METALRT_H */
