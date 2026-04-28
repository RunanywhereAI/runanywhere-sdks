/**
 * @file rac_vad_routing.h
 * @brief Minimal VAD service vtable for hybrid-router dispatch.
 *
 * The existing rac_vad_* C API is handle-based (callback-driven, streaming).
 * For routing, the router needs a synchronous request/response shape: take a
 * frame of samples, return a speech/no-speech decision plus a confidence
 * signal. This header defines a small vtable that backend adapters implement
 * to plug into the hybrid router.
 *
 * Adapter implementations for energy_vad / onnx_vad land in a follow-up PR.
 */

#ifndef RAC_VAD_ROUTING_H
#define RAC_VAD_ROUTING_H

#include <stdbool.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Per-call VAD result. confidence may be NaN when the backend doesn't expose
 * a probability signal — the router treats NaN as "trusted, no cascade".
 */
typedef struct rac_vad_routed_result {
    rac_bool_t is_speech;
    float      confidence;
} rac_vad_routed_result_t;

typedef struct rac_vad_routing_ops {
    /**
     * Process one frame and produce a decision + confidence.
     * @param impl       Backend-specific handle.
     * @param samples    Float PCM samples.
     * @param num_samples Length of samples.
     * @param out        Filled on success.
     */
    rac_result_t (*process)(void* impl, const float* samples, size_t num_samples,
                            rac_vad_routed_result_t* out);
    void (*destroy)(void* impl);
} rac_vad_routing_ops_t;

typedef struct rac_vad_routing_service {
    const rac_vad_routing_ops_t* ops;
    void*                        impl;
    const char*                  model_id;  // optional, non-owning
} rac_vad_routing_service_t;

#ifdef __cplusplus
}
#endif

#endif  // RAC_VAD_ROUTING_H
