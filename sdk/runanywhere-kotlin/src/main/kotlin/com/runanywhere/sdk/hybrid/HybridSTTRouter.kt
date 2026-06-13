/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * THIN Kotlin binding over the commons STT hybrid router
 * (rac_stt_hybrid_router + its proto-byte ABI). Per-request dispatch between
 * an on-device (offline, sherpa) STT service and a cloud (online, cloud)
 * STT service.
 *
 * Division of labour — commons owns ALL routing:
 *   - filter phase, rank/sort, confidence cascade, and primary→secondary
 *     fallback all live in rac_stt_hybrid_router.cpp. NONE of that logic is
 *     reimplemented here.
 * This binding only:
 *   1. creates the router handle,
 *   2. creates the two STT services through the registry-routed creation path
 *      and attaches them with their descriptors,
 *   3. registers any custom-filter predicates and installs the policy bytes,
 *   4. drives the router's transcribe and decodes the response (raw-PCM16 →
 *      WAV normalisation happens inside the commons router so one payload
 *      serves both services).
 *
 * Mirrors Swift's HybridSTTRouter.swift (same member names + semantics);
 * Closeable is retained as the Kotlin lifetime idiom.
 *
 * Lifetime: the router does NOT own the underlying services. This class keeps
 * each native service handle for the router's lifetime, clears the router
 * slots before destroying the services (avoiding the use-after-free called
 * out in rac_stt_hybrid_router.h), and tears everything down in close().
 */

package com.runanywhere.sdk.hybrid

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.Closeable
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode

/**
 * A hybrid STT router pairing one offline + one online speech service.
 *
 * Usage:
 * ```kotlin
 * Cloud.register()                  // fold the cloud plugin in
 * Cloud.register(id = "saaras", provider = "sarvam", model = "saaras:v3", apiKey = "…")
 * HybridDeviceState.setProvider(myProvider)   // optional: live Network/Battery
 *
 * val router = HybridSTTRouter()
 * router.setPair(
 *     offline = HybridModel.offlineSherpa("sherpa-onnx-whisper-tiny.en"),
 *     online = HybridModel.onlineCloud("saaras"),
 *     policy = HybridRoutingPolicy(
 *         hardFilters = listOf(HybridFilter.Network),
 *         cascade = HybridCascade.Confidence(threshold = 0.5f),
 *         rank = HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST,
 *     ),
 * )
 * val result = router.transcribe(pcm16Audio, HybridTranscribeOptions(sample_rate = 16000))
 * router.close()
 * ```
 *
 * Owns native resources (router handle + per-side service handles). Always
 * release via [close] or use as a `Closeable` in a `use { }` block; [close]
 * is idempotent.
 */
class HybridSTTRouter : Closeable {
    private var nativeHandle: Long
    private var offlineServiceHandle: Long = 0L
    private var onlineServiceHandle: Long = 0L

    /**
     * Names of custom-filter predicates registered for the current policy,
     * so [setPair] can replace and [close] can unregister exactly those.
     * Commons — not Kotlin — invokes the predicates while filtering.
     */
    private var registeredCustomFilterNames: List<String> = emptyList()

    /** Create the native router handle. */
    init {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        nativeHandle = RunAnywhereBridge.racSttHybridRouterCreate()
        if (nativeHandle == 0L) {
            throw serviceError("rac_stt_hybrid_router_create failed")
        }
    }

    // Pair + policy

    /**
     * Bind the offline + online models, install the policy, and register any
     * custom-filter predicates. Replaces any previous pairing.
     */
    @Synchronized
    fun setPair(
        offline: HybridModel,
        online: HybridModel,
        policy: HybridRoutingPolicy,
    ) {
        val handle = requireOpen()

        // Build both services up-front so a failure on the online side doesn't
        // leave a half-attached router.
        val offlineService = HybridRouterBridgeAdapter.createService(offline)
        val onlineService =
            try {
                HybridRouterBridgeAdapter.createService(online)
            } catch (t: Throwable) {
                HybridRouterBridgeAdapter.destroyService(offlineService)
                throw t
            }

        // Serialize all proto bytes (descriptors + policy) up-front, before
        // mutating any installed state. The router copies the bytes into its
        // own storage on each set call.
        val offlineDescriptor = HybridRouterProto.descriptor(offline)
        val onlineDescriptor = HybridRouterProto.descriptor(online)
        val packed = HybridRouterProto.policy(policy)

        // Detach + destroy any previously attached services before swapping in
        // the new pair (clear router slots first — see header UAF note), and
        // retire the previous policy's custom-filter predicates so re-pairing
        // with a different policy doesn't leave stale named filters registered
        // in commons.
        clearAndDestroyServices(handle)
        unregisterCustomFilters()

        val rcOff =
            RunAnywhereBridge.racSttHybridRouterSetOfflineService(
                routerHandle = handle,
                serviceHandle = offlineService,
                descriptorProto = offlineDescriptor,
            )
        if (rcOff != RunAnywhereBridge.RAC_SUCCESS) {
            destroyBoth(offlineService, onlineService)
            throw serviceError("racSttHybridRouterSetOfflineService failed (rc=$rcOff)")
        }
        val rcOn =
            RunAnywhereBridge.racSttHybridRouterSetOnlineService(
                routerHandle = handle,
                serviceHandle = onlineService,
                descriptorProto = onlineDescriptor,
            )
        if (rcOn != RunAnywhereBridge.RAC_SUCCESS) {
            RunAnywhereBridge.racSttHybridRouterSetOfflineService(handle, 0L, ByteArray(0))
            destroyBoth(offlineService, onlineService)
            throw serviceError("racSttHybridRouterSetOnlineService failed (rc=$rcOn)")
        }

        // Register custom-filter predicates with commons BEFORE installing the
        // policy bytes, so the router can resolve each HybridFilter.Custom name
        // the first time it filters. The router owns the eval — Kotlin only
        // supplies the named predicate.
        val customNames = packed.customFilters.map { it.name }
        for (custom in packed.customFilters) {
            HybridCustomFilter.register(name = custom.name, check = custom.check)
        }

        val rcPolicy = RunAnywhereBridge.racSttHybridRouterSetPolicy(handle, packed.bytes)
        if (rcPolicy != RunAnywhereBridge.RAC_SUCCESS) {
            for (name in customNames) {
                HybridCustomFilter.unregister(name)
            }
            RunAnywhereBridge.racSttHybridRouterSetOfflineService(handle, 0L, ByteArray(0))
            RunAnywhereBridge.racSttHybridRouterSetOnlineService(handle, 0L, ByteArray(0))
            destroyBoth(offlineService, onlineService)
            throw serviceError("racSttHybridRouterSetPolicy failed (rc=$rcPolicy)")
        }

        offlineServiceHandle = offlineService
        onlineServiceHandle = onlineService
        registeredCustomFilterNames = customNames
    }

    // Transcribe

    /**
     * Run one transcribe request through the router. The router applies the
     * installed policy (filters → rank → invoke → fallback) in commons and
     * returns the chosen backend's result plus the routing decision.
     *
     * @param audio   Raw 16-bit mono PCM bytes (pass the capture rate via
     *                [HybridTranscribeOptions.sample_rate]) OR file-encoded
     *                audio (wav/mp3/flac/...). Raw PCM16 is wrapped in a WAV
     *                container by the commons router
     *                (rac_stt_hybrid_router_proto.cpp); WAV input (RIFF/WAVE
     *                magic) and declared compressed formats pass through
     *                unchanged.
     * @param options Optional language / sample-rate / audio-format hints
     *                (proto-typed [HybridTranscribeOptions]).
     */
    @Synchronized
    fun transcribe(
        audio: ByteArray,
        options: HybridTranscribeOptions = HybridTranscribeOptions(),
    ): HybridTranscribeResult {
        val handle = requireOpen()

        val responseBytes =
            RunAnywhereBridge.racSttHybridRouterTranscribe(
                routerHandle = handle,
                requestProto = HybridSttRouterProto.request(audio, options),
            ) ?: throw serviceError("racSttHybridRouterTranscribe returned no response")

        return HybridSttRouterProto.parseResponse(responseBytes)
    }

    /**
     * Cancel an in-flight transcribe, if any. (Best-effort: no STT engine
     * exposes a cancel op today, so commons treats this as a no-op until one
     * does — see rac_stt_hybrid_router_cancel.)
     */
    @Synchronized
    fun cancel() {
        val handle = nativeHandle
        if (handle == 0L) {
            return
        }
        RunAnywhereBridge.racSttHybridRouterCancel(handle)
    }

    // Teardown

    /**
     * Detach + destroy both services, unregister custom filters, and destroy
     * the router handle. Idempotent.
     */
    @Synchronized
    override fun close() {
        val handle = nativeHandle
        if (handle != 0L) {
            clearAndDestroyServices(handle)
            RunAnywhereBridge.racSttHybridRouterDestroy(handle)
            nativeHandle = 0L
        }
        unregisterCustomFilters()
    }

    // Internals

    /**
     * Clear both router slots, then destroy whatever services were attached.
     * Slot-clearing must precede service destruction (router holds raw
     * pointers — see rac_stt_hybrid_router.h UAF note).
     */
    private fun clearAndDestroyServices(handle: Long) {
        RunAnywhereBridge.racSttHybridRouterSetOfflineService(handle, 0L, ByteArray(0))
        RunAnywhereBridge.racSttHybridRouterSetOnlineService(handle, 0L, ByteArray(0))
        destroyBoth(offlineServiceHandle, onlineServiceHandle)
        offlineServiceHandle = 0L
        onlineServiceHandle = 0L
    }

    private fun destroyBoth(
        offlineService: Long,
        onlineService: Long,
    ) {
        HybridRouterBridgeAdapter.destroyService(offlineService)
        HybridRouterBridgeAdapter.destroyService(onlineService)
    }

    /**
     * Unregister every custom-filter predicate this router installed in the
     * commons callback table. Idempotent.
     */
    private fun unregisterCustomFilters() {
        for (name in registeredCustomFilterNames) {
            HybridCustomFilter.unregister(name)
        }
        registeredCustomFilterNames = emptyList()
    }

    private fun requireOpen(): Long {
        val handle = nativeHandle
        if (handle == 0L) {
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
                message = "HybridSTTRouter is closed",
            )
        }
        return handle
    }

    private fun serviceError(message: String): SDKException =
        SDKException.make(
            code = ProtoErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
            message = message,
        )
}
