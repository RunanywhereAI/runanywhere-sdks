/**
 * @file rac_vlm_metalrt.h
 * @brief MetalRT VLM backend — internal header (Vision)
 */

#ifndef RAC_VLM_METALRT_H
#define RAC_VLM_METALRT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/vlm/rac_vlm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

rac_result_t rac_vlm_metalrt_create(const char* model_path, rac_handle_t* out_handle);
void rac_vlm_metalrt_destroy(rac_handle_t handle);

rac_result_t rac_vlm_metalrt_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                      const char* prompt, const rac_vlm_options_t* options,
                                      rac_vlm_result_t* out_result);

rac_result_t rac_vlm_metalrt_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                             const char* prompt, const rac_vlm_options_t* options,
                                             rac_vlm_stream_callback_fn callback,
                                             void* user_data);

void rac_vlm_metalrt_reset(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VLM_METALRT_H */
