/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * SDK-internal facade. Existing callers (RunAnywhere+STT.transcribe) stay on
 * this surface; under the hood it now delegates to the public [HybridRouter]
 * instance owned by [RouterRegistration]. The legacy types ([RouterPolicy],
 * [RouterBackend], [RoutedTranscription]) remain for backwards compat — new
 * code should use the types in `com.runanywhere.sdk.public.routing`.
 */
package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.routing.Policy
import com.runanywhere.sdk.public.routing.RoutingContext

/**
 * Legacy enum mirroring the public [Policy] sealed type. Values match
 * `rac_routing_policy_t`. Prefer [Policy] in new code.
 */
enum class RouterPolicy(val value: Int) {
    AUTO(0),
    LOCAL_ONLY(1),
    CLOUD_ONLY(2),
    PREFER_LOCAL(3),
    PREFER_ACCURACY(4),
    FRAMEWORK_PREFERRED(5),
    ;

    fun toPolicy(): Policy = when (this) {
        AUTO -> Policy.Auto
        LOCAL_ONLY -> Policy.LocalOnly
        CLOUD_ONLY -> Policy.CloudOnly
        PREFER_LOCAL -> Policy.PreferLocal
        PREFER_ACCURACY -> Policy.PreferAccuracy
        FRAMEWORK_PREFERRED -> Policy.FrameworkPreferred
    }
}

/** Legacy descriptor — kept for source compatibility. */
data class RouterBackend(
    val moduleId: String,
    val moduleName: String,
    val componentHandle: Long,
    val priority: Int,
    val isLocalOnly: Boolean,
    val needsNetwork: Boolean,
    val costCentsPerMinute: Float = 0.0f,
    val inferenceFramework: String? = null,
)

/** Legacy result — kept for source compatibility. */
data class RoutedTranscription(
    val text: String,
    val language: String,
    val durationMs: Long,
    val confidence: Float,
    val chosenModuleId: String,
    val wasFallback: Boolean,
    val primaryConfidence: Float,
    val attemptCount: Int,
)

object CppBridgeRouter {

    private val logger = SDKLogger("CppBridgeRouter")

    fun sttCount(): Int = RouterRegistration.sttRouter().count()

    /**
     * Run a transcription through the SDK-wide STT router.
     *
     * @throws IllegalStateException when no backend is eligible or all fail.
     */
    fun runStt(
        isOnline: Boolean,
        policy: RouterPolicy,
        preferredFramework: String?,
        audioData: ByteArray,
        optionsJson: String?,
    ): RoutedTranscription {
        val routed = RouterRegistration.sttRouter().transcribe(
            audioData = audioData,
            context = RoutingContext(
                isOnline = isOnline,
                policy = policy.toPolicy(),
                preferredFramework = preferredFramework,
            ),
            optionsJson = optionsJson,
        )
        return RoutedTranscription(
            text = routed.text,
            language = routed.language,
            durationMs = routed.durationMs,
            confidence = routed.confidence,
            chosenModuleId = routed.chosenModuleId,
            wasFallback = routed.wasFallback,
            primaryConfidence = routed.primaryConfidence,
            attemptCount = routed.attemptCount,
        )
    }
}
