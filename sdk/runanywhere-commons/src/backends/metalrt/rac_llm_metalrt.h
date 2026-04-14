/**
 * @file rac_llm_metalrt.h
 * @brief MetalRT LLM backend — internal header
 *
 * Wraps the MetalRT C API (metalrt_c_api.h) for LLM inference.
 */

#ifndef RAC_LLM_METALRT_H
#define RAC_LLM_METALRT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

rac_result_t rac_llm_metalrt_create(const char* model_path, rac_handle_t* out_handle);
void rac_llm_metalrt_destroy(rac_handle_t handle);
rac_bool_t rac_llm_metalrt_is_loaded(rac_handle_t handle);

rac_result_t rac_llm_metalrt_generate(rac_handle_t handle, const char* prompt,
                                       const rac_llm_options_t* options,
                                       rac_llm_result_t* out_result);

typedef rac_bool_t (*rac_llm_metalrt_stream_cb)(const char* token, rac_bool_t is_final,
                                                 void* user_data);

rac_result_t rac_llm_metalrt_generate_stream(rac_handle_t handle, const char* prompt,
                                              const rac_llm_options_t* options,
                                              rac_llm_metalrt_stream_cb callback,
                                              void* user_data);

rac_result_t rac_llm_metalrt_inject_system_prompt(rac_handle_t handle, const char* prompt);
rac_result_t rac_llm_metalrt_append_context(rac_handle_t handle, const char* text);
rac_result_t rac_llm_metalrt_generate_from_context(rac_handle_t handle, const char* query,
                                                    const rac_llm_options_t* options,
                                                    rac_llm_result_t* out_result);
rac_result_t rac_llm_metalrt_clear_context(rac_handle_t handle);
void rac_llm_metalrt_reset(rac_handle_t handle);

int rac_llm_metalrt_context_size(rac_handle_t handle);
const char* rac_llm_metalrt_model_name(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_METALRT_H */
