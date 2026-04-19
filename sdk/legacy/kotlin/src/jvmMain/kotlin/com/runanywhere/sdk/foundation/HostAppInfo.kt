package com.runanywhere.sdk.foundation

/**
 * JVM implementation of getHostAppInfo
 * Returns null for all fields as JVM doesn't have a standard way to get app info
 */
actual fun getHostAppInfo(): HostAppInfo = HostAppInfo(null, null, null)
