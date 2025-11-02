package com.runanywhere.sdk.foundation

/**
 * Native implementation of getHostAppInfo
 * Returns null for all fields as Native platforms don't have a standard way to get app info
 */
actual fun getHostAppInfo(): HostAppInfo {
    return HostAppInfo(null, null, null)
}
