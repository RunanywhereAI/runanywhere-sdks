/**
 * @file rac_routing.cpp
 * @brief RunAnywhere Commons - Routing Policy Implementation
 *
 * Implements validation and utility functions for routing policies.
 * The actual routing logic lives in platform SDKs; this file provides
 * shared types and validation only.
 */

#include "rac/features/llm/rac_routing.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "Routing";

extern "C" {

rac_result_t rac_routing_policy_create_default(rac_routing_policy_t* out_policy) {
    if (!out_policy) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_policy = RAC_ROUTING_POLICY_DEFAULT;
    return RAC_SUCCESS;
}

rac_result_t rac_routing_policy_validate(const rac_routing_policy_t* policy) {
    if (!policy) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Validate mode
    if (policy->mode < RAC_ROUTING_ALWAYS_LOCAL || policy->mode > RAC_ROUTING_HYBRID_MANUAL) {
        RAC_LOG_ERROR(LOG_CAT, "Invalid routing mode: %d", policy->mode);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Validate confidence threshold
    if (policy->confidence_threshold < 0.0f || policy->confidence_threshold > 1.0f) {
        RAC_LOG_ERROR(LOG_CAT, "Invalid confidence_threshold: %.3f (must be 0.0-1.0)",
                      policy->confidence_threshold);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Validate cost cap
    if (policy->cost_cap_usd < 0.0f) {
        RAC_LOG_ERROR(LOG_CAT, "Invalid cost_cap_usd: %.4f (must be >= 0.0)", policy->cost_cap_usd);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    return RAC_SUCCESS;
}

const char* rac_routing_mode_name(rac_routing_mode_t mode) {
    switch (mode) {
        case RAC_ROUTING_ALWAYS_LOCAL:
            return "always_local";
        case RAC_ROUTING_ALWAYS_CLOUD:
            return "always_cloud";
        case RAC_ROUTING_HYBRID_AUTO:
            return "hybrid_auto";
        case RAC_ROUTING_HYBRID_MANUAL:
            return "hybrid_manual";
        default:
            return "unknown";
    }
}

const char* rac_execution_target_name(rac_execution_target_t target) {
    switch (target) {
        case RAC_EXECUTION_ON_DEVICE:
            return "on_device";
        case RAC_EXECUTION_CLOUD:
            return "cloud";
        case RAC_EXECUTION_HYBRID_FALLBACK:
            return "hybrid_fallback";
        default:
            return "unknown";
    }
}

}  // extern "C"
