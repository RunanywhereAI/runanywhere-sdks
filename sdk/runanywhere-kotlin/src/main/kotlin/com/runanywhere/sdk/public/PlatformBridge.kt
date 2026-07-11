/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android bridge that connects the public RunAnywhere facade to CppBridge.
 */

package com.runanywhere.sdk.public

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTelemetry
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.events.EventBus
import java.util.Locale
import java.util.TimeZone

private const val TAG = "PlatformBridge"
private val logger = SDKLogger(TAG)

/**
 * Initialize the CppBridge with the given environment.
 * This loads the native libraries and registers platform adapters.
 *
 * @param environment SDK environment
 * @param apiKey API key for authentication (required for production/staging)
 * @param baseURL Backend API base URL (required for production/staging)
 */
internal fun initializePlatformBridge(environment: SDKEnvironment, apiKey: String?, baseURL: String?) {
    logger.debug("Initializing CppBridge for environment: $environment")

    // Normalize UNSPECIFIED -> DEVELOPMENT so the downstream C-ABI call gets a valid value.
    val resolvedEnvironment =
        if (environment == SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
        } else {
            environment
        }

    // Configure telemetry base URL if provided
    if (!baseURL.isNullOrEmpty()) {
        CppBridgeTelemetry.setBaseUrl(baseURL)
        logger.debug("Telemetry base URL configured: $baseURL")
    }
    if (!apiKey.isNullOrEmpty()) {
        CppBridgeTelemetry.setApiKey(apiKey)
        logger.debug("Telemetry API key configured")
    }

    CppBridge.initialize(resolvedEnvironment)
    configureClientInfo()

    // Wire the public EventBus to the canonical native SDKEvent stream
    // so consumers see lifecycle/error/model events emitted by C++.
    // Mirrors Swift EventBus's lazy CppBridge.Events.subscribeSDKEvents
    // call. Safe to invoke even when the native lib failed to load
    // (the actual no-ops on UnsatisfiedLinkError).
    EventBus.start()

    logger.debug("CppBridge initialization complete. Native library loaded: ${CppBridge.isNativeLibraryLoaded}")
}

private fun configureClientInfo() {
    val locale = Locale.getDefault().toLanguageTag()
    val timezone = TimeZone.getDefault().id

    val appInfo = readAndroidAppInfo()
    RunAnywhereBridge.racSdkSetClientInfo(
        sdkBinding = "kotlin",
        appIdentifier = appInfo?.identifier,
        appName = appInfo?.name,
        appVersion = appInfo?.version,
        appBuild = appInfo?.build,
        locale = locale,
        timezone = timezone,
    )
}

private data class AndroidAppInfo(
    val identifier: String,
    val name: String?,
    val version: String?,
    val build: String?,
)

private fun readAndroidAppInfo(): AndroidAppInfo? {
    if (!AndroidPlatformContext.isInitialized()) {
        return null
    }

    return try {
        val context = AndroidPlatformContext.applicationContext
        val packageName = context.packageName
        val packageManager = context.packageManager
        val packageInfo = readPackageInfo(context) ?: return null
        val appName =
            runCatching { context.applicationInfo.loadLabel(packageManager).toString() }.getOrNull()
        val versionName = packageInfo.versionName
        AndroidAppInfo(
            identifier = packageName,
            name = appName,
            version = versionName,
            build = readVersionCode(packageInfo).toString(),
        )
    } catch (e: Exception) {
        logger.debug("Unable to read Android app metadata: ${e.message}")
        null
    }
}

private fun readPackageInfo(context: Context): PackageInfo? {
    val packageManager = context.packageManager
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        packageManager.getPackageInfo(
            context.packageName,
            PackageManager.PackageInfoFlags.of(0),
        )
    } else {
        val method =
            PackageManager::class.java.getMethod(
                "getPackageInfo",
                String::class.java,
                Int::class.javaPrimitiveType,
            )
        method.invoke(packageManager, context.packageName, 0) as? PackageInfo
    }
}

private fun readVersionCode(packageInfo: PackageInfo): Long {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        packageInfo.longVersionCode
    } else {
        val field = PackageInfo::class.java.getField("versionCode")
        field.getInt(packageInfo).toLong()
    }
}

/**
 * Initialize CppBridge services (Phase 2).
 * This wires platform services/HTTP callbacks before the public facade calls
 * `CppBridgeSdkInit.phase2`, where commons owns auth/refresh, device
 * registration, assignment fetch, telemetry flush, and model discovery.
 */
internal suspend fun initializePlatformBridgeServices() {
    logger.debug("Initializing CppBridge services...")
    CppBridge.initializeServices()
    logger.debug("CppBridge services initialization complete")
}

/**
 * Shutdown CppBridge and release resources.
 */
internal fun shutdownPlatformBridge() {
    logger.debug("Shutting down CppBridge...")
    // Tear down the native SDKEvent subscription before C++ commons is
    // shutdown so the unsubscribe call still has a working ABI surface.
    EventBus.stop()
    CppBridge.shutdown()
    logger.debug("CppBridge shutdown complete")
}

// Auth + device-state actuals — route directly through `rac_auth_*` and
// CppBridgeDevice thunks. No Kotlin-side cache.

internal fun platformGetUserId(): String? = RunAnywhereBridge.racAuthGetUserId()

internal fun platformGetOrganizationId(): String? = RunAnywhereBridge.racAuthGetOrganizationId()

internal fun platformIsAuthenticated(): Boolean = RunAnywhereBridge.racAuthIsAuthenticated()

internal fun platformIsDeviceRegistered(): Boolean = CppBridgeDevice.isRegistered()

internal fun platformDeviceId(): String =
    CppBridgeDevice.getDeviceId() ?: RunAnywhereBridge.racAuthGetDeviceId() ?: ""
