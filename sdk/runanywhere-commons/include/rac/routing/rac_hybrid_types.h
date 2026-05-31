/**
 * @file rac_hybrid_types.h
 * @brief RunAnywhere Commons - Hybrid router shared types.
 *
 * C mirrors of the messages declared in idl/hybrid_router.proto. The router
 * uses a single capability-agnostic set of filter / cascade / rank types;
 * per-capability handles (rac_stt_hybrid_router.h, etc.) wrap these in a
 * typed public API.
 *
 * All enum values are explicit and match the proto wire numbers — Kotlin /
 * Swift / RN bindings pass these as int32 across the FFI and any reorder
 * would silently break them.
 */

#ifndef RAC_HYBRID_TYPES_H
#define RAC_HYBRID_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Capability dispatched by a hybrid router instance.
 */
typedef enum rac_hybrid_capability {
    RAC_HYBRID_CAPABILITY_UNSPECIFIED = 0,
    RAC_HYBRID_CAPABILITY_LLM         = 1,
    RAC_HYBRID_CAPABILITY_VLM         = 2,
    RAC_HYBRID_CAPABILITY_STT         = 3,
    RAC_HYBRID_CAPABILITY_TTS         = 4,
    RAC_HYBRID_CAPABILITY_VAD         = 5
} rac_hybrid_capability_t;

/**
 * @brief Backend identity. Matches an engines/ subdir registering a service
 *        vtable. Cloud backends are explicit kinds (each has a distinct
 *        HTTP shape + auth).
 */
typedef enum rac_hybrid_backend_kind {
    RAC_HYBRID_BACKEND_UNSPECIFIED = 0,
    RAC_HYBRID_BACKEND_LLAMACPP    = 1,
    RAC_HYBRID_BACKEND_OPENROUTER  = 2,
    RAC_HYBRID_BACKEND_SHERPA      = 3,
    RAC_HYBRID_BACKEND_SARVAM      = 4
} rac_hybrid_backend_kind_t;

/**
 * @brief Whether a registered model runs on-device or in the cloud.
 */
typedef enum rac_hybrid_model_type {
    RAC_HYBRID_MODEL_TYPE_UNSPECIFIED = 0,
    RAC_HYBRID_MODEL_TYPE_OFFLINE     = 1,
    RAC_HYBRID_MODEL_TYPE_ONLINE      = 2
} rac_hybrid_model_type_t;

/**
 * @brief Filter kind tag for rac_hybrid_filter_t's union. Matches the
 *        Routing Conditions list in thoughts/file.txt verbatim.
 */
typedef enum rac_hybrid_filter_kind {
    RAC_HYBRID_FILTER_NONE    = 0,
    RAC_HYBRID_FILTER_NETWORK = 1,
    /* Value 2 (PRIVACY) was removed. Do not reuse — it is reserved on the
       wire side too (see idl/hybrid_router.proto HybridFilter). */
    RAC_HYBRID_FILTER_QUALITY = 3,
    RAC_HYBRID_FILTER_BATTERY = 4,
    RAC_HYBRID_FILTER_CUSTOM  = 5
} rac_hybrid_filter_kind_t;

/**
 * @brief Custom filter callback. Returns true iff the candidate is eligible.
 *        Must be thread-safe.
 */
typedef bool (*rac_hybrid_custom_filter_fn)(const char* candidate_model_id, void* user_data);

/**
 * @brief Battery filter payload.
 */
typedef struct rac_hybrid_battery_filter {
    int32_t min_battery_percent;
} rac_hybrid_battery_filter_t;

/**
 * @brief Custom filter payload — callback + opaque user data + descriptive
 *        metadata for logging.
 */
typedef struct rac_hybrid_custom_filter {
    char                         name[64];
    char                         description[128];
    rac_hybrid_custom_filter_fn  check;
    void*                        user_data;
} rac_hybrid_custom_filter_t;

/**
 * @brief Single eligibility filter. Tagged-union shape — only the member
 *        named by `kind` is valid.
 */
typedef struct rac_hybrid_filter {
    rac_hybrid_filter_kind_t kind;
    union {
        bool                        network_required;
        int32_t                     quality_tier;
        rac_hybrid_battery_filter_t battery;
        rac_hybrid_custom_filter_t  custom;
    } data;
} rac_hybrid_filter_t;

/**
 * @brief Cascade kind tag. Only Confidence is in the file.txt spec.
 */
typedef enum rac_hybrid_cascade_kind {
    RAC_HYBRID_CASCADE_NONE       = 0,
    RAC_HYBRID_CASCADE_CONFIDENCE = 1
} rac_hybrid_cascade_kind_t;

/**
 * @brief Cascade trigger. At most one per policy. The Confidence cascade
 *        also fires on primary error (an error is treated as "no
 *        confidence").
 */
typedef struct rac_hybrid_cascade {
    rac_hybrid_cascade_kind_t kind;
    union {
        struct {
            float threshold;
        } confidence;
    } data;
} rac_hybrid_cascade_t;

/**
 * @brief Rank — sole comparator used to sort eligible candidates.
 */
typedef enum rac_hybrid_rank {
    RAC_HYBRID_RANK_UNSPECIFIED         = 0,
    RAC_HYBRID_RANK_PREFER_LOCAL_FIRST  = 1,
    RAC_HYBRID_RANK_PREFER_ONLINE_FIRST = 2
} rac_hybrid_rank_t;

/**
 * @brief Full routing policy attached to a model pair. `filters` is a
 *        non-owning pointer into caller memory — the router copies on
 *        register.
 */
typedef struct rac_hybrid_routing_policy {
    const rac_hybrid_filter_t* hard_filters;
    int32_t                    hard_filter_count;
    rac_hybrid_cascade_t       cascade;
    rac_hybrid_rank_t          rank;
} rac_hybrid_routing_policy_t;

/**
 * @brief Descriptor for one model registered with the router.
 */
typedef struct rac_hybrid_model_descriptor {
    char                      model_id[128];
    rac_hybrid_model_type_t   model_type;
    rac_hybrid_backend_kind_t backend;
} rac_hybrid_model_descriptor_t;

/**
 * @brief Per-request routing context populated by the SDK from host state.
 *        Not part of the user-facing Kotlin API — the JNI layer fills this
 *        with detected device state before calling the router.
 */
typedef struct rac_hybrid_routing_context {
    bool    is_online;
    int32_t battery_percent;
} rac_hybrid_routing_context_t;

/**
 * @brief Metadata returned alongside the capability result. Always populated.
 */
typedef struct rac_hybrid_routed_metadata {
    char    chosen_model_id[128];
    bool    was_fallback;
    int32_t attempt_count;
    /* RAC_SUCCESS (0) unless the router fell back; in that case the primary
       candidate's failing rac_result_t is captured here so the caller can
       surface "why we fell back" in UI/logs. */
    int32_t primary_error_code;
    char    primary_error_message[256];
    /* Final confidence of the result that was actually returned. NaN when the
       engine does not surface a quality signal. */
    float   confidence;
    /* Primary's confidence captured before cascading to the secondary on a
       confidence-based fallback. NaN when no confidence cascade occurred. */
    float   primary_confidence;
} rac_hybrid_routed_metadata_t;

/* Confidence threshold below which the STT hybrid router cascades from the
   primary (offline) candidate to the secondary (cloud) candidate. NaN
   confidence (no signal) is treated as "accept primary, no cascade". */
#define RAC_HYBRID_STT_CONFIDENCE_THRESHOLD 0.5f

#ifdef __cplusplus
}
#endif

#endif  // RAC_HYBRID_TYPES_H
