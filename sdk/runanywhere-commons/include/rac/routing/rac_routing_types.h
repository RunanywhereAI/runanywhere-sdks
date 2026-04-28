/**
 * @file rac_routing_types.h
 * @brief Hybrid router shared types.
 *
 * The router selects one backend per request from a set of registered
 * candidates, applying eligibility conditions, a routing policy, and a
 * confidence-based cascade. Types are capability-agnostic; per-capability
 * vtables live in rac_router.h.
 */

#ifndef RAC_ROUTING_TYPES_H
#define RAC_ROUTING_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rac_routed_capability {
    RAC_ROUTED_CAP_STT = 1,
    RAC_ROUTED_CAP_LLM = 2,
    RAC_ROUTED_CAP_VLM = 3,
    RAC_ROUTED_CAP_TTS = 4,
    RAC_ROUTED_CAP_VAD = 5
} rac_routed_capability_t;

typedef enum rac_routing_policy {
    RAC_ROUTING_POLICY_AUTO = 0,
    RAC_ROUTING_POLICY_LOCAL_ONLY = 1,
    RAC_ROUTING_POLICY_CLOUD_ONLY = 2,
    RAC_ROUTING_POLICY_PREFER_LOCAL = 3,
    RAC_ROUTING_POLICY_PREFER_ACCURACY = 4,
    RAC_ROUTING_POLICY_FRAMEWORK_PREFERRED = 5,
    // App-supplied scoring fn registered via rac_hybrid_router_set_custom_policy.
    RAC_ROUTING_POLICY_CUSTOM = 99
} rac_routing_policy_t;

// Custom scoring fn — higher score wins. Called for every eligible candidate
// when ctx.policy == RAC_ROUTING_POLICY_CUSTOM. Must be thread-safe; the
// router may call concurrently from different request threads.
typedef int32_t (*rac_custom_policy_fn)(const struct rac_backend_descriptor* descriptor,
                                        const struct rac_routing_context*    context,
                                        void*                                user_data);

typedef enum rac_condition_kind {
    RAC_COND_LOCAL_ONLY = 1,
    RAC_COND_NETWORK_REQUIRED = 2,
    RAC_COND_QUALITY_TIER = 3,
    RAC_COND_COST_MODEL = 4,
    RAC_COND_MODEL_AVAILABILITY = 5,
    RAC_COND_CUSTOM = 6
} rac_condition_kind_t;

typedef struct rac_routing_context {
    bool                 is_online;
    rac_routing_policy_t policy;
    // Preferred inference framework id (empty string = no preference).
    char preferred_framework[64];
} rac_routing_context_t;

typedef struct rac_routing_condition {
    rac_condition_kind_t kind;
    union {
        int32_t quality_tier;
        float   cost_per_minute_cents;
        struct {
            char  model_id[128];
            bool  (*check)(void* user_data);
            void* user_data;
        } availability;
        struct {
            char  desc[64];
            bool  (*check)(void* user_data, const rac_routing_context_t* ctx);
            void* user_data;
        } custom;
    } data;
} rac_routing_condition_t;

typedef struct rac_backend_descriptor {
    char                           module_id[64];
    char                           module_name[128];
    rac_routed_capability_t        capability;
    char                           inference_framework[64];
    int32_t                        base_priority;
    const rac_routing_condition_t* conditions;
    int32_t                        condition_count;
} rac_backend_descriptor_t;

typedef struct rac_routed_metadata {
    char    chosen_module_id[64];
    bool    was_fallback;
    float   primary_confidence;
    int32_t attempt_count;
    // When the cascade tried a cloud backend after a low-confidence local
    // primary and that cloud attempt failed, this captures the last error
    // code seen and the module_id that produced it. Allows the UI to surface
    // "we tried X, it failed with rc=Y" instead of silently returning the
    // restored local result. Defaults: code=0, id=empty.
    int32_t cascade_error_code;
    char    cascade_error_module_id[64];
} rac_routed_metadata_t;

// Confidence below which a local-only backend will cascade to the next
// candidate. Matches the Kotlin threshold the router replaces.
#define RAC_ROUTING_CONFIDENCE_THRESHOLD 0.5f

#ifdef __cplusplus
}
#endif

#endif  // RAC_ROUTING_TYPES_H
