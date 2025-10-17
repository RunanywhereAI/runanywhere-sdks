package com.runanywhere.sdk.models

import java.lang.management.ManagementFactory

/**
 * JVM implementation of device info collection
 */
actual fun collectDeviceInfo(): DeviceInfo {
    val runtime = Runtime.getRuntime()
    val osBean = ManagementFactory.getOperatingSystemMXBean()
    val runtimeBean = ManagementFactory.getRuntimeMXBean()

    return DeviceInfo.create(
        platformName = "JVM",
        platformVersion = System.getProperty("java.version") ?: "Unknown",
        deviceModel = "${System.getProperty("os.arch")} ${System.getProperty("os.name")}",
        osVersion = System.getProperty("os.version") ?: "Unknown",
        sdkVersion = "0.1.0",
        cpuCores = runtime.availableProcessors(),
        totalMemoryMB = runtime.maxMemory() / (1024 * 1024),
        appBundleId = runtimeBean.specName ?: System.getProperty("java.class.path")?.substringBefore(":"),
        appVersion = System.getProperty("java.specification.version")
    )
}
