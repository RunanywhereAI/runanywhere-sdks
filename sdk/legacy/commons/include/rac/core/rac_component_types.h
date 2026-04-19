/**
 * @file rac_component_types.h
 * @brief RunAnywhere Commons - Core Component Types
 *
 * C port of Swift's component types from:
 * Sources/RunAnywhere/Core/Types/ComponentTypes.swift
 * Sources/RunAnywhere/Core/Capabilities/Analytics/ResourceTypes.swift
 *
 * These types define SDK components, their configurations, and resource types.
 */

#ifndef RAC_COMPONENT_TYPES_H
#define RAC_COMPONENT_TYPES_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SDK COMPONENT - Mirrors Swift's SDKComponent enum
// =============================================================================

/**
 * @brief SDK component types for identification
 *
 * Mirrors Swift's SDKComponent enum exactly.
 * See: Sources/RunAnywhere/Core/Types/ComponentTypes.swift
 */
typedef enum rac_sdk_component {
    RAC_COMPONENT_LLM = 0,       /**< Large Language Model */
    RAC_COMPONENT_STT = 1,       /**< Speech-to-Text */
    RAC_COMPONENT_TTS = 2,       /**< Text-to-Speech */
    RAC_COMPONENT_VAD = 3,       /**< Voice Activity Detection */
    RAC_COMPONENT_VOICE = 4,     /**< Voice Agent */
    RAC_COMPONENT_EMBEDDING = 5, /**< Embedding generation */
} rac_sdk_component_t;

/**
 * @brief Get human-readable display name for SDK component
 *
 * @param component The SDK component type
 * @return Display name string (static, do not free)
 */
RAC_API const char* rac_sdk_component_display_name(rac_sdk_component_t component);

/**
 * @brief Get raw string value for SDK component
 *
 * Mirrors Swift's rawValue property.
 *
 * @param component The SDK component type
 * @return Raw string value (static, do not free)
 */
RAC_API const char* rac_sdk_component_raw_value(rac_sdk_component_t component);

// =============================================================================
// CAPABILITY RESOURCE TYPE - Mirrors Swift's CapabilityResourceType enum
// =============================================================================

/**
 * @brief Types of resources that can be loaded by capabilities
 *
 * Mirrors Swift's CapabilityResourceType enum exactly.
 * See: Sources/RunAnywhere/Core/Capabilities/Analytics/ResourceTypes.swift
 */
typedef enum rac_capability_resource_type {
    RAC_RESOURCE_LLM_MODEL = 0,         /**< LLM model */
    RAC_RESOURCE_STT_MODEL = 1,         /**< STT model */
    RAC_RESOURCE_TTS_VOICE = 2,         /**< TTS voice */
    RAC_RESOURCE_VAD_MODEL = 3,         /**< VAD model */
    RAC_RESOURCE_DIARIZATION_MODEL = 4, /**< Diarization model */
} rac_capability_resource_type_t;

/**
 * @brief Get raw string value for capability resource type
 *
 * Mirrors Swift's rawValue property.
 *
 * @param type The capability resource type
 * @return Raw string value (static, do not free)
 */
RAC_API const char* rac_capability_resource_type_raw_value(rac_capability_resource_type_t type);

// =============================================================================
// COMPONENT CONFIGURATION - Mirrors Swift's ComponentConfiguration protocol
// =============================================================================

/**
 * @brief Base component configuration
 *
 * Mirrors Swift's ComponentConfiguration protocol.
 * See: Sources/RunAnywhere/Core/Types/ComponentTypes.swift
 *
 * Note: In C, we use a struct with common fields instead of a protocol.
 * Specific configurations (LLM, STT, TTS, VAD) extend this with their own fields.
 */
typedef struct rac_component_config_base {
    /** Model identifier (optional - uses default if NULL) */
    const char* model_id;

    /** Preferred inference framework (use -1 for auto/none) */
    int32_t preferred_framework;
} rac_component_config_base_t;

/**
 * @brief Default base component configuration
 */
static const rac_component_config_base_t RAC_COMPONENT_CONFIG_BASE_DEFAULT = {
    .model_id = RAC_NULL, .preferred_framework = -1 /* No preference */
};

// =============================================================================
// COMPONENT INPUT/OUTPUT - Mirrors Swift's ComponentInput/ComponentOutput protocols
// =============================================================================

/**
 * @brief Base component output with timestamp
 *
 * Mirrors Swift's ComponentOutput protocol requirement.
 * All outputs include a timestamp in milliseconds since epoch.
 */
typedef struct rac_component_output_base {
    /** Timestamp in milliseconds since epoch (1970-01-01 00:00:00 UTC) */
    int64_t timestamp_ms;
} rac_component_output_base_t;

// =============================================================================
// INFERENCE FRAMEWORK - Mirrors Swift's InferenceFramework enum
// (Typically defined in model_types, but included here for completeness)
// =============================================================================

/**
 * @brief Get SDK component type from capability resource type
 *
 * Maps resource types to their corresponding SDK components.
 *
 * @param resource_type The capability resource type
 * @return Corresponding SDK component type
 */
RAC_API rac_sdk_component_t
rac_resource_type_to_component(rac_capability_resource_type_t resource_type);

/**
 * @brief Get capability resource type from SDK component type
 *
 * Maps SDK components to their corresponding resource types.
 *
 * @param component The SDK component type
 * @return Corresponding capability resource type, or -1 if no mapping exists
 */
RAC_API rac_capability_resource_type_t
rac_component_to_resource_type(rac_sdk_component_t component);

#ifdef __cplusplus
}
#endif

#endif /* RAC_COMPONENT_TYPES_H */
