package com.runanywhere.sdk.core.capabilities

import com.runanywhere.sdk.utils.getCurrentTimeMillis

// MARK: - Base Protocols

/**
 * Base protocol for component inputs
 */
interface ComponentInput {
    fun validate()
}

/**
 * Base protocol for component outputs
 */
interface ComponentOutput {
    val timestamp: Long
}

/**
 * Base protocol for component configurations
 */
interface ComponentConfiguration {
    fun validate()
}

// MARK: - Component State

/**
 * Component/Capability loading state.
 * Matches iOS CapabilityLoadingState pattern.
 */
enum class ComponentState {
    NOT_INITIALIZED,
    CHECKING,
    DOWNLOAD_REQUIRED,
    DOWNLOADING,
    DOWNLOADED,
    INITIALIZING,
    READY,
    PROCESSING,
    FAILED,
}

// MARK: - SDK Component Types

/**
 * SDK component type identifiers.
 * Used for analytics, logging, and event routing.
 */
enum class SDKComponent {
    STT,
    VAD,
    TTS,
    LLM,
    VLM,
    WAKEWORD,
    SPEAKER_DIARIZATION,
    VOICE_AGENT,
}

// MARK: - Component Health and Status

/**
 * Component health check result
 */
data class ComponentHealth(
    val isHealthy: Boolean,
    val details: String,
)

/**
 * Comprehensive component status matching iOS ComponentStatus
 */
data class ComponentStatus(
    val state: ComponentState,
    val progress: Float? = null,
    val error: Throwable? = null,
    val timestamp: Long = getCurrentTimeMillis(),
    val currentStage: String? = null,
    val metadata: Map<String, Any>? = null,
) {
    val isHealthy: Boolean
        get() = state != ComponentState.FAILED && error == null
}

// MARK: - Module Registry and Service Providers
//
// The ModuleRegistry is defined in com.runanywhere.sdk.core.ModuleRegistry
// Service providers (STTServiceProvider, VADServiceProvider, LLMServiceProvider, etc.)
// are also defined there.
//
// For iOS-aligned capability protocols (Capability, ModelLoadableCapability, etc.),
// see CapabilityProtocols.kt in this package.
// For analytics types, see CoreAnalyticsTypes.kt
// For resource types, see ResourceTypes.kt
