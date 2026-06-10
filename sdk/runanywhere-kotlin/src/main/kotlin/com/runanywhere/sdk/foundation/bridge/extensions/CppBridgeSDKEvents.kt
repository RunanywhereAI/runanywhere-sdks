/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Generated-proto SDK event bridge helpers.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.DeviceEvent
import ai.runanywhere.proto.v1.DeviceEventKind
import ai.runanywhere.proto.v1.ErrorSeverity
import ai.runanywhere.proto.v1.EventCategory
import ai.runanywhere.proto.v1.EventDestination
import ai.runanywhere.proto.v1.InitializationEvent
import ai.runanywhere.proto.v1.InitializationStage
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.events.SDKEvent
import java.util.UUID

/**
 * Event bridge surface backed by the canonical SDKEvent proto stream.
 */
object CppBridgeSDKEvents {
    @Volatile
    private var isRegistered: Boolean = false

    fun register(telemetryHandle: Long): Boolean {
        isRegistered = telemetryHandle != 0L
        return isRegistered
    }

    fun unregister() {
        isRegistered = false
    }

    fun isRegistered(): Boolean = isRegistered

    fun emitSDKInitStarted() {
        publishInitialization(
            stage = InitializationStage.INITIALIZATION_STAGE_STARTED,
            severity = ErrorSeverity.ERROR_SEVERITY_INFO,
            operationId = "sdk.init",
        )
    }

    fun emitSDKInitCompleted(durationMs: Double) {
        publishInitialization(
            stage = InitializationStage.INITIALIZATION_STAGE_COMPLETED,
            severity = ErrorSeverity.ERROR_SEVERITY_INFO,
            operationId = "sdk.init",
            properties = mapOf("duration_ms" to durationMs.toString()),
        )
    }

    fun emitSDKInitFailed(error: SDKException?) {
        publishInitialization(
            stage = InitializationStage.INITIALIZATION_STAGE_FAILED,
            severity = ErrorSeverity.ERROR_SEVERITY_ERROR,
            operationId = "sdk.init",
            error = error?.message ?: "",
        )
    }

    fun emitSDKModelsLoaded(modelIds: List<String>) {
        publishInitialization(
            stage = InitializationStage.INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED,
            severity = ErrorSeverity.ERROR_SEVERITY_INFO,
            operationId = "sdk.models_loaded",
            properties =
                mapOf(
                    "model_count" to modelIds.size.toString(),
                    "model_ids" to modelIds.joinToString(","),
                ),
        )
    }

    fun emitDeviceRegistered(deviceId: String) {
        publishDevice(
            kind = DeviceEventKind.DEVICE_EVENT_KIND_DEVICE_REGISTERED,
            severity = ErrorSeverity.ERROR_SEVERITY_INFO,
            deviceId = deviceId,
            operationId = "device.register",
        )
    }

    fun emitDeviceRegistrationFailed(errorMessage: String) {
        publishDevice(
            kind = DeviceEventKind.DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED,
            severity = ErrorSeverity.ERROR_SEVERITY_ERROR,
            error = errorMessage,
            operationId = "device.register",
        )
    }

    private fun publishInitialization(
        stage: InitializationStage,
        severity: ErrorSeverity,
        operationId: String,
        properties: Map<String, String> = emptyMap(),
        error: String = "",
    ) {
        publish(
            SDKEvent(
                timestamp_ms = System.currentTimeMillis(),
                severity = severity,
                category = EventCategory.EVENT_CATEGORY_INITIALIZATION,
                component = SDKComponent.SDK_COMPONENT_UNSPECIFIED,
                id = UUID.randomUUID().toString(),
                destination = EventDestination.EVENT_DESTINATION_ALL,
                properties = properties,
                operation_id = operationId,
                source = "kotlin",
                initialization =
                    InitializationEvent(
                        stage = stage,
                        error = error,
                        version = SDKConstants.VERSION,
                    ),
            ),
        )
    }

    private fun publishDevice(
        kind: DeviceEventKind,
        severity: ErrorSeverity,
        operationId: String,
        deviceId: String = "",
        error: String = "",
    ) {
        publish(
            SDKEvent(
                timestamp_ms = System.currentTimeMillis(),
                severity = severity,
                category = EventCategory.EVENT_CATEGORY_DEVICE,
                component = SDKComponent.SDK_COMPONENT_UNSPECIFIED,
                id = UUID.randomUUID().toString(),
                destination = EventDestination.EVENT_DESTINATION_ALL,
                operation_id = operationId,
                source = "kotlin",
                device =
                    DeviceEvent(
                        kind = kind,
                        device_id = deviceId,
                        error = error,
                    ),
            ),
        )
    }

    private fun publish(event: SDKEvent) {
        CppBridgeSDKEventStream.publish(event)
    }
}
