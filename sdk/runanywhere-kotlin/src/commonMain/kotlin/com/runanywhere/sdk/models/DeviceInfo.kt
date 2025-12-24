package com.runanywhere.sdk.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Core device hardware information for telemetry, logging, and API requests.
 * Matches iOS DeviceInfo.swift exactly.
 *
 * This is embedded in DeviceRegistrationRequest and also available standalone.
 */
@Serializable
data class DeviceInfo(
    // MARK: - Device Identity

    /** Persistent device UUID (survives app reinstalls via Keychain/SharedPreferences) */
    @SerialName("device_id")
    val deviceId: String,

    // MARK: - Device Hardware

    /** Device model identifier (e.g., "iPhone16,2" for iPhone 15 Pro Max, "Pixel 8 Pro" for Android) */
    @SerialName("model_identifier")
    val modelIdentifier: String,

    /** User-friendly device name (e.g., "iPhone 15 Pro Max", "Google Pixel 8 Pro") */
    @SerialName("model_name")
    val modelName: String,

    /** CPU architecture (e.g., "arm64", "x86_64") */
    @SerialName("architecture")
    val architecture: String,

    // MARK: - Operating System

    /** Operating system version string (e.g., "17.2", "14") */
    @SerialName("os_version")
    val osVersion: String,

    /** Platform identifier (e.g., "iOS", "Android", "JVM", "macOS") */
    @SerialName("platform")
    val platform: String,

    // MARK: - Device Classification

    /** Device type for API requests (mobile, tablet, desktop, tv, watch, vr) */
    @SerialName("device_type")
    val deviceType: String,

    /** Form factor (phone, tablet, laptop, desktop, tv, watch, headset) */
    @SerialName("form_factor")
    val formFactor: String,

    // MARK: - Hardware Specs

    /** Total physical memory in bytes */
    @SerialName("total_memory")
    val totalMemory: Long,

    /** Number of processor cores */
    @SerialName("processor_count")
    val processorCount: Int,
) {
    /**
     * Human-readable description of the device
     */
    val description: String
        get() = "$modelName ($platform $osVersion) - $processorCount cores, ${totalMemory / (1024 * 1024)}MB RAM"

    /**
     * Total memory in MB (convenience property)
     */
    val totalMemoryMB: Long
        get() = totalMemory / (1024 * 1024)

    /**
     * Check if device meets minimum requirements for on-device AI
     */
    fun meetsMinimumRequirements(): Boolean = processorCount >= 2 && totalMemoryMB >= 1024

    companion object {
        /**
         * Get current device info - delegates to platform-specific implementation
         */
        val current: DeviceInfo
            get() = collectDeviceInfo()
    }
}

/**
 * Platform-specific device info collection.
 * Implemented in jvmMain, androidMain, iosMain, etc.
 */
expect fun collectDeviceInfo(): DeviceInfo
