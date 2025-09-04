package com.runanywhere.sdk.services.deviceinfo

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import com.runanywhere.sdk.data.models.BatteryState
import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.models.DeviceFingerprint
import com.runanywhere.sdk.data.models.GPUType
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.models.ThermalState
import com.runanywhere.sdk.data.repository.DeviceInfoRepository
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.sync.SyncCoordinator
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.UUID
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLContext

/**
 * Device Info Service
 * One-to-one translation from iOS Swift Actor to Kotlin with thread-safety
 * Handles device information collection, caching, and synchronization
 */
class DeviceInfoService(
    private val context: Context,
    private val deviceInfoRepository: DeviceInfoRepository,
    private val syncCoordinator: SyncCoordinator?
) {

    private val logger = SDKLogger("DeviceInfoService")
    private val mutex = Mutex()

    private var currentDeviceInfo: DeviceInfoData? = null
    private var lastUpdate: Long = 0
    private val cacheValidityMs = 60 * 60 * 1000L // 1 hour

    /**
     * Get current device info from cache
     * Equivalent to iOS: func getCurrentDeviceInfo() async -> DeviceInfoData?
     */
    suspend fun getCurrentDeviceInfo(): DeviceInfoData? = mutex.withLock {
        if (currentDeviceInfo != null && isCacheValid()) {
            logger.debug("Returning cached device info")
            return currentDeviceInfo
        }

        return loadCurrentDeviceInfo()
    }

    /**
     * Load current device info with caching
     * Equivalent to iOS: func loadCurrentDeviceInfo() async -> DeviceInfoData?
     */
    suspend fun loadCurrentDeviceInfo(): DeviceInfoData? = mutex.withLock {
        logger.debug("Loading current device info")

        try {
            // Try to load from repository first
            val storedInfo = deviceInfoRepository.getCurrentDeviceInfo()

            if (storedInfo != null && isCacheValid(storedInfo.updatedAt)) {
                logger.debug("Using stored device info")
                currentDeviceInfo = storedInfo
                lastUpdate = storedInfo.updatedAt
                return storedInfo
            }

            // Collect fresh device info
            val freshInfo = collectDeviceInfo()
            currentDeviceInfo = freshInfo
            lastUpdate = System.currentTimeMillis()

            // Save to repository
            deviceInfoRepository.saveDeviceInfo(freshInfo)

            logger.info("Device info collected and cached")
            return freshInfo

        } catch (e: Exception) {
            logger.error("Failed to load device info", e)
            return currentDeviceInfo // Return cached if available
        }
    }

    /**
     * Refresh device info by collecting fresh data
     * Equivalent to iOS: func refreshDeviceInfo() async -> DeviceInfoData?
     */
    suspend fun refreshDeviceInfo(): DeviceInfoData? = mutex.withLock {
        logger.debug("Refreshing device info")

        try {
            val freshInfo = collectDeviceInfo()
            currentDeviceInfo = freshInfo
            lastUpdate = System.currentTimeMillis()

            // Save to repository
            deviceInfoRepository.saveDeviceInfo(freshInfo)

            logger.info("Device info refreshed")
            return freshInfo

        } catch (e: Exception) {
            logger.error("Failed to refresh device info", e)
            throw SDKError.ComponentError("DeviceInfoService", "Failed to refresh device info: ${e.message}")
        }
    }

    /**
     * Update device info with functional transform
     * Equivalent to iOS: func updateDeviceInfo(_ updates: (DeviceInfoData) -> DeviceInfoData) async throws
     */
    suspend fun updateDeviceInfo(updates: (DeviceInfoData) -> DeviceInfoData) = mutex.withLock {
        logger.debug("Updating device info")

        val current = currentDeviceInfo ?: throw SDKError.ComponentError("DeviceInfoService", "No current device info available")

        try {
            val updatedInfo = updates(current).copy(
                updatedAt = System.currentTimeMillis()
            )

            currentDeviceInfo = updatedInfo
            lastUpdate = updatedInfo.updatedAt

            // Save to repository
            deviceInfoRepository.saveDeviceInfo(updatedInfo)

            logger.info("Device info updated successfully")

        } catch (e: Exception) {
            logger.error("Failed to update device info", e)
            throw SDKError.ComponentError("DeviceInfoService", "Failed to update device info: ${e.message}")
        }
    }

    /**
     * Sync device info to cloud
     * Equivalent to iOS: func syncToCloud() async throws
     */
    suspend fun syncToCloud() = mutex.withLock {
        logger.debug("Syncing device info to cloud")

        val current = currentDeviceInfo ?: throw SDKError.ComponentError("DeviceInfoService", "No device info to sync")

        try {
            // Use sync coordinator if available
            syncCoordinator?.let { coordinator ->
                coordinator.syncDeviceInfo(current)
            } ?: run {
                // Direct sync without coordinator
                deviceInfoRepository.syncToRemote(current)
            }

            logger.info("Device info synced to cloud successfully")

        } catch (e: Exception) {
            logger.error("Failed to sync device info to cloud", e)
            throw SDKError.NetworkError("Failed to sync device info: ${e.message}")
        }
    }

    /**
     * Generate device fingerprint
     * Equivalent to iOS device fingerprinting
     */
    suspend fun generateDeviceFingerprint(): DeviceFingerprint = mutex.withLock {
        logger.debug("Generating device fingerprint")

        try {
            val hardwareFingerprint = buildString {
                append(Build.BOARD)
                append(Build.BRAND)
                append(Build.DEVICE)
                append(Build.HARDWARE)
                append(Build.MANUFACTURER)
                append(Build.MODEL)
                append(Build.PRODUCT)
            }

            val softwareFingerprint = buildString {
                append(Build.VERSION.SDK_INT)
                append(Build.VERSION.RELEASE)
                append(Build.ID)
                append(Build.DISPLAY)
                append(Build.FINGERPRINT)
            }

            val displayFingerprint = buildString {
                val displayMetrics = context.resources.displayMetrics
                append(displayMetrics.widthPixels)
                append("x")
                append(displayMetrics.heightPixels)
                append("@")
                append(displayMetrics.densityDpi)
            }

            val deviceId = getOrCreateDeviceId()

            return DeviceFingerprint(
                deviceId = deviceId,
                hardwareFingerprint = hardwareFingerprint.hashCode().toString(),
                softwareFingerprint = softwareFingerprint.hashCode().toString(),
                displayFingerprint = displayFingerprint.hashCode().toString()
            )

        } catch (e: Exception) {
            logger.error("Failed to generate device fingerprint", e)
            throw SDKError.ComponentError("DeviceInfoService", "Failed to generate device fingerprint: ${e.message}")
        }
    }

    // Private helper methods

    private suspend fun collectDeviceInfo(): DeviceInfoData {
        logger.debug("Collecting fresh device info")

        val deviceId = getOrCreateDeviceId()
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        return DeviceInfoData(
            deviceId = deviceId,
            deviceName = getDeviceName(),
            systemName = "Android",
            systemVersion = Build.VERSION.RELEASE,
            modelName = Build.MODEL,
            modelIdentifier = Build.DEVICE,

            // CPU information
            cpuType = getCpuType(),
            cpuArchitecture = getCpuArchitecture(),
            cpuCoreCount = getCpuCoreCount(),
            cpuFrequencyMhz = getCpuFrequency(),

            // Memory information
            totalMemoryMB = memInfo.totalMem / (1024 * 1024),
            availableMemoryMB = memInfo.availMem / (1024 * 1024),

            // Storage information
            totalStorageMB = getTotalStorage(),
            availableStorageMB = getAvailableStorage(),

            // GPU information
            gpuType = getGpuType(),
            gpuName = getGpuName(),
            gpuVendor = getGpuVendor(),
            supportsMetal = false, // Not applicable for Android
            supportsVulkan = checkVulkanSupport(),
            supportsOpenCL = checkOpenCLSupport(),

            // Battery information
            batteryLevel = getBatteryLevel(),
            batteryState = getBatteryState(),
            thermalState = getThermalState(),
            isLowPowerMode = isLowPowerMode(),

            // Connectivity
            hasCellular = hasFeature("android.hardware.telephony"),
            hasWifi = hasFeature("android.hardware.wifi"),
            hasBluetooth = hasFeature("android.hardware.bluetooth"),

            // Capabilities
            hasCamera = hasFeature("android.hardware.camera"),
            hasMicrophone = hasFeature("android.hardware.microphone"),
            hasSpeakers = hasFeature("android.hardware.audio.output"),
            hasBiometric = hasFeature("android.hardware.fingerprint") || hasFeature("android.hardware.biometrics.face"),

            // Performance
            benchmarkScore = null, // Could be implemented with benchmarking
            memoryPressure = getMemoryPressure(memInfo)
        )
    }

    private fun getOrCreateDeviceId(): String {
        // Try to get stored device ID
        val prefs = context.getSharedPreferences("runanywhere_device", Context.MODE_PRIVATE)
        var deviceId = prefs.getString("device_id", null)

        if (deviceId == null) {
            // Generate new device ID
            deviceId = UUID.randomUUID().toString()
            prefs.edit().putString("device_id", deviceId).apply()
        }

        return deviceId
    }

    private fun getDeviceName(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL}".trim()
    }

    private fun getCpuType(): String {
        return Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
    }

    private fun getCpuArchitecture(): String {
        return when {
            Build.SUPPORTED_ABIS.any { it.startsWith("arm64") } -> "arm64"
            Build.SUPPORTED_ABIS.any { it.startsWith("arm") } -> "arm"
            Build.SUPPORTED_ABIS.any { it.startsWith("x86_64") } -> "x86_64"
            Build.SUPPORTED_ABIS.any { it.startsWith("x86") } -> "x86"
            else -> "unknown"
        }
    }

    private fun getCpuCoreCount(): Int {
        return Runtime.getRuntime().availableProcessors()
    }

    private fun getCpuFrequency(): Int? {
        return try {
            val cpuInfo = File("/proc/cpuinfo").readText()
            val freqRegex = Regex("cpu MHz\\s*:\\s*(\\d+)")
            freqRegex.find(cpuInfo)?.groupValues?.get(1)?.toInt()
        } catch (e: Exception) {
            null
        }
    }

    private fun getTotalStorage(): Long {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            (stat.blockCountLong * stat.blockSizeLong) / (1024 * 1024)
        } catch (e: Exception) {
            0L
        }
    }

    private fun getAvailableStorage(): Long {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            (stat.availableBlocksLong * stat.blockSizeLong) / (1024 * 1024)
        } catch (e: Exception) {
            0L
        }
    }

    private fun getGpuType(): GPUType {
        val renderer = getGpuRenderer()
        return when {
            renderer.contains("adreno", ignoreCase = true) -> GPUType.ADRENO
            renderer.contains("mali", ignoreCase = true) -> GPUType.MALI
            renderer.contains("powervr", ignoreCase = true) -> GPUType.POWER_VR
            renderer.contains("tegra", ignoreCase = true) -> GPUType.TEGRA
            renderer.contains("vivante", ignoreCase = true) -> GPUType.VIVANTE
            else -> GPUType.UNKNOWN
        }
    }

    private fun getGpuName(): String? {
        return getGpuRenderer().takeIf { it.isNotBlank() }
    }

    private fun getGpuVendor(): String? {
        val vendor = getGpuVendorString()
        return vendor.takeIf { it.isNotBlank() }
    }

    private fun getGpuRenderer(): String {
        return try {
            android.opengl.GLES20.glGetString(android.opengl.GLES20.GL_RENDERER) ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }

    private fun getGpuVendorString(): String {
        return try {
            android.opengl.GLES20.glGetString(android.opengl.GLES20.GL_VENDOR) ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }

    private fun checkVulkanSupport(): Boolean {
        return hasFeature("android.hardware.vulkan.level") && Build.VERSION.SDK_INT >= 24
    }

    private fun checkOpenCLSupport(): Boolean {
        // OpenCL support is not easily detectable on Android
        // This would require native code to check properly
        return false
    }

    private fun getBatteryLevel(): Float? {
        return try {
            val batteryStatus = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) level.toFloat() / scale.toFloat() else null
        } catch (e: Exception) {
            null
        }
    }

    private fun getBatteryState(): BatteryState {
        return try {
            val batteryStatus = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING -> BatteryState.CHARGING
                BatteryManager.BATTERY_STATUS_FULL -> BatteryState.FULL
                BatteryManager.BATTERY_STATUS_NOT_CHARGING,
                BatteryManager.BATTERY_STATUS_DISCHARGING -> BatteryState.UNPLUGGED
                else -> BatteryState.UNKNOWN
            }
        } catch (e: Exception) {
            BatteryState.UNKNOWN
        }
    }

    private fun getThermalState(): ThermalState {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val thermalService = context.getSystemService(Context.THERMAL_SERVICE) as? android.os.PowerManager
            // This would require proper thermal state detection
            ThermalState.NOMINAL
        } else {
            ThermalState.NOMINAL
        }
    }

    private fun isLowPowerMode(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            powerManager.isPowerSaveMode
        } else {
            false
        }
    }

    private fun hasFeature(feature: String): Boolean {
        return context.packageManager.hasSystemFeature(feature)
    }

    private fun getMemoryPressure(memInfo: ActivityManager.MemoryInfo): Float {
        val usedMemory = memInfo.totalMem - memInfo.availMem
        return (usedMemory.toFloat() / memInfo.totalMem.toFloat()).coerceIn(0.0f, 1.0f)
    }

    private fun isCacheValid(timestamp: Long = lastUpdate): Boolean {
        return (System.currentTimeMillis() - timestamp) < cacheValidityMs
    }
}
