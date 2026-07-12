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

import ai.runanywhere.proto.v1.DeviceInfo
import com.runanywhere.sdk.foundation.bridge.HTTPClientAdapter
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import kotlinx.coroutines.runBlocking
import java.util.Locale

object CppBridgeDevice {
    private const val TAG = "CppBridgeDevice"

    // Note: device_id persistence now owned by commons via
    // `rac_device_get_or_create_persistent_id` (mirrors Swift). Only the
    // registration-status flag is still persisted Kotlin-side.
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

    // Public API

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

            val callbacks =
                object {
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
                    "Device manager callbacks registered",
                )
            } else {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to register device manager callbacks: $result",
                )
                SDKException.throwIfError(result)
            }
        }
    }

    /**
     * Unregister callbacks and reset state. Called from
     * [com.runanywhere.sdk.foundation.bridge.CppBridge.shutdown].
     */
    fun unregister() {
        synchronized(lock) {
            try {
                RunAnywhereBridge.racDeviceManagerClearCallbacks()
            } catch (t: Throwable) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Device manager callback teardown failed: ${t.message}",
                )
            } finally {
                callbacksRegistered = false
                deviceId = null
                deviceRegistered = false
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Device manager callbacks unregistered",
                )
            }
        }
    }

    /** Are JNI callbacks currently wired? */
    fun isRegistered(): Boolean = callbacksRegistered

    /** Current device id without re-initialising. */
    fun getDeviceId(): String? = deviceId

    // JNI callbacks (invoked by commons through `rac_device_callbacks_t`)

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
     *
     * The canonical schema is the generated [DeviceInfo] proto: we build
     * the proto from the device data (19 core fields + `platform_extras`
     * carrying the Android-only extras), then serialize it to the
     * snake_case JSON the C++ parser expects. Wire's JSON encoder emits
     * camelCase keys, so we serialize by hand: the core proto fields as
     * snake_case keys and each `platform_extras` entry as a top-level
     * snake_case key.
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
        val timezone =
            provider?.getTimezone() ?: java.util.TimeZone
                .getDefault()
                .id
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

        val deviceInfo =
            DeviceInfo(
                device_model = deviceModel,
                device_name = deviceName,
                platform = "android",
                os_version = osVersion,
                form_factor = formFactor,
                architecture = architecture,
                chip_name = chipName,
                total_memory = totalMemory,
                available_memory = availableMemory,
                has_neural_engine = hasNeuralEngine,
                neural_engine_cores = neuralEngineCores,
                gpu_family = gpuFamily,
                battery_level = batteryLevel.toFloat(),
                battery_state = batteryState,
                is_low_power_mode = isLowPowerMode,
                core_count = coreCount,
                performance_cores = performanceCores,
                efficiency_cores = efficiencyCores,
                device_fingerprint = deviceIdValue,
                // Android-only extras consumed by the C++ parser (`manufacturer`)
                // plus historical inert fields kept for payload stability.
                platform_extras =
                    linkedMapOf(
                        "device_id" to deviceIdValue,
                        "device_type" to "mobile",
                        "os_name" to "Android",
                        "processor_count" to coreCount.toString(),
                        "is_simulator" to isEmulator.toString(),
                        "manufacturer" to manufacturer,
                        "os_build_id" to osBuildId,
                        "sdk_version" to sdkVersionString,
                        "android_api_level" to androidApiLevel.toString(),
                        "locale" to locale,
                        "timezone" to timezone,
                    ),
            )

        return serializeDeviceInfoJson(deviceInfo)
    }

    /**
     * Serialize a [DeviceInfo] proto to the snake_case JSON contract the
     * C++ device parser (`jni_device_get_info`) consumes. Core proto fields
     * are emitted under their snake_case names; each `platform_extras` entry
     * is emitted as a top-level key. Extras whose historical wire value was a
     * JSON number or boolean (`processor_count`, `android_api_level`,
     * `is_simulator`) are emitted unquoted; all others are quoted strings.
     */
    private fun serializeDeviceInfoJson(info: DeviceInfo): String {
        val literalExtras = setOf("processor_count", "android_api_level", "is_simulator")
        return buildString {
            append("{")
            append("\"device_id\":\"${escapeJson(info.platform_extras["device_id"] ?: "")}\",")
            append("\"device_model\":\"${escapeJson(info.device_model)}\",")
            append("\"device_name\":\"${escapeJson(info.device_name)}\",")
            append("\"platform\":\"${escapeJson(info.platform)}\",")
            append("\"os_version\":\"${escapeJson(info.os_version)}\",")
            append("\"form_factor\":\"${escapeJson(info.form_factor)}\",")
            append("\"architecture\":\"${escapeJson(info.architecture)}\",")
            append("\"chip_name\":\"${escapeJson(info.chip_name)}\",")
            append("\"total_memory\":${info.total_memory},")
            append("\"available_memory\":${info.available_memory},")
            append("\"has_neural_engine\":${info.has_neural_engine},")
            append("\"neural_engine_cores\":${info.neural_engine_cores},")
            append("\"gpu_family\":\"${escapeJson(info.gpu_family)}\",")
            append("\"battery_level\":${info.battery_level},")
            if (info.battery_state != null) {
                append("\"battery_state\":\"${escapeJson(info.battery_state)}\",")
            } else {
                append("\"battery_state\":null,")
            }
            append("\"is_low_power_mode\":${info.is_low_power_mode},")
            append("\"core_count\":${info.core_count},")
            append("\"performance_cores\":${info.performance_cores},")
            append("\"efficiency_cores\":${info.efficiency_cores},")
            append("\"device_fingerprint\":\"${escapeJson(info.device_fingerprint ?: "")}\"")
            // Top-level snake_case extras (skip device_id; already emitted above).
            for ((key, value) in info.platform_extras) {
                if (key == "device_id") continue
                append(",")
                append("\"${escapeJson(key)}\":")
                if (key in literalExtras) {
                    append(value)
                } else {
                    append("\"${escapeJson(value)}\"")
                }
            }
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
        // Mirrors Swift: development (and pre-init `nil`) always returns false so
        // commons performs the Supabase UPSERT every launch.
        val env = CppBridgeTelemetry.currentEnvironment
        if (env == null || env == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) return false
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
     * Routes through the canonical [HTTPClientAdapter] — same path used
     * by auth and telemetry. The adapter handles base-URL resolution,
     * auth header injection, and Supabase upsert detection from the
     * endpoint path. The JNI caller is synchronous, so we bridge to the
     * adapter's `suspend` API with `runBlocking` (mirrors Swift's
     * `DispatchSemaphore.wait()` in `CppBridge+Device.swift`).
     *
     * @return HTTP status code on response (200/201/409 are success-ish),
     *         or `-1` for transport/configuration failure.
     */
    @JvmStatic
    fun httpPostCallback(endpoint: String, body: String, requiresAuth: Boolean): Int {
        if (!HTTPClientAdapter.isConfigured) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Skipping device registration: HTTPClientAdapter not configured",
            )
            return -1
        }
        return try {
            runBlocking {
                HTTPClientAdapter.postRaw(
                    path = endpoint,
                    payload = body.encodeToByteArray(),
                    requiresAuth = requiresAuth,
                )
            }
            // HTTPClientAdapter throws on non-2xx; reaching here implies success.
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Device registration POST $endpoint → success",
            )
            200
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Device registration POST $endpoint failed: ${e.message}",
            )
            -1
        }
    }

    // Private helpers

    /**
     * Initialise or load the persistent device id.
     *
     * Mirrors Swift's `CppBridge.Device.persistentId` — delegates to
     * commons' `rac_device_get_or_create_persistent_id`, which walks the
     * canonical chain inside C++:
     *   1. secure_get("device_id") via the platform adapter
     *   2. get_vendor_id callback (vendor id on iOS; unset on Android)
     *   3. freshly synthesized RFC-4122 v4 UUID (then persisted)
     *
     * Resolver and durable-write failures abort initialization. A transient
     * replacement would split auth, telemetry, and device-registration state.
     */
    private fun initializeDeviceId() {
        if (deviceId != null) return

        val outRc = intArrayOf(RunAnywhereBridge.RAC_SUCCESS)
        val resolved = RunAnywhereBridge.racDeviceGetOrCreatePersistentId(outRc)
        if (!resolved.isNullOrEmpty()) {
            deviceId = resolved
            return
        }
        SDKException.throwIfError(outRc[0])
        throw SDKException.operation("Persistent device ID resolver returned an empty value")
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
