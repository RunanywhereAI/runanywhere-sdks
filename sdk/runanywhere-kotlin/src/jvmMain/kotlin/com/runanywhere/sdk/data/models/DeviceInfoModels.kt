package com.runanywhere.sdk.data.models

actual fun getPlatformAPILevel(): Int = 35 // Default high API level for JVM

actual fun getPlatformOSVersion(): String {
    val osName = System.getProperty("os.name") ?: "Unknown"
    val osVersion = System.getProperty("os.version") ?: ""
    return "$osName $osVersion".trim()
}
