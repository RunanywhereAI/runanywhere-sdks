package com.runanywhere.sdk.data.network.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Models for development analytics submission to Supabase
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Models/DevAnalyticsModels.swift
 */

// MARK: - Analytics Submission

/**
 * Request model for submitting generation analytics to Supabase
 */
@Serializable
data class DevAnalyticsSubmissionRequest(
    @SerialName("generation_id")
    val generationId: String,

    @SerialName("device_id")
    val deviceId: String,

    @SerialName("model_id")
    val modelId: String,

    @SerialName("time_to_first_token_ms")
    val timeToFirstTokenMs: Double? = null,

    @SerialName("tokens_per_second")
    val tokensPerSecond: Double,

    @SerialName("total_generation_time_ms")
    val totalGenerationTimeMs: Double,

    @SerialName("input_tokens")
    val inputTokens: Int,

    @SerialName("output_tokens")
    val outputTokens: Int,

    @SerialName("success")
    val success: Boolean,

    @SerialName("execution_target")
    val executionTarget: String, // "onDevice" or "cloud"

    @SerialName("build_token")
    val buildToken: String, // Non-nullable to match iOS

    @SerialName("sdk_version")
    val sdkVersion: String,

    @SerialName("timestamp")
    val timestamp: String // ISO8601 format
)

/**
 * Response model from Supabase analytics submission
 */
@Serializable
data class DevAnalyticsSubmissionResponse(
    @SerialName("success")
    val success: Boolean,

    @SerialName("analytics_id")
    val analyticsId: String? = null
)

// MARK: - Device Registration

/**
 * Request model for registering device in development mode (Supabase)
 */
@Serializable
data class DevDeviceRegistrationRequest(
    @SerialName("device_id")
    val deviceId: String,

    @SerialName("platform")
    val platform: String, // "android", "ios", etc.

    @SerialName("os_version")
    val osVersion: String,

    @SerialName("device_model")
    val deviceModel: String,

    @SerialName("sdk_version")
    val sdkVersion: String,

    @SerialName("build_token")
    val buildToken: String? = null,

    @SerialName("architecture")
    val architecture: String? = null,

    @SerialName("chip_name")
    val chipName: String? = null,

    @SerialName("total_memory")
    val totalMemory: Long? = null, // In bytes, not GB!

    @SerialName("has_neural_engine")
    val hasNeuralEngine: Boolean? = null,

    @SerialName("form_factor")
    val formFactor: String? = null,

    @SerialName("app_version")
    val appVersion: String? = null
)

/**
 * Response model from device registration (Supabase)
 */
@Serializable
data class DevDeviceRegistrationResponse(
    @SerialName("success")
    val success: Boolean,

    @SerialName("device_id")
    val deviceId: String? = null,

    @SerialName("message")
    val message: String? = null
)
