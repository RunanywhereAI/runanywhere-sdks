package com.runanywhere.sdk.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Device registration request wrapper for backend API
 */
@Serializable
data class DeviceRegistrationPayload(
    @SerialName("device_info")
    val deviceInfo: DeviceInfoData,
)

/**
 * Device registration response from backend
 */
@Serializable
data class DeviceRegistrationResult(
    @SerialName("device_id")
    val deviceId: String,
    @SerialName("status")
    val status: String, // "registered", "updated"
    @SerialName("sync_status")
    val syncStatus: String, // "synced", "pending"
)
