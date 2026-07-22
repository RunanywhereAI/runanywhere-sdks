/**
 * @file rac_diarization_service.h
 * @brief Standalone speaker-diarization engine service interface.
 */

#ifndef RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_SERVICE_H
#define RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_SERVICE_H

#include <stddef.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/diarization/rac_diarization_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Backend stream callback. Each result is the complete current session
 * snapshot and remains valid only for the duration of the callback.
 */
typedef void (*rac_diarization_stream_callback_t)(const rac_diarization_result_t* result,
                                                  void* user_data);

typedef struct rac_diarization_service_ops {
    rac_result_t (*initialize)(void* impl, const char* model_path);
    /**
     * Produce an offline result. Commons supplies a zero-initialized
     * out_result. Every returned pointer (segments, each speaker_id, and
     * model_id) MUST use a malloc/free-compatible allocator. Ownership of
     * success and partially-populated error results transfers to the caller;
     * either shape MUST be safe to pass to rac_diarization_result_free().
     */
    rac_result_t (*diarize)(void* impl, const float* samples, size_t sample_count,
                            const rac_diarization_options_t* options,
                            rac_diarization_result_t* out_result);
    /**
     * The three stream operations are an all-or-none capability group. A
     * successful create MUST publish a non-NULL stream handle.
     */
    rac_result_t (*stream_create)(void* impl, const rac_diarization_options_t* options,
                                  rac_handle_t* out_stream_handle);
    /**
     * Feed one serialized chunk. Commons never calls this concurrently for
     * the same stream. The backend may dispatch callbacks on worker threads,
     * but every callback caused by this invocation MUST be quiescent before
     * the invocation returns. samples == NULL and sample_count == 0 requests
     * a final flush. The provider may synchronously refine the snapshot more
     * than once; Commons retains the last valid snapshot and emits one FINAL
     * only after this invocation returns.
     */
    rac_result_t (*stream_feed_audio_chunk)(void* impl, rac_handle_t stream_handle,
                                            const float* samples, size_t sample_count,
                                            rac_diarization_stream_callback_t callback,
                                            void* user_data);
    /**
     * Destroy the persistent stream. Before returning, the backend MUST join
     * or otherwise quiesce every callback for this stream and MUST NOT access
     * any previously supplied callback or user_data afterward.
     */
    rac_result_t (*stream_destroy)(void* impl, rac_handle_t stream_handle);
    rac_result_t (*cleanup)(void* impl);
    void (*destroy)(void* impl);
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_diarization_service_ops_t;

typedef struct rac_diarization_service {
    const rac_diarization_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_diarization_service_t;

RAC_API rac_result_t rac_diarization_create(const char* model_id, rac_handle_t* out_handle);
RAC_API rac_result_t rac_diarization_initialize(rac_handle_t handle, const char* model_path);
/**
 * out_result is reset before provider dispatch. On success or error, release
 * any provider-owned fields with rac_diarization_result_free(); the free
 * helper is NULL-safe, partial-result-safe under the provider contract above,
 * idempotent after zeroing, and zeros the struct before returning.
 */
RAC_API rac_result_t rac_diarization_diarize(rac_handle_t handle, const float* samples,
                                             size_t sample_count,
                                             const rac_diarization_options_t* options,
                                             rac_diarization_result_t* out_result);
RAC_API rac_result_t rac_diarization_stream_create(rac_handle_t handle,
                                                   const rac_diarization_options_t* options,
                                                   rac_handle_t* out_stream_handle);
RAC_API rac_result_t rac_diarization_stream_feed_audio_chunk(
    rac_handle_t handle, rac_handle_t stream_handle, const float* samples, size_t sample_count,
    rac_diarization_stream_callback_t callback, void* user_data);
RAC_API rac_result_t rac_diarization_stream_destroy(rac_handle_t handle,
                                                    rac_handle_t stream_handle);
RAC_API rac_result_t rac_diarization_cleanup(rac_handle_t handle);
RAC_API void rac_diarization_destroy(rac_handle_t handle);

/** Offline SDK-facing ABI over runanywhere.v1.DiarizationRequest/Result. */
RAC_API rac_result_t rac_diarization_diarize_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                             size_t request_proto_size,
                                                             rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_SERVICE_H */
