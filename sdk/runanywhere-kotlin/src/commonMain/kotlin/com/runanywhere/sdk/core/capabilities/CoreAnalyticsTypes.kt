package com.runanywhere.sdk.core.capabilities

/**
 * CoreAnalyticsTypes.kt
 * RunAnywhere SDK
 *
 * Core analytics types used across all capabilities.
 * Matches iOS Core/Capabilities/Analytics/CoreAnalyticsTypes.swift
 */

// MARK: - Analytics Metrics Protocol

/**
 * Base interface for analytics metrics.
 * Matches iOS AnalyticsMetrics protocol.
 */
interface AnalyticsMetrics {
    val totalEvents: Int
    val startTime: Long // Epoch milliseconds
    val lastEventTime: Long? // Epoch milliseconds, null if no events yet
}

// MARK: - Inference Framework Type

/**
 * Inference frameworks used for tracking which engine is processing requests.
 * Use "none" for services that don't require a model/framework.
 * Matches iOS InferenceFrameworkType enum.
 *
 * Note: This is for analytics tracking. For the main framework enum, see
 * [com.runanywhere.sdk.models.enums.InferenceFramework]
 */
enum class InferenceFrameworkType(val value: String) {
    LLAMA_CPP("llama_cpp"),
    WHISPER_KIT("whisper_kit"),
    ONNX("onnx"),
    CORE_ML("core_ml"),
    FOUNDATION_MODELS("foundation_models"),
    MLX("mlx"),
    BUILT_IN("built_in"),  // For simple services like energy-based VAD
    NONE("none"),          // For services that don't use a model
    UNKNOWN("unknown");

    companion object {
        fun fromValue(value: String): InferenceFrameworkType {
            return entries.find { it.value == value } ?: UNKNOWN
        }
    }
}

// MARK: - Model Lifecycle Event Types

/**
 * Event types for model lifecycle across all capabilities.
 * Matches iOS ModelLifecycleEventType enum.
 */
enum class ModelLifecycleEventType(val value: String) {
    LOADING_STARTED("model_loading_started"),
    LOAD_COMPLETED("model_load_completed"),
    LOAD_FAILED("model_load_failed"),
    UNLOAD_COMPLETED("model_unload_completed"),
    DOWNLOAD_STARTED("model_download_started"),
    DOWNLOAD_PROGRESS("model_download_progress"),
    DOWNLOAD_COMPLETED("model_download_completed"),
    DOWNLOAD_FAILED("model_download_failed"),
    ERROR("model_lifecycle_error");

    companion object {
        fun fromValue(value: String): ModelLifecycleEventType? {
            return entries.find { it.value == value }
        }
    }
}

// MARK: - Model Lifecycle Metrics

/**
 * Metrics for model lifecycle operations.
 * Matches iOS ModelLifecycleMetrics struct.
 */
data class ModelLifecycleMetrics(
    override val totalEvents: Int = 0,
    override val startTime: Long = System.currentTimeMillis(),
    override val lastEventTime: Long? = null,
    val totalLoads: Int = 0,
    val successfulLoads: Int = 0,
    val failedLoads: Int = 0,
    val averageLoadTimeMs: Double = -1.0,  // -1 indicates N/A for services without models
    val totalUnloads: Int = 0,
    val totalDownloads: Int = 0,
    val successfulDownloads: Int = 0,
    val failedDownloads: Int = 0,
    val totalBytesDownloaded: Long = 0,
    val framework: InferenceFrameworkType = InferenceFrameworkType.UNKNOWN
) : AnalyticsMetrics
