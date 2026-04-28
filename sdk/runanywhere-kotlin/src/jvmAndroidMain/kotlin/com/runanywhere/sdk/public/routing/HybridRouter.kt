/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public dev-facing hybrid router. Thin shell — the C++ side does all the
 * work. One [HybridRouter] instance == one rac_hybrid_router_t handle bound
 * to a single capability. Devs can hold multiple instances side-by-side
 * (e.g. fast-LLM router + accurate-LLM router with different backends).
 *
 * Usage shape (mirrors docs/impl/HYB.txt):
 *
 *   val router = HybridRouter(Capability.STT)
 *   router.registerStt(localComponentHandle, BackendDescriptor(
 *       moduleId = "whisper-local", moduleName = "Whisper",
 *       capability = Capability.STT, basePriority = 100,
 *       isLocalOnly = true, inferenceFramework = "onnx",
 *   ))
 *   val out = router.transcribe(audioBytes, RoutingContext(isOnline = true))
 *   // out.text, out.confidence, out.chosenModuleId, out.wasFallback
 *
 * Lifetime:
 *   - The router holds a non-owning ref to each registered component. The
 *     caller must [unregister] before unloading or destroying a component.
 *   - Call [close] to release the C handle. Multiple routers can coexist.
 */
package com.runanywhere.sdk.public.routing

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

class HybridRouter(val capability: Capability) : AutoCloseable {

    private val logger = SDKLogger("HybridRouter")
    private val handle: Long = RunAnywhereBridge.racHybridRouterCreate(capability.value)

    init {
        check(handle != 0L) { "rac_hybrid_router_create failed" }
    }

    /** @return underlying rac_hybrid_router_t handle. Internal use. */
    internal fun nativeHandle(): Long = handle

    /**
     * Configure cascade behavior. Default: enabled, threshold 0.5.
     * @param threshold confidence below which a local primary cascades to
     *   the next candidate. Range 0..1.
     */
    fun setCascade(enabled: Boolean = true, threshold: Float = 0.5f): Boolean {
        require(threshold in 0.0f..1.0f) { "threshold must be in [0, 1]" }
        return RunAnywhereBridge.racHybridRouterSetCascade(handle, enabled, threshold) == 0
    }

    /**
     * Register an STT backend. Capability of this router must be [Capability.STT].
     *
     * @param componentHandle pointer from `racSttComponentCreate` after a
     *   successful `racSttComponentLoadModel`.
     */
    fun registerStt(componentHandle: Long, descriptor: BackendDescriptor): Boolean {
        require(capability == Capability.STT) { "router capability is $capability, not STT" }
        require(descriptor.capability == Capability.STT) { "descriptor capability mismatch" }
        val rc = RunAnywhereBridge.racHybridRouterRegisterStt(
            routerHandle = handle,
            componentHandle = componentHandle,
            moduleId = descriptor.moduleId,
            moduleName = descriptor.moduleName,
            priority = descriptor.basePriority,
            isLocalOnly = descriptor.isLocalOnly,
            needsNetwork = descriptor.needsNetwork,
            costCentsPerMinute = descriptor.costCentsPerMinute,
            inferenceFramework = descriptor.inferenceFramework,
        )
        if (rc != 0) logger.warn("registerStt('${descriptor.moduleId}') rc=$rc")
        return rc == 0
    }

    /**
     * Register a VAD backend. Capability of this router must be [Capability.VAD].
     *
     * @param serviceHandle pointer to a `rac_vad_routing_service_t` (see
     *   `include/rac/routing/rac_vad_routing.h`). Backend adapters supply this.
     */
    fun registerVad(serviceHandle: Long, descriptor: BackendDescriptor): Boolean {
        require(capability == Capability.VAD) { "router capability is $capability, not VAD" }
        require(descriptor.capability == Capability.VAD) { "descriptor capability mismatch" }
        val rc = RunAnywhereBridge.racHybridRouterRegisterVad(
            routerHandle = handle,
            serviceHandle = serviceHandle,
            moduleId = descriptor.moduleId,
            moduleName = descriptor.moduleName,
            priority = descriptor.basePriority,
            isLocalOnly = descriptor.isLocalOnly,
            needsNetwork = descriptor.needsNetwork,
            costCentsPerMinute = descriptor.costCentsPerMinute,
            inferenceFramework = descriptor.inferenceFramework,
        )
        if (rc != 0) logger.warn("registerVad('${descriptor.moduleId}') rc=$rc")
        return rc == 0
    }

    fun unregister(moduleId: String): Boolean =
        RunAnywhereBridge.racHybridRouterUnregister(handle, moduleId) == 0

    /** @return number of backends currently registered. */
    fun count(): Int = RunAnywhereBridge.racHybridRouterCount(handle)

    /**
     * Run STT through this router. Capability must be [Capability.STT].
     * @throws IllegalStateException when no candidate is eligible or all fail.
     */
    fun transcribe(
        audioData: ByteArray,
        context: RoutingContext,
        optionsJson: String? = null,
    ): RoutedSttResult {
        require(capability == Capability.STT) { "router capability is $capability, not STT" }
        val effectivePolicy = when (context.policy) {
            is Policy.Custom -> {
                logger.warn("Policy.Custom not yet wired across JNI — falling back to Auto")
                Policy.Auto.value
            }
            else -> context.policy.value
        }
        val json = RunAnywhereBridge.racHybridRouterRunStt(
            routerHandle = handle,
            isOnline = context.isOnline,
            policy = effectivePolicy,
            preferredFramework = context.preferredFramework,
            audioData = audioData,
            optionsJson = optionsJson,
        ) ?: throw IllegalStateException(
            "Router returned no result (no eligible backend, or all failed)"
        )
        return parseSttJson(json)
    }

    /**
     * Run VAD on one frame of float PCM samples. Capability must be [Capability.VAD].
     * @throws IllegalStateException when no candidate is eligible or all fail.
     */
    fun detect(samples: FloatArray, context: RoutingContext): RoutedVadResult {
        require(capability == Capability.VAD) { "router capability is $capability, not VAD" }
        val effectivePolicy = if (context.policy is Policy.Custom) Policy.Auto.value
                              else context.policy.value
        val json = RunAnywhereBridge.racHybridRouterRunVad(
            routerHandle = handle,
            isOnline = context.isOnline,
            policy = effectivePolicy,
            preferredFramework = context.preferredFramework,
            samples = samples,
        ) ?: throw IllegalStateException(
            "VAD router returned no result (no eligible backend, or all failed)"
        )
        return parseVadJson(json)
    }

    private fun parseVadJson(json: String): RoutedVadResult {
        fun bool(key: String): Boolean =
            Regex("\"$key\"\\s*:\\s*(true|false)").find(json)
                ?.groupValues?.get(1) == "true"
        fun int(key: String): Int =
            Regex("\"$key\"\\s*:\\s*(-?\\d+)").find(json)
                ?.groupValues?.get(1)?.toIntOrNull() ?: 0
        fun str(key: String, default: String = ""): String =
            Regex("\"$key\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(json)
                ?.groupValues?.get(1) ?: default
        fun float(key: String): Float {
            val m = Regex("\"$key\"\\s*:\\s*(null|-?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)").find(json)
                ?: return Float.NaN
            val raw = m.groupValues[1]
            return if (raw == "null") Float.NaN else raw.toFloatOrNull() ?: Float.NaN
        }
        return RoutedVadResult(
            isSpeech = bool("is_speech"),
            confidence = float("confidence"),
            chosenModuleId = str("chosen_module_id"),
            wasFallback = bool("was_fallback"),
            attemptCount = int("attempt_count"),
        )
    }

    override fun close() {
        if (handle != 0L) RunAnywhereBridge.racHybridRouterDestroy(handle)
    }

    // --- JSON parsing (regex-based to match the rest of the bridge layer) ---

    private fun parseSttJson(json: String): RoutedSttResult {
        fun str(key: String, default: String = ""): String =
            Regex("\"$key\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(json)
                ?.groupValues?.get(1) ?: default

        fun long(key: String): Long =
            Regex("\"$key\"\\s*:\\s*(-?\\d+)").find(json)
                ?.groupValues?.get(1)?.toLongOrNull() ?: 0L

        fun int(key: String): Int =
            Regex("\"$key\"\\s*:\\s*(-?\\d+)").find(json)
                ?.groupValues?.get(1)?.toIntOrNull() ?: 0

        fun bool(key: String): Boolean =
            Regex("\"$key\"\\s*:\\s*(true|false)").find(json)
                ?.groupValues?.get(1) == "true"

        fun float(key: String): Float {
            val m = Regex("\"$key\"\\s*:\\s*(null|-?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)").find(json)
                ?: return Float.NaN
            val raw = m.groupValues[1]
            if (raw == "null") return Float.NaN
            return raw.toFloatOrNull() ?: Float.NaN
        }

        return RoutedSttResult(
            text = str("text"),
            language = str("language", "en"),
            durationMs = long("duration_ms"),
            confidence = float("confidence"),
            chosenModuleId = str("chosen_module_id"),
            wasFallback = bool("was_fallback"),
            primaryConfidence = float("primary_confidence"),
            attemptCount = int("attempt_count"),
            cascadeErrorCode = int("cascade_error_code"),
            cascadeErrorModuleId = str("cascade_error_module_id"),
        )
    }
}
