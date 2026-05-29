/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Two-phase SDK init bridge — wraps the canonical C ABI surface in
 * rac_sdk_init.h (P2-T9). Mirrors Swift's
 * Foundation/Bridge/Extensions/CppBridge+SdkInit.swift exactly (adapting only
 * syntax): maps Kotlin parameters into SdkInitPhase{1,2}Request, invokes
 * rac_sdk_init_phase{1,2}_proto / rac_sdk_retry_http_proto via the JNI bridge,
 * and returns the decoded SdkInitResult so the public façade can react to the
 * outcome flags (http_configured / device_registered / linked_models_count /
 * warning).
 *
 * Phase 1 additionally runs the validation contract
 * (rac_validate_api_key / rac_validate_base_url) and rac_state_initialize
 * inside commons — so a malformed apiKey/baseURL is rejected on Android
 * exactly as it is on iOS, instead of silently booting.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SdkInitEnvironment
import ai.runanywhere.proto.v1.SdkInitPhase1Request
import ai.runanywhere.proto.v1.SdkInitPhase2Request
import ai.runanywhere.proto.v1.SdkInitResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment

/**
 * Two-phase SDK init bridge. Mirrors Swift's `CppBridge.SdkInit`.
 */
object CppBridgeSdkInit {
    /**
     * Drive Phase 1 (synchronous core init) through the canonical C ABI.
     * Validates inputs and runs `rac_state_initialize` inside commons.
     */
    fun phase1(
        environment: SDKEnvironment,
        apiKey: String,
        baseURL: String,
        deviceId: String,
    ): SdkInitResult {
        val request =
            SdkInitPhase1Request(
                environment = environment.toSdkInitEnvironment(),
                api_key = apiKey,
                base_url = baseURL,
                device_id = deviceId,
            )
        val result =
            decode(
                RunAnywhereBridge.racSdkInitPhase1Proto(SdkInitPhase1Request.ADAPTER.encode(request)),
                phase = "1",
            )
        assertSuccess(result)
        return result
    }

    /**
     * Drive Phase 2 (services init step list) through the canonical C ABI.
     * Surfaces `http_configured`, `device_registered`, `linked_models_count`
     * and warning flags. Failures in individual sub-steps are non-fatal — the
     * C ABI reports `success=true` with flags off.
     */
    fun phase2(): SdkInitResult {
        val result =
            decode(
                RunAnywhereBridge.racSdkInitPhase2Proto(
                    SdkInitPhase2Request.ADAPTER.encode(SdkInitPhase2Request()),
                ),
                phase = "2",
            )
        assertSuccess(result)
        return result
    }

    /**
     * Re-attempt HTTP/auth setup after an offline initialization. Idempotent
     * fast path when already authenticated; surfaces a warning when no usable
     * external config is available. Mirrors `rac_sdk_retry_http_proto`.
     */
    fun retryHTTP(): SdkInitResult {
        val result = decode(RunAnywhereBridge.racSdkRetryHttpProto(), phase = "RETRY_HTTP")
        assertSuccess(result)
        return result
    }

    private fun decode(bytes: ByteArray?, phase: String): SdkInitResult {
        val payload =
            bytes ?: throw SDKException.operation("SDK init phase $phase returned null result")
        return try {
            SdkInitResult.ADAPTER.decode(payload)
        } catch (e: Exception) {
            throw SDKException.operation("Failed to decode SDK init phase $phase result: ${e.message}", e)
        }
    }

    /**
     * Throw the embedded SDKError when the C ABI signals a hard failure
     * (validation/parse/state init). Soft failures (offline mode) come back
     * with `success=true` plus warnings — the caller decides how to react.
     * Mirrors Swift's `assertSuccess`.
     */
    private fun assertSuccess(result: SdkInitResult) {
        if (result.success) return
        result.error?.let { throw SDKException(it) }
        throw SDKException.operation(
            "SDK init phase ${result.phase} failed without error detail",
        )
    }

    private fun SDKEnvironment.toSdkInitEnvironment(): SdkInitEnvironment =
        when (this) {
            SDKEnvironment.SDK_ENVIRONMENT_STAGING -> SdkInitEnvironment.SDK_INIT_ENVIRONMENT_STAGING
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> SdkInitEnvironment.SDK_INIT_ENVIRONMENT_PRODUCTION
            else -> SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT
        }
}
