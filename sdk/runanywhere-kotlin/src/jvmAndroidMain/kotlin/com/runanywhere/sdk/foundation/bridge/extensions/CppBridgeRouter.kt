/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Kotlin facade over the C++ hybrid router (rac_router_*).
 *
 * The router lives in runanywhere-commons. Each registered STT backend is a
 * loaded rac_stt_component; the C layer pulls its underlying service and
 * dispatches transcription through it, applying eligibility, policy, and a
 * confidence cascade.
 *
 * This bridge is thin by design — all routing logic lives in C++ so that
 * every language SDK (Kotlin, Swift, Flutter, RN, Web) sees the same
 * behavior with no policy drift.
 */
package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Router policy values. Must match `rac_routing_policy_t` in
 * `rac_routing_types.h` — do not reorder.
 */
enum class RouterPolicy(val value: Int) {
    AUTO(0),
    LOCAL_ONLY(1),
    CLOUD_ONLY(2),
    PREFER_LOCAL(3),
    PREFER_ACCURACY(4),
    FRAMEWORK_PREFERRED(5),
}

/**
 * Descriptor + identity for a backend registered with the router.
 *
 * The `componentHandle` must come from [CppBridgeSTT]-style component
 * creation and must have a model loaded before calling [CppBridgeRouter.registerStt].
 */
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

/** Result of a routed STT run. Fields mirror the JSON produced by the JNI layer. */
data class RoutedTranscription(
    val text: String,
    val language: String,
    val durationMs: Long,
    /** Primary result confidence, or [Float.NaN] if the backend did not emit a signal. */
    val confidence: Float,
    val chosenModuleId: String,
    val wasFallback: Boolean,
    /** Confidence from the first attempted backend. May equal [confidence] when no cascade occurred. */
    val primaryConfidence: Float,
    val attemptCount: Int,
)

object CppBridgeRouter {

    private val logger = SDKLogger("CppBridgeRouter")

    /**
     * Register an STT backend with the global router. The caller owns the
     * component lifecycle and must call [unregisterStt] before unloading or
     * destroying the component.
     *
     * @return true on success; false if registration failed (model not
     *   loaded, duplicate module id, invalid args).
     */
    fun registerStt(backend: RouterBackend): Boolean {
        val rc = RunAnywhereBridge.racRouterRegisterStt(
            componentHandle = backend.componentHandle,
            moduleId = backend.moduleId,
            moduleName = backend.moduleName,
            priority = backend.priority,
            isLocalOnly = backend.isLocalOnly,
            needsNetwork = backend.needsNetwork,
            costCentsPerMinute = backend.costCentsPerMinute,
            inferenceFramework = backend.inferenceFramework,
        )
        if (rc != 0) {
            logger.warn("registerStt('${backend.moduleId}') failed with rc=$rc")
            return false
        }
        logger.info("registerStt('${backend.moduleId}') OK (priority=${backend.priority})")
        return true
    }

    fun unregisterStt(moduleId: String): Boolean {
        val rc = RunAnywhereBridge.racRouterUnregisterStt(moduleId)
        if (rc != 0) {
            logger.warn("unregisterStt('$moduleId') failed with rc=$rc")
            return false
        }
        return true
    }

    /** @return number of STT backends currently registered with the router. */
    fun sttCount(): Int = RunAnywhereBridge.racRouterSttCount()

    /**
     * Run a transcription through the router.
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
        val json = RunAnywhereBridge.racRouterRunStt(
            isOnline = isOnline,
            policy = policy.value,
            preferredFramework = preferredFramework,
            audioData = audioData,
            optionsJson = optionsJson,
        ) ?: throw IllegalStateException("Router returned no result (no eligible backend, or all failed)")
        return parseJson(json)
    }

    // --- JSON parsing ----------------------------------------------------------
    //
    // We keep the parser ad-hoc (regex) to match the rest of the bridge layer —
    // every CppBridge* file uses the same pattern. This avoids pulling in a
    // JSON dependency for a stable, small payload.

    private fun parseJson(json: String): RoutedTranscription {
        fun str(key: String, default: String = ""): String {
            val m = Regex("\"$key\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(json) ?: return default
            return m.groupValues[1]
        }

        fun long(key: String): Long {
            val m = Regex("\"$key\"\\s*:\\s*(-?\\d+)").find(json) ?: return 0L
            return m.groupValues[1].toLongOrNull() ?: 0L
        }

        fun int(key: String): Int {
            val m = Regex("\"$key\"\\s*:\\s*(-?\\d+)").find(json) ?: return 0
            return m.groupValues[1].toIntOrNull() ?: 0
        }

        fun bool(key: String): Boolean {
            val m = Regex("\"$key\"\\s*:\\s*(true|false)").find(json) ?: return false
            return m.groupValues[1] == "true"
        }

        // Float that handles JSON null → Float.NaN, distinguishing "no signal"
        // from a real 0.0 score.
        fun float(key: String): Float {
            val m = Regex("\"$key\"\\s*:\\s*(null|-?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)").find(json)
                ?: return Float.NaN
            val raw = m.groupValues[1]
            if (raw == "null") return Float.NaN
            return raw.toFloatOrNull() ?: Float.NaN
        }

        return RoutedTranscription(
            text = str("text"),
            language = str("language", "en"),
            durationMs = long("duration_ms"),
            confidence = float("confidence"),
            chosenModuleId = str("chosen_module_id"),
            wasFallback = bool("was_fallback"),
            primaryConfidence = float("primary_confidence"),
            attemptCount = int("attempt_count"),
        )
    }
}
