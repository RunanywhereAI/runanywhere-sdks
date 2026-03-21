/**
 * @file rac_stt_metalrt.h
 * @brief MetalRT STT backend — internal header (Whisper)
 */

#ifndef RAC_STT_METALRT_H
#define RAC_STT_METALRT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_types.h"

#ifdef __cplusplus
extern "C" {
#endif

rac_result_t rac_stt_metalrt_create(const char* model_path, rac_handle_t* out_handle);
void rac_stt_metalrt_destroy(rac_handle_t handle);

rac_result_t rac_stt_metalrt_transcribe(rac_handle_t handle, const void* audio_data,
                                         size_t audio_size, const rac_stt_options_t* options,
                                         rac_stt_result_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_METALRT_H */
