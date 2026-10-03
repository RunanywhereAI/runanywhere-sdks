/** @file rac_decision_service.h @brief Decision-model engine service interface. */

#ifndef RAC_FEATURES_DECISION_RAC_DECISION_SERVICE_H
#define RAC_FEATURES_DECISION_RAC_DECISION_SERVICE_H

#include <stddef.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/decision/rac_decision_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_decision_service_ops {
    rac_result_t (*initialize)(void* impl, const char* model_path);
    /**
     * Score every question against the state and produce one answer per
     * question, in request order. Every pointer returned in out_result MUST use
     * a malloc/free-compatible allocator and remains caller-owned on both
     * success and partial failure.
     */
    rac_result_t (*decide)(void* impl, const char* state,
                           const rac_decision_question_t* questions, size_t question_count,
                           const rac_decision_options_t* options, rac_decision_result_t* out_result);
    rac_result_t (*cleanup)(void* impl);
    void (*destroy)(void* impl);
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_decision_service_ops_t;

typedef struct rac_decision_service {
    const rac_decision_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_decision_service_t;

RAC_API rac_result_t rac_decision_create(const char* model_id, rac_handle_t* out_handle);
RAC_API rac_result_t rac_decision_initialize(rac_handle_t handle, const char* model_path);
RAC_API rac_result_t rac_decision_decide(rac_handle_t handle, const char* state,
                                         const rac_decision_question_t* questions,
                                         size_t question_count,
                                         const rac_decision_options_t* options,
                                         rac_decision_result_t* out_result);
RAC_API rac_result_t rac_decision_cleanup(rac_handle_t handle);
RAC_API void rac_decision_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_DECISION_RAC_DECISION_SERVICE_H */