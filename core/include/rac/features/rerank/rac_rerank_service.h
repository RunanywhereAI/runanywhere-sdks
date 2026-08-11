/** @file rac_rerank_service.h @brief Cross-encoder reranking engine service interface. */

#ifndef RAC_FEATURES_RERANK_RAC_RERANK_SERVICE_H
#define RAC_FEATURES_RERANK_RAC_RERANK_SERVICE_H

#include <stddef.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/rerank/rac_rerank_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_rerank_service_ops {
    rac_result_t (*initialize)(void* impl, const char* model_path);
    /**
     * Score every candidate against the query and produce a result ranked by
     * descending relevance. Every pointer returned in out_result MUST use a
     * malloc/free-compatible allocator and remains caller-owned on both success
     * and partial failure.
     */
    rac_result_t (*rerank)(void* impl, const char* query,
                           const rac_rerank_candidate_t* candidates, size_t candidate_count,
                           const rac_rerank_options_t* options, rac_rerank_result_t* out_result);
    rac_result_t (*cleanup)(void* impl);
    void (*destroy)(void* impl);
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_rerank_service_ops_t;

typedef struct rac_rerank_service {
    const rac_rerank_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_rerank_service_t;

RAC_API rac_result_t rac_rerank_create(const char* model_id, rac_handle_t* out_handle);
RAC_API rac_result_t rac_rerank_initialize(rac_handle_t handle, const char* model_path);
RAC_API rac_result_t rac_rerank_rerank(rac_handle_t handle, const char* query,
                                       const rac_rerank_candidate_t* candidates,
                                       size_t candidate_count,
                                       const rac_rerank_options_t* options,
                                       rac_rerank_result_t* out_result);
RAC_API rac_result_t rac_rerank_cleanup(rac_handle_t handle);
RAC_API void rac_rerank_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_RERANK_RAC_RERANK_SERVICE_H */
