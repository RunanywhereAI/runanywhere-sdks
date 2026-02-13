/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Device extension for CppBridge.
 * Provides device registration callbacks for C++ core.
 *
 * Follows iOS CppBridge+Device.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import java.util.Locale
import java.util.UUID

/**
 * Device bridge that provides device registration callbacks for C++ core.
 *
 * The C++ core needs device information and registration status to:
 * - Track device analytics
 * - Manage per-device model assignments
 * - Handle device-specific configurations
 *
 * Usage:
 * - Called during Phase 1 initialization in [CppBridge.initialize]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 */
object CppBridgeDevice {
    /**
     * Device platform type constants matching C++ RAC_PLATFORM_* values.
     */
    object PlatformType {
        const val UNKNOWN = 0
        const val IOS = 1
        const val ANDROID = 2
        const val JVM = 3
        const val LINUX = 4
        const val MACOS = 5
        const val WINDOWS = 6
    }

    /**
     * Device registration status constants.
     */
    object RegistrationStatus {
        const val NOT_REGISTERED = 0
        const val REGISTERING = 1
        const val REGISTERED = 2
        const val FAILED = 3
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var registrationStatus: Int = RegistrationStatus.NOT_REGISTERED

    @Volatile
    private var deviceId: String? = null

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeDevice"

    /**
     * Secure storage key for device ID.
     */
    private const val DEVICE_ID_KEY = "runanywhere_device_id"

    /**
     * Secure storage key for registration status.
     * Used to persist registration status across app restarts.
     */
    private const val REGISTRATION_STATUS_KEY = "runanywhere_device_registered"

    /**
     * Optional listener for device registration events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var deviceListener: DeviceListener? = null

    /**
     * Optional provider for platform-specific device info.
     * Set this to provide accurate device information on Android.
     */
    @Volatile
    var deviceInfoProvider: DeviceInfoProvider? = null

    /**
     * Listener interface for device registration events.
     */
    interface DeviceListener {
        /**
         * Called when device registration starts.
         *
         * @param deviceId The device ID being registered
         */
        fun onRegistrationStarted(deviceId: String)

        /**
         * Called when device registration completes successfully.
         *
         * @param deviceId The registered device ID
         */
        fun onRegistrationCompleted(deviceId: String)

        /**
         * Called when device registration fails.
         *
         * @param deviceId The device ID that failed to register
         * @param errorMessage The error message
         */
        fun onRegistrationFailed(deviceId: String, errorMessage: String)
    }

    /**
     * Provider interface for platform-specific device information.
     *
     * Implement this interface to provide accurate device information
     * on Android (Build.MODEL, Build.VERSION.SDK_INT, etc.).
     *
     * This matches the Swift SDK's DeviceInfo struct fields.
     */
    interface DeviceInfoProvider {
        /**
         * Get the device model name.
         * e.g., "Pixel 8 Pro", "SM-S918U"
         */
        fun getDeviceModel(): String

        /**
         * Get the device manufacturer.
         * e.g., "Google", "Samsung"
         */
        fun getDeviceManufacturer(): String

        /**
         * Get the user-assigned device name.
         * e.g., "John's Phone"
         */
        fun getDeviceName(): String = getDeviceModel()

        /**
         * Get the OS version.
         * e.g., "14" for Android 14
         */
        fun getOSVersion(): String

        /**
         * Get the OS build ID.
         * e.g., "UQ1A.231205.015"
         */
        fun getOSBuildId(): String

        /**
         * Get the SDK version (API level).
         * e.g., 34 for Android 14
         */
        fun getSDKVersion(): Int

        /**
         * Get the device locale.
         * e.g., "en-US"
         */
        fun getLocale(): String

        /**
         * Get the device timezone.
         * e.g., "America/Los_Angeles"
         */
        fun getTimezone(): String

        /**
         * Check if the device is an emulator.
         */
        fun isEmulator(): Boolean

        /**
         * Get the form factor.
         * e.g., "phone", "tablet"
         */
        fun getFormFactor(): String = "phone"

        /**
         * Get the architecture.
         * e.g., "arm64", "x86_64"
         */
        fun getArchitecture(): String

        /**
         * Get the chip/processor name.
         * e.g., "Snapdragon 8 Gen 3", "Tensor G3"
         */
        fun getChipName(): String = "Unknown"

        /**
         * Get total memory in bytes.
         */
        fun getTotalMemory(): Long

        /**
         * Get available memory in bytes.
         */
        fun getAvailableMemory(): Long = getTotalMemory() / 2

        /**
         * Check if device has Neural Engine / NPU.
         */
        fun hasNeuralEngine(): Boolean = false

        /**
         * Get number of Neural Engine cores.
         */
        fun getNeuralEngineCores(): Int = 0

        /**
         * Get GPU family.
         * e.g., "adreno", "mali"
         */
        fun getGPUFamily(): String = "unknown"

        /**
         * Get battery level (0.0 to 1.0, or negative if unavailable).
         */
        fun getBatteryLevel(): Double = -1.0

        /**
         * Get battery state.
         * e.g., "charging", "full", "unplugged"
         */
        fun getBatteryState(): String? = null

        /**
         * Check if low power mode is enabled.
         */
        fun isLowPowerMode(): Boolean = false

        /**
         * Get total CPU cores.
         */
        fun getCoreCount(): Int

        /**
         * Get performance cores.
         */
        fun getPerformanceCores(): Int = getCoreCount() / 2

        /**
         * Get efficiency cores.
         */
        fun getEfficiencyCores(): Int = getCoreCount() - getPerformanceCores()
    }

    /**
     * Register the device callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Initialize device ID if not already set
            initializeDeviceId()

            // Load persisted registration status (prevents re-registering on every app start)
            loadRegistrationStatus()

            // Create device callbacks object for JNI
            val callbacks =
                object {
                    @Suppress("unused")
                    fun getDeviceInfo(): String = getDeviceInfoCallback()

                    @Suppress("unused")
                    fun getDeviceId(): String = getDeviceIdCallback()

                    @Suppress("unused")
                    fun isRegistered(): Boolean = isDeviceRegisteredCallback()

                    @Suppress("unused")
                    fun setRegistered(registered: Boolean) {
                        setRegistrationStatusCallback(
                            if (registered) RegistrationStatus.REGISTERED else RegistrationStatus.NOT_REGISTERED,
                            null,
                        )
                    }

                    @Suppress("unused")
                    fun httpPost(endpoint: String, body: String, requiresAuth: Boolean): Int {
                        // Get environment from telemetry (0=DEV, 1=STAGING, 2=PRODUCTION)
                        val env = CppBridgeTelemetry.currentEnvironment

                        val baseUrl: String?
                        val headers =
                            mutableMapOf(
                                "Content-Type" to "application/json",
                                "Accept" to "application/json",
                            )

                        if (env == 0) {
                            // DEVELOPMENT mode - use Supabase
                            baseUrl =
                                try {
                                    com.runanywhere.sdk.native.bridge.RunAnywhereBridge
                                        .racDevConfigGetSupabaseUrl()
                                } catch (e: Exception) {
                                    null
                                }

                            // Add Supabase-specific headers
                            headers["Prefer"] = "resolution=merge-duplicates"

                            // Add Supabase API key
                            try {
                                val apiKey =
                                    com.runanywhere.sdk.native.bridge.RunAnywhereBridge
                                        .racDevConfigGetSupabaseKey()
                                if (!apiKey.isNullOrEmpty()) {
                                    headers["apikey"] = apiKey
                                    CppBridgePlatformAdapter.logCallback(
                                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                                        TAG,
                                        "Added Supabase apikey header (dev mode)",
                                    )
                                }
                            } catch (e: Exception) {
                                CppBridgePlatformAdapter.logCallback(
                                    CppBridgePlatformAdapter.LogLevel.WARN,
                                    TAG,
                                    "Failed to get Supabase API key: ${e.message}",
                                )
                            }
                        } else {
                            // PRODUCTION/STAGING mode - use Railway backend
                            baseUrl = CppBridgeTelemetry.getBaseUrl()

                            // Add Bearer auth with JWT access token
                            // Use getValidToken() which automatically refreshes if needed
                            val accessToken = CppBridgeAuth.getValidToken()
                            if (!accessToken.isNullOrEmpty()) {
                                headers["Authorization"] = "Bearer $accessToken"
                                CppBridgePlatformAdapter.logCallback(
                                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                                    TAG,
                                    "Added Authorization Bearer header with JWT (prod/staging mode)",
                                )
                            } else {
                                // Fallback to API key if no JWT available
                                val apiKey = CppBridgeTelemetry.getApiKey()
                                if (!apiKey.isNullOrEmpty()) {
                                    headers["Authorization"] = "Bearer $apiKey"
                                    CppBridgePlatformAdapter.logCallback(
                                        CppBridgePlatformAdapter.LogLevel.WARN,
                                        TAG,
                                        "⚠️ No JWT - using API key directly (may fail if backend requires JWT)",
                                    )
                                } else {
                                    CppBridgePlatformAdapter.logCallback(
                                        CppBridgePlatformAdapter.LogLevel.WARN,
                                        TAG,
                                        "⚠️ No access token or API key available for Bearer auth!",
                                    )
                                }
                            }
                        }

                        if (baseUrl.isNullOrEmpty()) {
                            CppBridgePlatformAdapter.logCallback(
                                CppBridgePlatformAdapter.LogLevel.ERROR,
                                TAG,
                                "❌ No base URL configured for device registration (env=$env)",
                            )
                            return -1
                        }

                        // For Supabase (dev mode), add ?on_conflict=device_id for UPSERT
                        // For Railway (prod mode), the backend handles conflict internally
                        val finalEndpoint =
                            if (env == 0) {
                                if (endpoint.contains("?")) "$endpoint&on_conflict=device_id" else "$endpoint?on_conflict=device_id"
                            } else {
                                endpoint
                            }

                        // Build full URL: baseUrl + endpoint path
                        val fullUrl = baseUrl.trimEnd('/') + finalEndpoint

                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.INFO,
                            TAG,
                            "📤 Device registration HTTP POST to: $fullUrl (env=$env)",
                        )

                        // Log request body for debugging
                        val bodyPreview = if (body.length > 200) body.substring(0, 200) + "..." else body
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.DEBUG,
                            TAG,
                            "Device registration body: $bodyPreview",
                        )

                        val (statusCode, response) =
                            CppBridgeTelemetry.sendTelemetry(
                                fullUrl,
                                CppBridgeTelemetry.HttpMethod.POST,
                                headers,
                                body,
                            )

                        if (statusCode in 200..299 || statusCode == 409) {
                            CppBridgePlatformAdapter.logCallback(
                                CppBridgePlatformAdapter.LogLevel.INFO,
                                TAG,
                                "✅ Device registration successful (status=$statusCode)",
                            )
                        } else {
                            CppBridgePlatformAdapter.logCallback(
                                CppBridgePlatformAdapter.LogLevel.ERROR,
                                TAG,
                                "❌ Device registration failed: status=$statusCode, response=$response",
                            )
                        }

                        return statusCode
                    }
                }

            // Register with native
            val result =
                com.runanywhere.sdk.native.bridge.RunAnywhereBridge
                    .racDeviceManagerSetCallbacks(callbacks)

            if (result == 0) {
                isRegistered = true
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Device callbacks registered. Device ID: ${deviceId ?: "unknown"}",
                )
            } else {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to register device callbacks: $result",
                )
            }
        }
    }

    /**
     * Check if the device callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Get the current registration status.
     */
    fun getRegistrationStatus(): Int = registrationStatus

    // ========================================================================
    // DEVICE CALLBACKS
    // ========================================================================

    /**
     * Get device information as a JSON string.
     *
     * Returns device info matching the C++ rac_device_registration_info_t struct
     * and Swift SDK's DeviceInfo struct for proper backend registration.
     *
     * @return JSON-encoded device information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDeviceInfoCallback(): String {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "📱 getDeviceInfoCallback() called - gathering device info...",
        )

        val provider = deviceInfoProvider

        val platform = "android" // String platform for backend
        // Note: detectPlatform() available for future use if needed
        val deviceModel = provider?.getDeviceModel() ?: getDefaultDeviceModel()
        val deviceName = provider?.getDeviceName() ?: deviceModel
        val manufacturer = provider?.getDeviceManufacturer() ?: getDefaultManufacturer()
        val osVersion = provider?.getOSVersion() ?: getDefaultOsVersion()
        val osBuildId = provider?.getOSBuildId() ?: ""
        val androidApiLevel = provider?.getSDKVersion() ?: getDefaultSdkVersion()
        // Use RunAnywhere SDK version string (e.g., "0.1.0"), not Android API level
        val sdkVersionString = com.runanywhere.sdk.utils.SDKConstants.SDK_VERSION
        val locale = provider?.getLocale() ?: Locale.getDefault().toLanguageTag()
        val timezone =
            provider?.getTimezone() ?: java.util.TimeZone
                .getDefault()
                .id
        val isEmulator = provider?.isEmulator() ?: false
        val formFactor = provider?.getFormFactor() ?: "phone"
        val architecture = provider?.getArchitecture() ?: getDefaultArchitecture()
        // Use actual chip name or fallback to a descriptive string, not just architecture
        val chipName = provider?.getChipName() ?: getDefaultChipName(architecture)
        val totalMemory = provider?.getTotalMemory() ?: getDefaultTotalMemory()
        val availableMemory = provider?.getAvailableMemory() ?: (totalMemory / 2)
        val hasNeuralEngine = provider?.hasNeuralEngine() ?: false
        val neuralEngineCores = provider?.getNeuralEngineCores() ?: 0
        val gpuFamily = provider?.getGPUFamily() ?: getDefaultGPUFamily(chipName)
        val batteryLevel = provider?.getBatteryLevel() ?: -1.0
        val batteryState = provider?.getBatteryState()
        val isLowPowerMode = provider?.isLowPowerMode() ?: false
        val coreCount = provider?.getCoreCount() ?: Runtime.getRuntime().availableProcessors()
        val performanceCores = provider?.getPerformanceCores() ?: (coreCount / 2)
        val efficiencyCores = provider?.getEfficiencyCores() ?: (coreCount - performanceCores)
        val deviceIdValue = deviceId ?: ""

        // Log key device info for debugging
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "📱 Device info: model=$deviceModel, os=$osVersion, arch=$architecture, chip=$chipName",
        )

        // Build JSON matching rac_device_registration_info_t struct
        return buildString {
            append("{")
            // Required fields (backend schema)
            append("\"device_id\":\"${escapeJson(deviceIdValue)}\",")
            append("\"device_model\":\"${escapeJson(deviceModel)}\",")
            append("\"device_name\":\"${escapeJson(deviceName)}\",")
            append("\"platform\":\"${escapeJson(platform)}\",")
            append("\"os_version\":\"${escapeJson(osVersion)}\",")
            append("\"form_factor\":\"${escapeJson(formFactor)}\",")
            append("\"architecture\":\"${escapeJson(architecture)}\",")
            append("\"chip_name\":\"${escapeJson(chipName)}\",")
            append("\"total_memory\":$totalMemory,")
            append("\"available_memory\":$availableMemory,")
            append("\"has_neural_engine\":$hasNeuralEngine,")
            append("\"neural_engine_cores\":$neuralEngineCores,")
            append("\"gpu_family\":\"${escapeJson(gpuFamily)}\",")
            append("\"battery_level\":$batteryLevel,")
            if (batteryState != null) {
                append("\"battery_state\":\"${escapeJson(batteryState)}\",")
            } else {
                append("\"battery_state\":null,")
            }
            append("\"is_low_power_mode\":$isLowPowerMode,")
            append("\"core_count\":$coreCount,")
            append("\"performance_cores\":$performanceCores,")
            append("\"efficiency_cores\":$efficiencyCores,")
            append("\"device_fingerprint\":\"${escapeJson(deviceIdValue)}\",")
            // Legacy fields (backward compatibility)
            append("\"device_type\":\"mobile\",")
            append("\"os_name\":\"Android\",")
            append("\"processor_count\":$coreCount,")
            append("\"is_simulator\":$isEmulator,")
            // Additional fields
            append("\"manufacturer\":\"${escapeJson(manufacturer)}\",")
            append("\"os_build_id\":\"${escapeJson(osBuildId)}\",")
            // sdk_version is the RunAnywhere SDK version string (e.g., "0.1.0")
            append("\"sdk_version\":\"${escapeJson(sdkVersionString)}\",")
            // android_api_level is the Android SDK_INT for internal use
            append("\"android_api_level\":$androidApiLevel,")
            append("\"locale\":\"${escapeJson(locale)}\",")
            append("\"timezone\":\"${escapeJson(timezone)}\"")
            append("}")
        }
    }

    /**
     * Get default architecture from system properties.
     * On Android, uses Build.SUPPORTED_ABIS to get the actual ABI string.
     * Returns actual Android ABI: "arm64-v8a", "armeabi-v7a", "x86_64", "x86", etc.
     * Backend accepts: arm64, arm64-v8a, armeabi-v7a, x86_64, x86, unknown
     */
    private fun getDefaultArchitecture(): String {
        // Try to get Android SUPPORTED_ABIS first (returns "arm64-v8a", "armeabi-v7a", etc.)
        try {
            val buildClass = Class.forName("android.os.Build")

            @Suppress("UNCHECKED_CAST")
            val supportedAbis = buildClass.getField("SUPPORTED_ABIS").get(null) as? Array<String>
            if (!supportedAbis.isNullOrEmpty()) {
                return supportedAbis[0] // Return the primary ABI as-is
            }
        } catch (e: Exception) {
            // Fall through to system property
        }

        // Fallback: map JVM os.arch to Android-style ABI strings
        val arch = System.getProperty("os.arch") ?: return "unknown"
        return when {
            arch.contains("aarch64", ignoreCase = true) -> "arm64-v8a"
            arch.contains("arm64", ignoreCase = true) -> "arm64-v8a"
            arch.contains("arm", ignoreCase = true) -> "armeabi-v7a"
            arch.contains("x86_64", ignoreCase = true) -> "x86_64"
            arch.contains("amd64", ignoreCase = true) -> "x86_64"
            arch.contains("x86", ignoreCase = true) -> "x86"
            else -> "unknown"
        }
    }

    /**
     * Get default total memory from system.
     * On Android, uses ActivityManager to get actual device RAM.
     */
    private fun getDefaultTotalMemory(): Long {
        // Try to get actual device memory via ActivityManager
        try {
            val contextClass = Class.forName("android.content.Context")
            val activityServiceField = contextClass.getField("ACTIVITY_SERVICE")
            val activityService = activityServiceField.get(null) as String

            // Get application context
            val activityThreadClass = Class.forName("android.app.ActivityThread")
            val currentAppMethod = activityThreadClass.getMethod("currentApplication")
            val context = currentAppMethod.invoke(null)

            if (context != null) {
                val getSystemServiceMethod = contextClass.getMethod("getSystemService", String::class.java)
                val activityManager = getSystemServiceMethod.invoke(context, activityService)

                if (activityManager != null) {
                    val memInfoClass = Class.forName("android.app.ActivityManager\$MemoryInfo")
                    val memInfo = memInfoClass.getDeclaredConstructor().newInstance()

                    val getMemInfoMethod = activityManager.javaClass.getMethod("getMemoryInfo", memInfoClass)
                    getMemInfoMethod.invoke(activityManager, memInfo)

                    val totalMemField = memInfoClass.getField("totalMem")
                    return totalMemField.getLong(memInfo)
                }
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Could not get device memory via ActivityManager: ${e.message}",
            )
        }

        // Fallback to JVM max memory (less accurate)
        return Runtime.getRuntime().maxMemory()
    }

    /**
     * Get default chip name based on architecture and device info.
     * Tries to read from /proc/cpuinfo or Build.HARDWARE.
     */
    private fun getDefaultChipName(architecture: String): String {
        // Try to get from Build.HARDWARE
        try {
            val buildClass = Class.forName("android.os.Build")
            val hardware = buildClass.getField("HARDWARE").get(null) as? String
            if (!hardware.isNullOrEmpty() && hardware != "unknown") {
                return hardware
            }
        } catch (e: Exception) {
            // Fall through
        }

        // Try to read from /proc/cpuinfo
        try {
            val cpuInfo = java.io.File("/proc/cpuinfo").readText()
            // Look for "Hardware" line
            val hardwareLine = cpuInfo.lines().find { it.startsWith("Hardware", ignoreCase = true) }
            if (hardwareLine != null) {
                val chipName = hardwareLine.substringAfter(":").trim()
                if (chipName.isNotEmpty()) {
                    return chipName
                }
            }
        } catch (e: Exception) {
            // Fall through
        }

        // Fallback to architecture as last resort
        return architecture
    }

    /**
     * Get default GPU family based on chip name.
     * Infers GPU vendor from known chip manufacturers:
     * - Samsung Exynos → Mali
     * - Qualcomm Snapdragon → Adreno
     * - MediaTek → Mali (mostly)
     * - HiSilicon Kirin → Mali
     * - Google Tensor → Mali
     * - Apple → Apple
     */
    private fun getDefaultGPUFamily(chipName: String): String {
        val chipLower = chipName.lowercase()

        return when {
            // Samsung Exynos uses Mali GPUs
            chipLower.contains("exynos") -> "mali"
            chipLower.startsWith("s5e") -> "mali" // Samsung internal chip naming (e.g., s5e8535)
            chipLower.contains("samsung") -> "mali"

            // Qualcomm Snapdragon uses Adreno GPUs
            chipLower.contains("snapdragon") -> "adreno"
            chipLower.contains("qualcomm") -> "adreno"
            chipLower.contains("sdm") -> "adreno" // SDM845, SDM855, etc.
            chipLower.contains("sm8") -> "adreno" // SM8150, SM8250, etc.
            chipLower.contains("sm7") -> "adreno" // SM7150, etc.
            chipLower.contains("sm6") -> "adreno" // SM6150, etc.
            chipLower.contains("msm") -> "adreno" // Older MSM chips

            // MediaTek uses Mali GPUs (mostly)
            chipLower.contains("mediatek") -> "mali"
            chipLower.contains("mt6") -> "mali" // MT6xxx series
            chipLower.contains("mt8") -> "mali" // MT8xxx series
            chipLower.contains("dimensity") -> "mali"
            chipLower.contains("helio") -> "mali"

            // HiSilicon Kirin uses Mali GPUs
            chipLower.contains("kirin") -> "mali"
            chipLower.contains("hisilicon") -> "mali"

            // Google Tensor uses Mali GPUs
            chipLower.contains("tensor") -> "mali"
            chipLower.contains("gs1") -> "mali" // GS101 (Tensor)
            chipLower.contains("gs2") -> "mali" // GS201 (Tensor G2)

            // Intel/x86 GPUs
            chipLower.contains("intel") -> "intel"

            // NVIDIA (rare on mobile)
            chipLower.contains("nvidia") -> "nvidia"
            chipLower.contains("tegra") -> "nvidia"

            else -> "unknown"
        }
    }

    /**
     * Get the unique device identifier.
     *
     * Returns a persistent device ID that is:
     * - Unique per device installation
     * - Persisted across app restarts
     * - Used for analytics and device registration
     *
     * @return The device ID string
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDeviceIdCallback(): String {
        return deviceId ?: run {
            initializeDeviceId()
            deviceId ?: ""
        }
    }

    /**
     * Check if the device is registered with the backend.
     *
     * **Production/Staging mode**: Returns persisted status.
     * - First launch: returns false → device registers once with full info
     * - Subsequent launches: returns true → skips registration (already done)
     *
     * **Development mode**: Always returns false to trigger UPSERT.
     * - Supabase uses UPSERT (`?on_conflict=device_id`) which updates existing records
     * - This ensures device info is always fresh during development
     *
     * @return true if already registered (prod/staging), false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isDeviceRegisteredCallback(): Boolean {
        // Get current environment from telemetry (0=DEV, 1=STAGING, 2=PRODUCTION)
        val env = CppBridgeTelemetry.currentEnvironment

        // For DEVELOPMENT mode (env=0): Always return false to trigger UPSERT
        // Supabase handles duplicates gracefully with ?on_conflict=device_id
        if (env == 0) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "isDeviceRegisteredCallback: dev mode → returning false (UPSERT always)",
            )
            return false
        }

        // For PRODUCTION/STAGING mode (env != 0): Return persisted status
        // - First launch: NOT_REGISTERED → returns false → registers once
        // - Subsequent launches: REGISTERED → returns true → skips registration
        val isRegistered = registrationStatus == RegistrationStatus.REGISTERED
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "isDeviceRegisteredCallback: prod/staging mode → returning $isRegistered (register once)",
        )
        return isRegistered
    }

    /**
     * Set the device registration status.
     *
     * Called by C++ core when device registration status changes.
     *
     * @param status The new registration status (see [RegistrationStatus])
     * @param errorMessage Optional error message if status is FAILED
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setRegistrationStatusCallback(status: Int, errorMessage: String?) {
        val previousStatus = registrationStatus
        registrationStatus = status

        val deviceIdValue = deviceId ?: ""

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Registration status changed: $previousStatus -> $status",
        )

        // Persist registration status so we don't re-register on every app restart
        if (status == RegistrationStatus.REGISTERED) {
            persistRegistrationStatus(true)
        } else if (status == RegistrationStatus.NOT_REGISTERED) {
            persistRegistrationStatus(false)
        }

        // Notify listener
        try {
            when (status) {
                RegistrationStatus.REGISTERING -> {
                    deviceListener?.onRegistrationStarted(deviceIdValue)
                }
                RegistrationStatus.REGISTERED -> {
                    deviceListener?.onRegistrationCompleted(deviceIdValue)
                }
                RegistrationStatus.FAILED -> {
                    deviceListener?.onRegistrationFailed(
                        deviceIdValue,
                        errorMessage ?: "Unknown error",
                    )
                }
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in device listener: ${e.message}",
            )
        }
    }

    /**
     * HTTP POST callback for device registration requests.
     *
     * Called by C++ core to send device registration data to the backend.
     * This is used when the C++ telemetry HTTP callback is not yet available.
     *
     * @param url The registration endpoint URL
     * @param body The request body (JSON)
     * @param headers JSON-encoded headers map
     * @param completionCallbackId ID for the C++ completion callback
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun httpPostCallback(
        url: String,
        body: String,
        headers: String?,
        completionCallbackId: Long,
    ) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Device registration POST to: $url",
        )

        // Delegate to telemetry HTTP callback if available
        CppBridgeTelemetry.httpCallback(
            requestId = "device-registration-${System.currentTimeMillis()}",
            url = url,
            method = CppBridgeTelemetry.HttpMethod.POST,
            headers = headers,
            body = body,
            completionCallbackId = completionCallbackId,
        )
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the device callbacks with C++ core.
     *
     * Registers [getDeviceInfoCallback], [getDeviceIdCallback],
     * [isDeviceRegisteredCallback], [setRegistrationStatusCallback],
     * and [httpPostCallback] with C++ core.
     * Reserved for future native callback integration.
     *
     * C API: rac_device_set_callbacks(...)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeSetDeviceCallbacks()

    /**
     * Native method to unset the device callbacks.
     *
     * Called during shutdown to clean up native resources.
     * Reserved for future native callback integration.
     *
     * C API: rac_device_set_callbacks(nullptr)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnsetDeviceCallbacks()

    /**
     * Native method to trigger device registration with backend.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_device_register()
     */
    @JvmStatic
    external fun nativeRegisterDevice(): Int

    /**
     * Native method to check if device needs re-registration.
     *
     * @return true if registration is needed
     *
     * C API: rac_device_needs_registration()
     */
    @JvmStatic
    external fun nativeNeedsRegistration(): Boolean

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the device callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // Clear native callbacks by setting null
            // This is handled by the JNI layer

            deviceListener = null
            registrationStatus = RegistrationStatus.NOT_REGISTERED
            isRegistered = false

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Device callbacks unregistered",
            )
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Initialize or retrieve the device ID.
     *
     * First checks secure storage for an existing ID.
     * If not found, generates a new UUID and stores it.
     */
    private fun initializeDeviceId() {
        if (deviceId != null) {
            return
        }

        // Try to load from secure storage
        val storedId = CppBridgePlatformAdapter.secureGetCallback(DEVICE_ID_KEY)
        if (storedId != null) {
            deviceId = String(storedId, Charsets.UTF_8)
            return
        }

        // Generate new ID
        val newId = UUID.randomUUID().toString()
        deviceId = newId

        // Store in secure storage
        CppBridgePlatformAdapter.secureSetCallback(
            DEVICE_ID_KEY,
            newId.toByteArray(Charsets.UTF_8),
        )

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Generated new device ID: $newId",
        )
    }

    /**
     * Load persisted registration status from secure storage.
     *
     * NOTE: For production/staging modes, we don't rely solely on local persistence
     * to skip registration. The C++ layer and backend handle the logic:
     * - C++ checks if device is registered via callback
     * - Backend supports upsert/update of device info
     * - Full device info should be sent at least once per installation
     *
     * For development mode (Supabase), UPSERT is used so we can always register.
     */
    private fun loadRegistrationStatus() {
        val storedStatus = CppBridgePlatformAdapter.secureGetCallback(REGISTRATION_STATUS_KEY)
        if (storedStatus != null) {
            val statusStr = String(storedStatus, Charsets.UTF_8)
            if (statusStr == "true" || statusStr == "1") {
                // For development mode, we trust the persisted status
                // For production/staging, we'll let the C++ layer decide
                // but we still load the status for informational purposes
                registrationStatus = RegistrationStatus.REGISTERED
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.INFO,
                    TAG,
                    "📋 Loaded persisted registration status: REGISTERED",
                )
            }
        }
    }

    /**
     * Persist registration status to secure storage.
     *
     * @param isRegistered Whether the device is registered
     */
    private fun persistRegistrationStatus(isRegistered: Boolean) {
        val value = if (isRegistered) "true" else "false"
        CppBridgePlatformAdapter.secureSetCallback(
            REGISTRATION_STATUS_KEY,
            value.toByteArray(Charsets.UTF_8),
        )
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Persisted registration status: $value",
        )
    }

    /**
     * Manually set the device ID.
     *
     * Useful for testing or when migrating from another ID system.
     *
     * @param id The device ID to set
     */
    fun setDeviceId(id: String) {
        synchronized(lock) {
            deviceId = id
            CppBridgePlatformAdapter.secureSetCallback(
                DEVICE_ID_KEY,
                id.toByteArray(Charsets.UTF_8),
            )
        }
    }

    /**
     * Get the current device ID without initializing.
     *
     * @return The device ID, or null if not initialized
     */
    fun getDeviceId(): String? = deviceId

    /**
     * Trigger device registration with the backend.
     *
     * This should be called after SDK initialization when the app is ready
     * to register the device.
     *
     * @param environment SDK environment (0=DEVELOPMENT, 1=STAGING, 2=PRODUCTION)
     * @param buildToken Optional build token for development mode
     * @return true if registration was triggered, false if already registered or failed
     */
    fun triggerRegistration(environment: Int = 0, buildToken: String? = null): Boolean {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "📱 triggerRegistration called: env=$environment, buildToken=${if (buildToken != null) "present (${buildToken.length} chars)" else "null"}",
        )

        if (!isRegistered) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "❌ Cannot trigger registration: device callbacks not registered",
            )
            return false
        }

        // NOTE: Unlike development mode, we don't skip registration for production/staging
        // based on local registrationStatus. This matches Swift SDK behavior where the C++
        // layer handles all the logic via rac_device_manager_register_if_needed().
        //
        // For production/staging (env != 0):
        // - The C++ code will skip if already registered (performance optimization)
        // - But we need to call it at least once to send full device info
        // - Authentication only creates a basic device record
        //
        // For development (env == 0):
        // - The C++ code uses UPSERT to always update (track active devices)
        // - We still call every time to update last_seen_at

        if (registrationStatus == RegistrationStatus.REGISTERING) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "⏳ Device registration already in progress",
            )
            return true
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "📤 Calling racDeviceManagerRegisterIfNeeded...",
        )

        // Call native registration
        val result =
            com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racDeviceManagerRegisterIfNeeded(
                environment,
                buildToken,
            )

        val resultMessage =
            when (result) {
                0 -> "✅ SUCCESS"
                1 -> "⚠️ Already registered"
                else -> "❌ ERROR (code=$result)"
            }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Device registration result: $resultMessage",
        )

        return result == 0
    }

    /**
     * Check if device is registered with backend.
     * Calls native method to get current status.
     */
    fun checkIsRegistered(): Boolean {
        return com.runanywhere.sdk.native.bridge.RunAnywhereBridge
            .racDeviceManagerIsRegistered()
    }

    /**
     * Clear device registration status.
     */
    fun clearRegistration() {
        com.runanywhere.sdk.native.bridge.RunAnywhereBridge
            .racDeviceManagerClearRegistration()
        registrationStatus = RegistrationStatus.NOT_REGISTERED
    }

    /**
     * Get native device ID from C++ device manager.
     */
    fun getNativeDeviceId(): String? {
        return com.runanywhere.sdk.native.bridge.RunAnywhereBridge
            .racDeviceManagerGetDeviceId()
    }

    /**
     * Detect the current platform type.
     * Reserved for future platform-specific handling.
     */
    @Suppress("unused")
    private fun detectPlatform(): Int {
        val osName = System.getProperty("os.name")?.lowercase() ?: ""
        val javaVendor = System.getProperty("java.vendor")?.lowercase() ?: ""
        val vmName = System.getProperty("java.vm.name")?.lowercase() ?: ""

        return when {
            // Check for Android runtime
            vmName.contains("dalvik") || vmName.contains("art") -> PlatformType.ANDROID
            javaVendor.contains("android") -> PlatformType.ANDROID

            // Check OS
            osName.contains("mac") || osName.contains("darwin") -> PlatformType.MACOS
            osName.contains("linux") -> PlatformType.LINUX
            osName.contains("win") -> PlatformType.WINDOWS

            // Default to JVM
            else -> PlatformType.JVM
        }
    }

    /**
     * Get default device model for JVM environment.
     */
    private fun getDefaultDeviceModel(): String {
        // Try to get from Android Build class via reflection
        return try {
            val buildClass = Class.forName("android.os.Build")
            buildClass.getField("MODEL").get(null) as? String ?: "unknown"
        } catch (e: Exception) {
            System.getProperty("os.name") ?: "unknown"
        }
    }

    /**
     * Get default manufacturer for JVM/Android environment.
     */
    private fun getDefaultManufacturer(): String {
        // Try to get from Android Build class via reflection
        return try {
            val buildClass = Class.forName("android.os.Build")
            buildClass.getField("MANUFACTURER").get(null) as? String ?: "unknown"
        } catch (e: Exception) {
            System.getProperty("java.vendor") ?: "unknown"
        }
    }

    /**
     * Get default OS version for Android.
     */
    private fun getDefaultOsVersion(): String {
        return try {
            val versionClass = Class.forName("android.os.Build\$VERSION")
            versionClass.getField("RELEASE").get(null) as? String ?: "unknown"
        } catch (e: Exception) {
            System.getProperty("os.version") ?: "unknown"
        }
    }

    /**
     * Get default SDK/API version for Android.
     */
    private fun getDefaultSdkVersion(): Int {
        return try {
            val versionClass = Class.forName("android.os.Build\$VERSION")
            versionClass.getField("SDK_INT").get(null) as? Int ?: 0
        } catch (e: Exception) {
            0
        }
    }

    /**
     * Escape special characters for JSON string.
     */
    private fun escapeJson(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}
