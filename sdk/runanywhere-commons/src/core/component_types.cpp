/**
 * @file component_types.cpp
 * @brief Implementation of component types
 *
 * C++ implementation of component type utilities.
 * 1:1 port from Swift's ComponentTypes.swift and ResourceTypes.swift
 */

#include <cstring>

#include "rac/core/rac_component_types.h"

// =============================================================================
// SDK COMPONENT FUNCTIONS
// =============================================================================

const char* rac_sdk_component_display_name(rac_sdk_component_t component) {
    // Port from Swift's SDKComponent.displayName computed property
    switch (component) {
        case RAC_COMPONENT_LLM:
            return "LLM";
        case RAC_COMPONENT_STT:
            return "Speech-to-Text";
        case RAC_COMPONENT_TTS:
            return "Text-to-Speech";
        case RAC_COMPONENT_VAD:
            return "Voice Activity Detection";
        case RAC_COMPONENT_VOICE:
            return "Voice Agent";
        case RAC_COMPONENT_EMBEDDING:
            return "Embedding";
        default:
            return "Unknown";
    }
}

const char* rac_sdk_component_raw_value(rac_sdk_component_t component) {
    // Port from Swift's SDKComponent.rawValue (enum case names)
    switch (component) {
        case RAC_COMPONENT_LLM:
            return "llm";
        case RAC_COMPONENT_STT:
            return "stt";
        case RAC_COMPONENT_TTS:
            return "tts";
        case RAC_COMPONENT_VAD:
            return "vad";
        case RAC_COMPONENT_VOICE:
            return "voice";
        case RAC_COMPONENT_EMBEDDING:
            return "embedding";
        default:
            return "unknown";
    }
}

// =============================================================================
// CAPABILITY RESOURCE TYPE FUNCTIONS
// =============================================================================

const char* rac_capability_resource_type_raw_value(rac_capability_resource_type_t type) {
    // Port from Swift's CapabilityResourceType.rawValue
    switch (type) {
        case RAC_RESOURCE_LLM_MODEL:
            return "llm_model";
        case RAC_RESOURCE_STT_MODEL:
            return "stt_model";
        case RAC_RESOURCE_TTS_VOICE:
            return "tts_voice";
        case RAC_RESOURCE_VAD_MODEL:
            return "vad_model";
        case RAC_RESOURCE_DIARIZATION_MODEL:
            return "diarization_model";
        default:
            return "unknown";
    }
}

// =============================================================================
// MAPPING FUNCTIONS
// =============================================================================

rac_sdk_component_t rac_resource_type_to_component(rac_capability_resource_type_t resource_type) {
    // Map resource types to SDK components
    switch (resource_type) {
        case RAC_RESOURCE_LLM_MODEL:
            return RAC_COMPONENT_LLM;
        case RAC_RESOURCE_STT_MODEL:
            return RAC_COMPONENT_STT;
        case RAC_RESOURCE_TTS_VOICE:
            return RAC_COMPONENT_TTS;
        case RAC_RESOURCE_VAD_MODEL:
        case RAC_RESOURCE_DIARIZATION_MODEL:
            return RAC_COMPONENT_VAD;
        default:
            return RAC_COMPONENT_LLM;  // Default fallback
    }
}

rac_capability_resource_type_t rac_component_to_resource_type(rac_sdk_component_t component) {
    // Map SDK components to resource types
    switch (component) {
        case RAC_COMPONENT_LLM:
            return RAC_RESOURCE_LLM_MODEL;
        case RAC_COMPONENT_STT:
            return RAC_RESOURCE_STT_MODEL;
        case RAC_COMPONENT_TTS:
            return RAC_RESOURCE_TTS_VOICE;
        case RAC_COMPONENT_VAD:
            return RAC_RESOURCE_VAD_MODEL;
        case RAC_COMPONENT_VOICE:
            // Voice agent doesn't have a direct resource type
            return static_cast<rac_capability_resource_type_t>(-1);
        case RAC_COMPONENT_EMBEDDING:
            return RAC_RESOURCE_LLM_MODEL;  // Embeddings use LLM models
        default:
            return static_cast<rac_capability_resource_type_t>(-1);
    }
}
