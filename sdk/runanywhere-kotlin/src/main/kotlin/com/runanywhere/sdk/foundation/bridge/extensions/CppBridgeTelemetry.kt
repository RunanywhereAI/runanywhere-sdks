/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Telemetry bridge extension for CppBridge.
 *
 * Mirrors Swift's `CppBridge+Telemetry.swift`. C++ owns event logic,
 * JSON serialization, and batching; Kotlin only provides:
 *   - the native telemetry-manager lifecycle (create/destroy/flush),
 *   - the HTTP callback that C++ uses to drain queued events to the
 *     backend — routed through [HTTPClientAdapter] (W2-6).
 *
 * The previous ~600 LOC of bespoke HTTP transport, header parsing, dev-
 * config-aware URL resolution, and listener / interceptor surface has
 * been deleted. All dev-config queries now live in [CppBridgeDevConfig];
 * all HTTP transport routes through [HTTPClientAdapter].
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ErrorSeverity
import ai.runanywhere.proto.v1.EventCategory
import ai.runanywhere.proto.v1.EventDestination
import ai.runanywhere.proto.v1.InitializationEvent
import ai.runanywhere.proto.v1.InitializationStage
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.HTTPClientAdapter
import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.cEnvironment
import com.runanywhere.sdk.public.configuration.description
import com.runanywhere.sdk.public.events.SDKEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Telemetry bridge — owns the native `rac_telemetry_manager_*` handle
 * and forwards the HTTP callback from C++ through [HTTPClientAdapter].
 *
 * Thread safety: handle/state mutations are guarded by a [lock] sync
 * block; the HTTP callback dispatches to the shared [scope] running on
 * `Dispatchers.IO`.
 */
object CppBridgeTelemetry {
    private const val TAG = "CppBridgeTelemetry"

    @Volatile private var isRegistered: Boolean = false

    @Volatile private var telemetryManagerHandle: Long = 0

    @Volatile private var _baseUrl: String? = null

    @Volatile private var _apiKey: String? = null

    /**
     * Current SDK environment. Mirrors Swift's
     * `Telemetry.activeEnvironment: OSAllocatedUnfairLock<SDKEnvironment?>`.
     * Set by [setEnvironment] from `CppBridge.initialize` so
     * `CppBridgeDevice.isDeviceRegisteredCallback` can branch on it. `null`
     * before initialization and after [unregister] / shutdown.
     */
    @Volatile
    var currentEnvironment: SDKEnvironment? = null
        private set

    private val lock = Any()

    /** Background scope for the C++→Kotlin HTTP callback. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Lifecycle (parity with Swift `CppBridge.Events.register/unregister`
    // and `CppBridge.Telemetry.initialize/shutdown`)

    /** Register the telemetry bridge. Idempotent. */
    fun register() {
        synchronized(lock) {
            if (isRegistered) return
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Registering telemetry…")
            isRegistered = true
        }
    }

    /**
     * Create the native telemetry manager and wire the HTTP callback.
     * Mirrors Swift's `Telemetry.initialize(environment:)`.
     */
    fun initialize(
        environment: SDKEnvironment,
        deviceId: String,
        deviceModel: String,
        osVersion: String,
        sdkVersion: String,
    ) {
        synchronized(lock) {
            currentEnvironment = environment

            telemetryManagerHandle =
                RunAnywhereBridge.racTelemetryManagerCreate(
                    environment.cEnvironment,
                    deviceId,
                    SDKConstants.SDK_PLATFORM,
                    sdkVersion,
                )

            if (telemetryManagerHandle == 0L) {
                log(CppBridgePlatformAdapter.LogLevel.WARN, "Failed to create telemetry manager")
                return
            }

            RunAnywhereBridge.racTelemetryManagerSetDeviceInfo(
                telemetryManagerHandle,
                deviceModel,
                osVersion,
            )

            // HTTP callback shape (matched by JNI lookup):
            //   onHttpRequest(endpoint: String, body: String, bodyLength: Int, requiresAuth: Boolean)
            val httpCallback =
                object {
                    @Suppress("unused")
                    fun onHttpRequest(
                        endpoint: String,
                        body: String,
                        bodyLength: Int,
                        requiresAuth: Boolean,
                    ) {
                        scope.launch { performTelemetryHttp(endpoint, body, requiresAuth) }
                    }
                }
            RunAnywhereBridge.racTelemetryManagerSetHttpCallback(telemetryManagerHandle, httpCallback)

            // Attach this manager as the C++ event router's telemetry sink so
            // the router (`rac::events::route`) feeds every TELEMETRY-bit event
            // into it for batching + HTTP transport. The router does the
            // per-event translation internally — no analytics callback needed.
            // Mirrors Swift's `rac_events_set_telemetry_sink(...)` wired in
            // `CppBridge.Events.register()`. Pass `0` to detach.
            val sinkRc = RunAnywhereBridge.racEventsSetTelemetrySink(telemetryManagerHandle)
            if (sinkRc != 0) {
                log(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    "Failed to register telemetry sink (rc=$sinkRc)",
                )
            }

            log(
                CppBridgePlatformAdapter.LogLevel.INFO,
                "Telemetry manager initialized (handle=$telemetryManagerHandle, env=${environment.description})",
            )
        }
    }

    /** Flush pending telemetry events through the native manager. */
    fun flush() {
        synchronized(lock) {
            if (telemetryManagerHandle != 0L) {
                RunAnywhereBridge.racTelemetryManagerFlush(telemetryManagerHandle)
            }
        }
    }

    /**
     * Tear down the telemetry bridge.
     *
     * Mirrors Swift's `CppBridge.Telemetry.shutdown()`, which flushes pending
     * events BEFORE destroying the manager so in-flight analytics are not
     * silently dropped at SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) return
            if (telemetryManagerHandle != 0L) {
                // Detach the telemetry sink first so the C++ router stops
                // feeding events into a manager we are about to destroy.
                try {
                    RunAnywhereBridge.racEventsSetTelemetrySink(0L)
                } catch (_: Throwable) {
                    // Best-effort; native lib may already be unloaded.
                }
                // Flush BEFORE destroy — parity with Swift Telemetry.shutdown().
                RunAnywhereBridge.racTelemetryManagerFlush(telemetryManagerHandle)
                RunAnywhereBridge.racTelemetryManagerDestroy(telemetryManagerHandle)
                telemetryManagerHandle = 0
            }
            // Mirrors Swift's `activeEnvironment.withLock { $0 = nil }` in
            // `CppBridge.Telemetry.shutdown()`.
            currentEnvironment = null
            isRegistered = false
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Telemetry unregistered")
        }
    }

    /** Native telemetry manager handle (0 if not initialized). */
    fun getTelemetryHandle(): Long = telemetryManagerHandle

    // Configuration (called by CppBridge.kt + PlatformBridge.kt during
    // Phase 1 init). Mirrors Swift, where the same values feed
    // `CppBridge.HTTP.configure(baseURL:apiKey:)`.

    fun setBaseUrl(url: String) {
        _baseUrl = url
    }

    fun setApiKey(key: String) {
        _apiKey = key
    }

    fun getBaseUrl(): String? = _baseUrl

    fun getApiKey(): String? = _apiKey

    /** Set the active environment so callbacks can branch on prod vs dev. */
    fun setEnvironment(environment: SDKEnvironment) {
        currentEnvironment = environment
        log(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            "Environment set to: ${environment.cEnvironment} (${environment.description})",
        )
    }

    // HTTP callback path

    /**
     * Forward a telemetry HTTP request from C++ through the canonical
     * [HTTPClientAdapter]. Mirrors Swift's `performTelemetryHTTP(...)`.
     *
     * Skipped silently when the adapter has no usable configuration —
     * matches Swift's `CppBridge.HTTP.hasUsableConfiguration` + `isConfigured`
     * preflight.
     */
    private suspend fun performTelemetryHttp(path: String, json: String, requiresAuth: Boolean) {
        val env = currentEnvironment
        if ((env == null || env == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) &&
            !CppBridgeDevConfig.hasUsableSupabaseConfig
        ) {
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Skipping telemetry: no usable dev config")
            return
        }
        if (!HTTPClientAdapter.hasUsableConfiguration || !HTTPClientAdapter.isConfigured) {
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Skipping telemetry: HTTPClientAdapter not configured")
            return
        }
        try {
            HTTPClientAdapter.post(path, json, requiresAuth = requiresAuth)
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Telemetry sent to $path")
        } catch (e: Exception) {
            log(CppBridgePlatformAdapter.LogLevel.ERROR, "Telemetry HTTP failed for $path: ${e.message}")
        }
    }

    // SDK lifecycle event emission helpers (parity with Swift's
    // `CppBridge.Events.emitSDKInit*` / `emitSDKModelsLoaded`).
    //
    // Each builds an [InitializationEvent] + wraps it in an [SDKEvent]
    // and publishes it through the canonical SDKEvent proto stream via
    // [CppBridgeSDKEventStream.publish] — C++ owns fan-out + routing.

    /** Emit "SDK init started" through the canonical SDKEvent proto stream. */
    fun emitSDKInitStarted() {
        publishInitialization(stage = InitializationStage.INITIALIZATION_STAGE_STARTED)
    }

    /** Emit "SDK init completed" carrying init duration in milliseconds. */
    fun emitSDKInitCompleted(durationMs: Double) {
        publishInitialization(
            stage = InitializationStage.INITIALIZATION_STAGE_COMPLETED,
            properties = mapOf("duration_ms" to durationMs.toString()),
        )
    }

    /**
     * Emit "SDK init failed". Mirrors Swift's `emitSDKInitFailed(error:)`.
     * A `null` [error] still produces a FAILED event with an empty message so
     * downstream consumers see the failure stage.
     */
    fun emitSDKInitFailed(error: SDKException?) {
        publishInitialization(
            stage = InitializationStage.INITIALIZATION_STAGE_FAILED,
            errorMessage = error?.message ?: "",
        )
    }

    /**
     * Emit "SDK models loaded". Swift sends a `model_count`; Kotlin SDK callers
     * already have the full id list at the call site, so we send both the
     * count and a comma-joined id list for richer downstream attribution.
     */
    fun emitSDKModelsLoaded(modelIds: List<String>) {
        publishInitialization(
            stage = InitializationStage.INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED,
            properties =
                mapOf(
                    "model_count" to modelIds.size.toString(),
                    "model_ids" to modelIds.joinToString(","),
                ),
        )
    }

    private fun publishInitialization(
        stage: InitializationStage,
        errorMessage: String = "",
        properties: Map<String, String> = emptyMap(),
    ) {
        val severity =
            if (stage == InitializationStage.INITIALIZATION_STAGE_FAILED) {
                ErrorSeverity.ERROR_SEVERITY_ERROR
            } else {
                ErrorSeverity.ERROR_SEVERITY_INFO
            }

        val event =
            SDKEvent(
                id = UUID.randomUUID().toString(),
                timestamp_ms = System.currentTimeMillis(),
                severity = severity,
                category = EventCategory.EVENT_CATEGORY_INITIALIZATION,
                component = SDKComponent.SDK_COMPONENT_UNSPECIFIED,
                destination = EventDestination.EVENT_DESTINATION_ALL,
                source = "kotlin",
                properties = properties,
                initialization =
                    InitializationEvent(
                        stage = stage,
                        error = errorMessage,
                        version = SDKConstants.VERSION,
                    ),
            )

        CppBridgeSDKEventStream.publish(event)
    }

    private fun log(level: Int, message: String) {
        CppBridgePlatformAdapter.logCallback(level, TAG, message)
    }
}
