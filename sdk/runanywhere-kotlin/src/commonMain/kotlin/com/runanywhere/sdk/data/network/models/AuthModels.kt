package com.runanywhere.sdk.data.network.models

import kotlinx.serialization.Serializable

/**
 * Authentication request model
 * Matches iOS AuthenticationRequest structure
 */
@Serializable
data class AuthenticationRequest(
    val apiKey: String,
    val deviceId: String,
    val platform: String,
    val sdkVersion: String,
    val platformVersion: String? = null,
    val appIdentifier: String? = null,
)

/**
 * Authentication response model
 * Matches iOS AuthenticationResponse structure
 */
@Serializable
data class AuthenticationResponse(
    val accessToken: String,
    val refreshToken: String? = null,
    val expiresIn: Int,
    val tokenType: String = "Bearer",
    val deviceId: String,
    val organizationId: String,
    val userId: String? = null, // Can be null for org-level access
)

/**
 * Refresh token request model
 * Matches iOS RefreshTokenRequest structure
 */
@Serializable
data class RefreshTokenRequest(
    val refreshToken: String,
    val deviceId: String? = null,
)

/**
 * Refresh token response model
 * Matches iOS RefreshTokenResponse structure
 */
@Serializable
data class RefreshTokenResponse(
    val accessToken: String,
    val refreshToken: String? = null,
    val expiresIn: Int,
    val tokenType: String = "Bearer",
    val deviceId: String? = null,
    val organizationId: String? = null,
    val userId: String? = null,
)

/**
 * Health check response model
 * Matches iOS HealthCheckResponse structure
 */
@Serializable
data class HealthCheckResponse(
    val status: String,
    val version: String,
    val timestamp: Long? = null,
    val uptime: Long? = null,
    val environment: String? = null,
)

/**
 * Device registration request model
 * Matches iOS DeviceRegistrationRequest structure
 */
@Serializable
data class DeviceRegistrationRequest(
    val deviceInfo: DeviceRegistrationInfo,
)

/**
 * Device registration response model
 * Matches iOS DeviceRegistrationResponse structure exactly
 * Location: Infrastructure/Device/Models/Network/DeviceRegistrationResponse.swift
 */
@Serializable
data class DeviceRegistrationResponse(
    val success: Boolean,
    @kotlinx.serialization.SerialName("device_id")
    val deviceId: String,
    @kotlinx.serialization.SerialName("registered_at")
    val registeredAt: String,
)

/**
 * Comprehensive device registration info
 * Matches iOS DeviceRegistrationInfo structure
 */
@Serializable
data class DeviceRegistrationInfo(
    val architecture: String,
    val availableMemory: Long,
    val batteryLevel: Double,
    val batteryState: String,
    val chipName: String,
    val coreCount: Int,
    val deviceModel: String,
    val deviceName: String,
    val efficiencyCores: Int,
    val formFactor: String,
    val gpuFamily: String,
    val hasNeuralEngine: Boolean,
    val isLowPowerMode: Boolean,
    val neuralEngineCores: Int,
    val osVersion: String,
    val performanceCores: Int,
    val platform: String,
    val totalMemory: Long,
)

/**
 * Error response model for API errors
 */
@Serializable
data class APIErrorResponse(
    val error: String,
    val message: String,
    val code: Int? = null,
    val details: Map<String, String>? = null, // Changed from Any to String for serialization
)
