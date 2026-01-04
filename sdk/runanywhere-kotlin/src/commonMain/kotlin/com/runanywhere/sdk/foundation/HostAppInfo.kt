package com.runanywhere.sdk.foundation

/**
 * Host application information container
 */
data class HostAppInfo(
    val identifier: String?,
    val name: String?,
    val version: String?,
)

/**
 * Get host application information (platform-specific implementation)
 */
expect fun getHostAppInfo(): HostAppInfo
