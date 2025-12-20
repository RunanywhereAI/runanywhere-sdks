package com.runanywhere.sdk.core.capabilities

/**
 * ResourceTypes.kt
 * RunAnywhere SDK
 *
 * Resource types for capabilities.
 * Lifecycle events are tracked directly via EventPublisher.
 * Matches iOS Core/Capabilities/Analytics/ResourceTypes.swift
 */

// MARK: - Resource Types

/**
 * Types of resources that can be loaded by capabilities.
 * Matches iOS CapabilityResourceType enum.
 */
enum class CapabilityResourceType(val value: String) {
    LLM_MODEL("llm_model"),
    STT_MODEL("stt_model"),
    TTS_VOICE("tts_voice"),
    VAD_MODEL("vad_model"),
    DIARIZATION_MODEL("diarization_model");

    companion object {
        fun fromValue(value: String): CapabilityResourceType? {
            return entries.find { it.value == value }
        }
    }
}
