/**
 * @file rac_model_assignment.h
 * @brief Model Assignment Manager - Fetches models assigned to device from backend
 */

#ifndef RAC_MODEL_ASSIGNMENT_H
#define RAC_MODEL_ASSIGNMENT_H

#include "rac_types.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CALLBACK TYPES
// =============================================================================

typedef struct rac_assignment_http_response {
    rac_result_t result;
    int32_t status_code;
    const char* response_body;
    size_t response_length;
    const char* error_message;
} rac_assignment_http_response_t;

typedef struct rac_assignment_device_info {
    const char* device_type;
    const char* platform;
} rac_assignment_device_info_t;

typedef rac_result_t (*rac_assignment_http_get_fn)(const char* endpoint,
                                                    rac_bool_t requires_auth,
                                                    rac_assignment_http_response_t* out_response,
                                                    void* user_data);

typedef void (*rac_assignment_get_device_info_fn)(rac_assignment_device_info_t* out_info,
                                                   void* user_data);

typedef struct rac_assignment_callbacks {
    rac_assignment_http_get_fn http_get;
    rac_assignment_get_device_info_fn get_device_info;
    void* user_data;
} rac_assignment_callbacks_t;

// =============================================================================
// MODEL ASSIGNMENT API
// =============================================================================

RAC_API rac_result_t rac_model_assignment_set_callbacks(const rac_assignment_callbacks_t* callbacks);

RAC_API rac_result_t rac_model_assignment_fetch(rac_bool_t force_refresh,
                                                 rac_model_info_t*** out_models,
                                                 size_t* out_count);

RAC_API rac_result_t rac_model_assignment_get_by_framework(rac_inference_framework_t framework,
                                                            rac_model_info_t*** out_models,
                                                            size_t* out_count);

RAC_API rac_result_t rac_model_assignment_get_by_category(rac_model_category_t category,
                                                           rac_model_info_t*** out_models,
                                                           size_t* out_count);

RAC_API void rac_model_assignment_clear_cache(void);

RAC_API void rac_model_assignment_set_cache_timeout(uint32_t timeout_seconds);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_ASSIGNMENT_H */
