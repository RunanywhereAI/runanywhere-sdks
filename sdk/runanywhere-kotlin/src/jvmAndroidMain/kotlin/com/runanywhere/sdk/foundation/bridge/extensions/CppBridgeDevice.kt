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

            // Register the device callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetDeviceCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Device callbacks registered. Device ID: ${deviceId ?: "unknown"}"
            )
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
     * Returns device info including: platform, model, manufacturer, OS version,
     * SDK version, locale, timezone, and whether it's an emulator.
     *
     * @return JSON-encoded device information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDeviceInfoCallback(): String {
        val provider = deviceInfoProvider

        val platform = detectPlatform()
        val model = provider?.getDeviceModel() ?: getDefaultDeviceModel()
        val manufacturer = provider?.getDeviceManufacturer() ?: getDefaultManufacturer()
        val osVersion = provider?.getOSVersion() ?: System.getProperty("os.version") ?: "unknown"
        val osBuildId = provider?.getOSBuildId() ?: ""
        val sdkVersion = provider?.getSDKVersion() ?: 0
        val locale = provider?.getLocale() ?: Locale.getDefault().toLanguageTag()
        val timezone = provider?.getTimezone() ?: java.util.TimeZone.getDefault().id
        val isEmulator = provider?.isEmulator() ?: false

        // Build JSON manually to avoid external dependencies
        return buildString {
            append("{")
            append("\"platform\":$platform,")
            append("\"model\":\"${escapeJson(model)}\",")
            append("\"manufacturer\":\"${escapeJson(manufacturer)}\",")
            append("\"os_version\":\"${escapeJson(osVersion)}\",")
            append("\"os_build_id\":\"${escapeJson(osBuildId)}\",")
            append("\"sdk_version\":$sdkVersion,")
            append("\"locale\":\"${escapeJson(locale)}\",")
            append("\"timezone\":\"${escapeJson(timezone)}\",")
            append("\"is_emulator\":$isEmulator,")
            append("\"device_id\":\"${escapeJson(deviceId ?: "")}\"")
            append("}")
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
     * @return true if registered, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isDeviceRegisteredCallback(): Boolean {
        return registrationStatus == RegistrationStatus.REGISTERED
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
            "Registration status changed: $previousStatus -> $status"
        )

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
                        errorMessage ?: "Unknown error"
                    )
                }
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in device listener: ${e.message}"
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
        completionCallbackId: Long
    ) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Device registration POST to: $url"
        )

        // Delegate to telemetry HTTP callback if available
        CppBridgeTelemetry.httpCallback(
            requestId = "device-registration-${System.currentTimeMillis()}",
            url = url,
            method = CppBridgeTelemetry.HttpMethod.POST,
            headers = headers,
            body = body,
            completionCallbackId = completionCallbackId
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
     *
     * C API: rac_device_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetDeviceCallbacks()

    /**
     * Native method to unset the device callbacks.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_device_set_callbacks(nullptr)
     */
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

            // TODO: Call native unregistration
            // nativeUnsetDeviceCallbacks()

            deviceListener = null
            registrationStatus = RegistrationStatus.NOT_REGISTERED
            isRegistered = false
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
            newId.toByteArray(Charsets.UTF_8)
        )

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Generated new device ID: $newId"
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
                id.toByteArray(Charsets.UTF_8)
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
     * @return true if registration was triggered, false if already registered or failed
     */
    fun triggerRegistration(): Boolean {
        if (!isRegistered) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Cannot trigger registration: device callbacks not registered"
            )
            return false
        }

        if (registrationStatus == RegistrationStatus.REGISTERED) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Device already registered"
            )
            return true
        }

        if (registrationStatus == RegistrationStatus.REGISTERING) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Device registration already in progress"
            )
            return true
        }

        // TODO: Call native registration
        // val result = nativeRegisterDevice()
        // return result == 0

        return true
    }

    /**
     * Detect the current platform type.
     */
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
        return System.getProperty("os.arch") ?: "unknown"
    }

    /**
     * Get default manufacturer for JVM environment.
     */
    private fun getDefaultManufacturer(): String {
        return System.getProperty("java.vendor") ?: "unknown"
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
