/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Device extension for CppBridge.
 *
 * Mirrors Swift `CppBridge+Device.swift`: a thin glue layer that wires
 * a callback bag into the C++ device manager (`rac_device_manager_*`)
 * and exposes the four registration-state thunks. ALL business logic
 * (when to register, dev-vs-prod routing, JSON payload assembly,
 * retry/backoff, last-seen tracking) lives in commons. Kotlin only
 * provides:
 *
 *   1. The platform device id (UUID persisted in secure storage) —
 *      commons has no `rac_device_get_or_create_persistent_id` JNI
 *      binding yet (TODO: KOT-W5-DEVICE-IDJNI), so we keep the Kotlin
 *      side resolver. Swift delegates to commons directly.
 *   2. Android-only device-info reflection (Build.MODEL, MANUFACTURER,
 *      VERSION.RELEASE, SDK_INT). Architecture / chip name / total
 *      memory / GPU family already live in [CppBridgeHardware].
 *   3. The five JNI callback methods that commons invokes
 *      (`getDeviceInfo` / `getDeviceId` / `isRegistered` /
 *      `setRegistered` / `httpPost`) wired through the existing
 *      `CppBridgeEnvironment`, `CppBridgeEndpoints`,
 *      `CppBridgeTelemetry`, `CppBridgeAuth` extensions.
 *
 * iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/
 *     Extensions/CppBridge+Device.swift
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.util.Locale
import java.util.UUID

object CppBridgeDevice {

    private const val TAG = "CppBridgeDevice"
    private const val DEVICE_ID_KEY = "runanywhere_device_id"
    private const val REGISTRATION_STATUS_KEY = "runanywhere_device_registered"

    @Volatile
    private var callbacksRegistered: Boolean = false

    @Volatile
    private var deviceId: String? = null

    /** Mirrors Swift's `UserDefaults` flag used by the `is_registered`
     *  / `set_registered` callbacks. Persisted in secure storage. */
    @Volatile
    private var deviceRegistered: Boolean = false

    private val lock = Any()

    /**
     * Optional provider for platform-specific device info. Set this
     * before [register] to override the reflection-based defaults
     * (Build.MODEL / MANUFACTURER / VERSION.RELEASE / SDK_INT).
     */
    @Volatile
    var deviceInfoProvider: DeviceInfoProvider? = null

    /**
     * Provider interface for platform-specific device information.
     * Mirrors fields populated by Swift's `DeviceInfo.current`.
     */
    interface DeviceInfoProvider {
        fun getDeviceModel(): String
        fun getDeviceManufacturer(): String
        fun getDeviceName(): String = getDeviceModel()
        fun getOSVersion(): String
        fun getOSBuildId(): String
        fun getSDKVersion(): Int
        fun getLocale(): String
        fun getTimezone(): String
        fun isEmulator(): Boolean
        fun getFormFactor(): String = "phone"
        fun getArchitecture(): String
        fun getChipName(): String = "Unknown"
        fun getTotalMemory(): Long
        fun getAvailableMemory(): Long = getTotalMemory() / 2
        fun hasNeuralEngine(): Boolean = false
        fun getNeuralEngineCores(): Int = 0
        fun getGPUFamily(): String = "unknown"
        fun getBatteryLevel(): Double = -1.0
        fun getBatteryState(): String? = null
        fun isLowPowerMode(): Boolean = false
        fun getCoreCount(): Int
        fun getPerformanceCores(): Int = getCoreCount() / 2
        fun getEfficiencyCores(): Int = getCoreCount() - getPerformanceCores()
    }

    // ========================================================================
    // PUBLIC API
    // ========================================================================

    /**
     * Register the JNI callback bag with the C++ device manager.
     *
     * Mirrors Swift `CppBridge.Device.register()`. Safe to call
     * multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (callbacksRegistered) return

            initializeDeviceId()
            loadRegistrationStatus()

            val callbacks = object {
                @Suppress("unused")
                fun getDeviceInfo(): String = getDeviceInfoCallback()

                @Suppress("unused")
                fun getDeviceId(): String = getDeviceIdCallback()

                @Suppress("unused")
                fun isRegistered(): Boolean = isDeviceRegisteredCallback()

                @Suppress("unused")
                fun setRegistered(registered: Boolean) =
                    setRegisteredCallback(registered)

                @Suppress("unused")
                fun httpPost(endpoint: String, body: String, requiresAuth: Boolean): Int =
                    httpPostCallback(endpoint, body, requiresAuth)
            }

            val result = RunAnywhereBridge.racDeviceManagerSetCallbacks(callbacks)
            if (result == 0) {
                callbacksRegistered = true
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Device manager callbacks registered. Device ID: ${deviceId ?: "unknown"}",
                )
            } else {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to register device manager callbacks: $result",
                )
            }
        }
    }

    /**
     * Unregister callbacks and reset state. Called from
     * [com.runanywhere.sdk.foundation.bridge.CppBridge.shutdown].
     */
    fun unregister() {
        synchronized(lock) {
            if (!callbacksRegistered) return
            callbacksRegistered = false
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Device manager callbacks unregistered",
            )
        }
    }

    /** Are JNI callbacks currently wired? */
    fun isRegistered(): Boolean = callbacksRegistered

    /** Current device id without re-initialising. */
    fun getDeviceId(): String? = deviceId

    /**
     * Trigger device registration with the backend. Thin wrapper over
     * `rac_device_manager_register_if_needed` — commons handles every
     * policy decision (skip-if-registered, dev UPSERT, full payload
     * assembly, retry). Mirrors Swift's
     * `CppBridge.Device.registerIfNeeded(environment:)`.
     *
     * @return `true` when commons reported success (or already-done).
     */
    fun triggerRegistration(environment: Int, buildToken: String? = null): Boolean {
        if (!callbacksRegistered) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Cannot trigger registration: device callbacks not registered",
            )
            return false
        }
        if (!CppBridgeTelemetry.hasUsableNetworkConfig(environment)) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Skipping device registration: no usable external config (env=$environment)",
            )
            return false
        }

        val result = RunAnywhereBridge.racDeviceManagerRegisterIfNeeded(environment, buildToken)
        return result == 0
    }

    // ========================================================================
    // JNI CALLBACKS (invoked by commons through `rac_device_callbacks_t`)
    // ========================================================================

    @JvmStatic
    fun getDeviceIdCallback(): String {
        return deviceId ?: run {
            initializeDeviceId()
            deviceId ?: ""
        }
    }

    /**
     * Device-info JSON callback. The C++ side parses the returned
     * string into `rac_device_registration_info_t`. Mirrors Swift's
     * direct pointer fill in `register()` — JSON is the JNI-friendly
     * equivalent of populating the C struct fields.
     */
    @JvmStatic
    fun getDeviceInfoCallback(): String {
        val provider = deviceInfoProvider

        val deviceModel = provider?.getDeviceModel() ?: getDefaultDeviceModel()
        val deviceName = provider?.getDeviceName() ?: deviceModel
        val manufacturer = provider?.getDeviceManufacturer() ?: getDefaultManufacturer()
        val osVersion = provider?.getOSVersion() ?: getDefaultOsVersion()
        val osBuildId = provider?.getOSBuildId() ?: ""
        val androidApiLevel = provider?.getSDKVersion() ?: getDefaultSdkVersion()
        val sdkVersionString = com.runanywhere.sdk.foundation.constants.SDKConstants.SDK_VERSION
        val locale = provider?.getLocale() ?: Locale.getDefault().toLanguageTag()
        val timezone = provider?.getTimezone() ?: java.util.TimeZone.getDefault().id
        val isEmulator = provider?.isEmulator() ?: false
        val formFactor = provider?.getFormFactor() ?: "phone"
        val architecture = provider?.getArchitecture() ?: CppBridgeHardware.defaultArchitecture()
        val chipName = provider?.getChipName() ?: CppBridgeHardware.defaultChipName(architecture)
        val totalMemory = provider?.getTotalMemory() ?: CppBridgeHardware.defaultTotalMemory()
        val availableMemory = provider?.getAvailableMemory() ?: (totalMemory / 2)
        val hasNeuralEngine = provider?.hasNeuralEngine() ?: false
        val neuralEngineCores = provider?.getNeuralEngineCores() ?: 0
        val gpuFamily = provider?.getGPUFamily() ?: CppBridgeHardware.defaultGpuFamily(chipName)
        val batteryLevel = provider?.getBatteryLevel() ?: -1.0
        val batteryState = provider?.getBatteryState()
        val isLowPowerMode = provider?.isLowPowerMode() ?: false
        val coreCount = provider?.getCoreCount() ?: Runtime.getRuntime().availableProcessors()
        val performanceCores = provider?.getPerformanceCores() ?: (coreCount / 2)
        val efficiencyCores = provider?.getEfficiencyCores() ?: (coreCount - performanceCores)
        val deviceIdValue = deviceId ?: ""

        return buildString {
            append("{")
            append("\"device_id\":\"${escapeJson(deviceIdValue)}\",")
            append("\"device_model\":\"${escapeJson(deviceModel)}\",")
            append("\"device_name\":\"${escapeJson(deviceName)}\",")
            append("\"platform\":\"android\",")
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
            append("\"device_type\":\"mobile\",")
            append("\"os_name\":\"Android\",")
            append("\"processor_count\":$coreCount,")
            append("\"is_simulator\":$isEmulator,")
            append("\"manufacturer\":\"${escapeJson(manufacturer)}\",")
            append("\"os_build_id\":\"${escapeJson(osBuildId)}\",")
            append("\"sdk_version\":\"${escapeJson(sdkVersionString)}\",")
            append("\"android_api_level\":$androidApiLevel,")
            append("\"locale\":\"${escapeJson(locale)}\",")
            append("\"timezone\":\"${escapeJson(timezone)}\"")
            append("}")
        }
    }

    /**
     * Mirrors Swift's `UserDefaults` lookup: dev mode always returns
     * `false` so commons performs the Supabase UPSERT every launch;
     * prod/staging consults the persisted flag so we only send the
     * full payload once per installation.
     */
    @JvmStatic
    fun isDeviceRegisteredCallback(): Boolean {
        if (CppBridgeTelemetry.currentEnvironment == 0) return false
        return deviceRegistered
    }

    /**
     * Mirrors Swift's `UserDefaults.set(_, forKey:)` on the registered
     * key. Persisted via the platform secure storage so the value
     * survives process restarts.
     */
    @JvmStatic
    fun setRegisteredCallback(registered: Boolean) {
        deviceRegistered = registered
        persistRegistrationStatus(registered)
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Device registration flag updated: $registered",
        )
    }

    /**
     * HTTP POST callback used by `rac_device_manager_register_if_needed`.
     * Mirrors Swift's `callbacks.http_post = { ... CppBridge.HTTP.shared.postRaw(...) }`.
     *
     * Commons hands us a relative endpoint path; we resolve dev-vs-prod
     * base URL, auth header, and Supabase UPSERT mode using the existing
     * extensions (`CppBridgeEnvironment` / `CppBridgeDevConfig` /
     * `CppBridgeTelemetry`). The returned int is the HTTP status code
     * (or `-1` for transport/configuration failure).
     */
    @JvmStatic
    fun httpPostCallback(endpoint: String, body: String, @Suppress("UNUSED_PARAMETER") requiresAuth: Boolean): Int {
        val env = CppBridgeTelemetry.currentEnvironment
        val baseUrl: String?
        val headers = mutableMapOf(
            "Content-Type" to "application/json",
            "Accept" to "application/json",
        )

        if (env == 0) {
            baseUrl = CppBridgeDevConfig.supabaseURL
            if (!CppBridgeDevConfig.isUsableHTTPURL(baseUrl)) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Skipping dev device registration: Supabase URL missing/placeholder",
                )
                return -1
            }
            headers["Prefer"] = "resolution=merge-duplicates"
            CppBridgeDevConfig.supabaseKey
                ?.takeIf { CppBridgeDevConfig.isUsableCredential(it) }
                ?.let { headers["apikey"] = it }
        } else {
            baseUrl = CppBridgeTelemetry.getBaseUrl()
            if (!CppBridgeDevConfig.isUsableHTTPURL(baseUrl)) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Skipping device registration: base URL missing/placeholder",
                )
                return -1
            }
            val token = CppBridgeAuth.getValidToken()
            val authValue = if (!token.isNullOrEmpty()) token else CppBridgeTelemetry.getApiKey()
            if (!authValue.isNullOrEmpty()) {
                headers["Authorization"] = "Bearer $authValue"
            }
        }

        if (baseUrl.isNullOrEmpty()) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "No base URL configured for device registration (env=$env)",
            )
            return -1
        }

        val finalEndpoint = if (env == 0) {
            if (endpoint.contains("?")) "$endpoint&on_conflict=device_id" else "$endpoint?on_conflict=device_id"
        } else {
            endpoint
        }
        val fullUrl = baseUrl.trimEnd('/') + finalEndpoint

        // Synchronous POST via the native curl-backed client. We deliberately
        // bypass HTTPClientAdapter here because commons hands us a
        // pre-resolved endpoint + auth header set and the JNI caller is
        // synchronous (no coroutine context). All callers of this Kotlin
        // shim are inside `rac_device_manager_register_if_needed`.
        val resp = RunAnywhereBridge.racHttpRequestExecute(
            method = "POST",
            url = fullUrl,
            headerKeys = headers.keys.toTypedArray(),
            headerValues = headers.values.toTypedArray(),
            body = body.encodeToByteArray(),
            timeoutMs = 30_000,
            followRedirects = true,
        )
        val statusCode = resp?.statusCode ?: -1
        val response = resp?.bodyAsString()
        if (resp?.errorMessage != null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Device registration transport error for $fullUrl: ${resp.errorMessage}",
            )
        } else if (statusCode in 200..299 || statusCode == 409) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Device registration POST $fullUrl → $statusCode",
            )
        } else {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Device registration POST $fullUrl → $statusCode body=$response",
            )
        }
        return statusCode
    }

    // ========================================================================
    // PRIVATE HELPERS
    // ========================================================================

    /**
     * Initialise or load the persistent device id.
     *
     * TODO(KOT-W5-DEVICE-IDJNI): Swift delegates to
     * `rac_device_get_or_create_persistent_id` for a canonical
     * Keychain → vendor-id → UUID resolution chain. Kotlin has no
     * matching JNI thunk today, so we keep the local UUID +
     * secure-storage resolver. Wire the JNI binding when commons
     * exposes it and replace this with a single `racDeviceGetOrCreatePersistentId`.
     */
    private fun initializeDeviceId() {
        if (deviceId != null) return

        val stored = CppBridgePlatformAdapter.secureGetCallback(DEVICE_ID_KEY)
        if (stored != null) {
            deviceId = String(stored, Charsets.UTF_8)
            return
        }

        val newId = UUID.randomUUID().toString()
        deviceId = newId
        CppBridgePlatformAdapter.secureSetCallback(DEVICE_ID_KEY, newId.toByteArray(Charsets.UTF_8))
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Generated new device ID: $newId",
        )
    }

    /** Load persisted `device_registered` flag from secure storage. */
    private fun loadRegistrationStatus() {
        val stored = CppBridgePlatformAdapter.secureGetCallback(REGISTRATION_STATUS_KEY) ?: return
        val v = String(stored, Charsets.UTF_8)
        if (v == "true" || v == "1") deviceRegistered = true
    }

    /** Persist `device_registered` flag through secure storage. */
    private fun persistRegistrationStatus(registered: Boolean) {
        CppBridgePlatformAdapter.secureSetCallback(
            REGISTRATION_STATUS_KEY,
            (if (registered) "true" else "false").toByteArray(Charsets.UTF_8),
        )
    }

    /** Android-specific Build.MODEL fallback via reflection. */
    private fun getDefaultDeviceModel(): String =
        try {
            Class.forName("android.os.Build").getField("MODEL").get(null) as? String ?: "unknown"
        } catch (_: Exception) {
            System.getProperty("os.name") ?: "unknown"
        }

    /** Android-specific Build.MANUFACTURER fallback via reflection. */
    private fun getDefaultManufacturer(): String =
        try {
            Class.forName("android.os.Build").getField("MANUFACTURER").get(null) as? String ?: "unknown"
        } catch (_: Exception) {
            System.getProperty("java.vendor") ?: "unknown"
        }

    /** Android-specific Build.VERSION.RELEASE fallback via reflection. */
    private fun getDefaultOsVersion(): String =
        try {
            Class.forName("android.os.Build\$VERSION").getField("RELEASE").get(null) as? String ?: "unknown"
        } catch (_: Exception) {
            System.getProperty("os.version") ?: "unknown"
        }

    /** Android-specific Build.VERSION.SDK_INT fallback via reflection. */
    private fun getDefaultSdkVersion(): Int =
        try {
            Class.forName("android.os.Build\$VERSION").getField("SDK_INT").get(null) as? Int ?: 0
        } catch (_: Exception) {
            0
        }

    /** Escape special chars for embedding in a JSON string value. */
    private fun escapeJson(value: String): String =
        value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
}
