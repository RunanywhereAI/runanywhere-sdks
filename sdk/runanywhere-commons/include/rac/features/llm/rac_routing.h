/**
 * @file rac_routing.h
 * @brief RunAnywhere Commons - Routing Policy Types and Configuration
 *
 * Defines policy types for intelligent routing between on-device and
 * cloud inference. The C++ commons layer defines the types and validation;
 * the platform SDKs implement the actual cloud provider calls.
 *
 * Routing modes:
 * - ALWAYS_LOCAL: Never route to cloud, all inference on-device.
 * - ALWAYS_CLOUD: Skip on-device, always use cloud provider.
 * - HYBRID_AUTO: On-device first; auto-fallback to cloud on low confidence.
 * - HYBRID_MANUAL: On-device first; return handoff signal (app decides).
 */

#ifndef RAC_ROUTING_H
#define RAC_ROUTING_H

#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// ROUTING MODE
// =============================================================================

/**
 * @brief Routing mode for inference requests
 */
typedef enum rac_routing_mode {
    /** Never use cloud - all inference is on-device only */
    RAC_ROUTING_ALWAYS_LOCAL = 0,

    /** Always use cloud - skip on-device inference entirely */
    RAC_ROUTING_ALWAYS_CLOUD = 1,

    /** On-device first, automatically fallback to cloud on low confidence */
    RAC_ROUTING_HYBRID_AUTO = 2,

    /** On-device first, return handoff signal for app to decide */
    RAC_ROUTING_HYBRID_MANUAL = 3,
} rac_routing_mode_t;

// =============================================================================
// EXECUTION TARGET
// =============================================================================

/**
 * @brief Where inference was actually executed
 */
typedef enum rac_execution_target {
    /** Inference ran entirely on-device */
    RAC_EXECUTION_ON_DEVICE = 0,

    /** Inference ran entirely in the cloud */
    RAC_EXECUTION_CLOUD = 1,

    /** Inference started on-device, then fell back to cloud */
    RAC_EXECUTION_HYBRID_FALLBACK = 2,
} rac_execution_target_t;

// =============================================================================
// ROUTING POLICY
// =============================================================================

/**
 * @brief Routing policy configuration
 *
 * Controls how inference requests are routed between on-device and cloud.
 * Can be set per-request or as a default for the SDK.
 */
typedef struct rac_routing_policy {
    /** Routing mode (default: HYBRID_MANUAL) */
    rac_routing_mode_t mode;

    /**
     * Confidence threshold for cloud handoff (0.0 - 1.0).
     * Used in HYBRID_AUTO and HYBRID_MANUAL modes.
     * Lower values = more tolerant of on-device uncertainty.
     * Default: 0.7
     */
    float confidence_threshold;

    /**
     * Maximum time-to-first-token in milliseconds before triggering cloud fallback.
     * 0 = no latency limit (default).
     * Only used in HYBRID_AUTO mode.
     */
    uint32_t max_local_latency_ms;

    /**
     * Maximum cloud API cost in USD per request.
     * 0.0 = no cost cap (default).
     * When exceeded, generation stops or falls back to on-device.
     */
    float cost_cap_usd;

    /** Whether to prefer streaming for cloud calls (default: true) */
    rac_bool_t prefer_streaming;
} rac_routing_policy_t;

/**
 * @brief Default routing policy
 *
 * HYBRID_MANUAL mode with 0.7 confidence threshold.
 * Safe default: returns handoff signal, app decides what to do.
 */
static const rac_routing_policy_t RAC_ROUTING_POLICY_DEFAULT = {
    .mode = RAC_ROUTING_HYBRID_MANUAL,
    .confidence_threshold = 0.7f,
    .max_local_latency_ms = 0,
    .cost_cap_usd = 0.0f,
    .prefer_streaming = RAC_TRUE,
};

/** Convenience: always-local policy (no cloud routing) */
static const rac_routing_policy_t RAC_ROUTING_POLICY_LOCAL_ONLY = {
    .mode = RAC_ROUTING_ALWAYS_LOCAL,
    .confidence_threshold = 0.0f,
    .max_local_latency_ms = 0,
    .cost_cap_usd = 0.0f,
    .prefer_streaming = RAC_FALSE,
};

/** Convenience: always-cloud policy */
static const rac_routing_policy_t RAC_ROUTING_POLICY_CLOUD_ONLY = {
    .mode = RAC_ROUTING_ALWAYS_CLOUD,
    .confidence_threshold = 0.0f,
    .max_local_latency_ms = 0,
    .cost_cap_usd = 0.0f,
    .prefer_streaming = RAC_TRUE,
};

// =============================================================================
// ROUTING DECISION
// =============================================================================

/**
 * @brief Routing decision metadata
 *
 * Describes the routing decision made for a generation request.
 * Included in generation results so the app can inspect what happened.
 */
typedef struct rac_routing_decision {
    /** Where inference was executed */
    rac_execution_target_t execution_target;

    /** The routing policy that was applied */
    rac_routing_policy_t policy;

    /** On-device confidence score (0.0 - 1.0, only valid if on-device was attempted) */
    float on_device_confidence;

    /** Whether cloud handoff was triggered */
    rac_bool_t cloud_handoff_triggered;

    /** Handoff reason (only valid if cloud_handoff_triggered) */
    rac_handoff_reason_t handoff_reason;

    /** On-device time-to-first-token in ms (0 if cloud-only) */
    int64_t on_device_ttft_ms;

    /** Cloud provider ID used (NULL if on-device only) */
    const char* cloud_provider_id;

    /** Cloud model used (NULL if on-device only) */
    const char* cloud_model;
} rac_routing_decision_t;

// =============================================================================
// ROUTING POLICY API
// =============================================================================

/**
 * @brief Create a default routing policy
 *
 * @param out_policy Output: routing policy with defaults
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_routing_policy_create_default(rac_routing_policy_t* out_policy);

/**
 * @brief Validate a routing policy
 *
 * Checks that all values are within valid ranges.
 *
 * @param policy Policy to validate
 * @return RAC_SUCCESS if valid, RAC_ERROR_INVALID_ARGUMENT if not
 */
RAC_API rac_result_t rac_routing_policy_validate(const rac_routing_policy_t* policy);

/**
 * @brief Get a human-readable name for a routing mode
 *
 * @param mode The routing mode
 * @return Static string (never NULL)
 */
RAC_API const char* rac_routing_mode_name(rac_routing_mode_t mode);

/**
 * @brief Get a human-readable name for an execution target
 *
 * @param target The execution target
 * @return Static string (never NULL)
 */
RAC_API const char* rac_execution_target_name(rac_execution_target_t target);

#ifdef __cplusplus
}
#endif

#endif /* RAC_ROUTING_H */
