/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Hybrid router facade.
 *
 * Per-request dispatch between an on-device (offline) backend and a cloud
 * (online) backend. The user-visible accessors read as:
 *   RACRouter.stt.init(...)
 *   RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.NETWORK())
 *   RACRouter.AdvanceRouterPolicy { hardFilters = arrayOf(...) ... }
 *   router.stt.addPair(model1, model2, routerPolicy)
 *   router.stt.transcribe(audio)
 *
 * Only the STT capability is wired today (offline sherpa ↔ cloud, e.g.
 * the Sarvam provider).
 * `router.tts` / `router.vlm` accessors exist for the API shape but raise
 * NotImplementedError.
 */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.HybridRank
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.Closeable

/**
 * Candidate comparator for a routing policy. Aliased to the generated
 * [HybridRank] so the wire numbering is maintained in one place;
 * [RACRouter.RoutingPolicy.PreferLocalFirst] /
 * [RACRouter.RoutingPolicy.PreferOnlineFirst] expose the ergonomic names.
 */
typealias Rank = HybridRank

/**
 * Multi-capability hybrid router.
 *
 * Obtain an instance from the static [Companion.stt] factory:
 *
 *     val router = RACRouter.stt.init(
 *         backendOffline = BACKEND.SHERPA.STT,
 *         backendOnline  = BACKEND.CLOUD.STT,
 *     )
 *     router.stt.addPair(
 *         model1 = RACModel(id = "sherpa-onnx-whisper-tiny.en", modelType = ROUTER.OFFLINE),
 *         model2 = RACModel(id = "saaras", modelType = ROUTER.ONLINE),
 *         routerPolicy = RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.PreferLocalFirst),
 *     )
 *     val result = router.stt.transcribe(audioBytes)
 *     router.close()
 *
 * Owns native resources (router handle + per-side service handles).
 * Always release via [close] or use as a `Closeable` in a `use { }` block.
 */
class RACRouter internal constructor() : Closeable {
    /** STT capability slot. See [SttRouter]. */
    val stt: SttRouter = SttRouter()

    /** TTS slot — currently throws on use (STT-only today). */
    val tts: NotImplementedCapability = NotImplementedCapability("tts")

    /** VLM slot — currently throws on use (STT-only today). */
    val vlm: NotImplementedCapability = NotImplementedCapability("vlm")

    /**
     * Release all native resources owned by this router. After [close]
     * returns, any further call on `router.stt.*` will throw. Safe to call
     * multiple times.
     */
    override fun close() {
        stt.close()
    }

    // Filter / Cascade / Rank interfaces and the RoutingPolicy accessor.

    /**
     * Hard eligibility predicate. Each filter drops candidates that don't
     * pass; surviving candidates are then ranked. Filters compose with AND
     * — every filter in a policy must pass for a candidate to be eligible.
     *
     * Concrete filters live under [RoutingPolicy] (e.g.
     * [RoutingPolicy.NETWORK], [RoutingPolicy.Quality],
     * [RoutingPolicy.Battery], [RoutingPolicy.CustomDefine]).
     *
     * The wire shape is the generated `HybridFilter` oneof; the mapping from
     * each concrete Kotlin filter to its proto field lives in
     * [HybridRouterProto.policy], so no hand-maintained discriminator is needed
     * here.
     */
    interface Filter

    /**
     * Mid-request fallback trigger. At most one cascade per policy. The
     * configured cascade fires when the primary candidate succeeds with
     * a sub-threshold confidence signal, OR when the primary errors out
     * (errors are treated as "no confidence" at the C level).
     *
     * The wire shape is the generated `HybridCascade` oneof; the mapping from
     * each concrete Kotlin cascade to its proto field lives in
     * [HybridRouterProto.policy].
     */
    interface Cascade

    /**
     * Catalog of routing-policy primitives.
     *
     * Filters, cascades, and ranks are constructed via the nested types
     * here, e.g. `RACRouter.RoutingPolicy.NETWORK()`,
     * `RACRouter.RoutingPolicy.Confidence(0.5f)`,
     * `RACRouter.RoutingPolicy.PreferLocalFirst`.
     */
    object RoutingPolicy {
        /**
         * Filter: drops online candidates when the device has no network.
         * Offline candidates are unaffected. The network state is detected
         * by the SDK internally before each request — callers don't pass
         * it in.
         */
        class NETWORK : Filter

        /**
         * Filter: requires the candidate to meet at least [tier]. Reserved
         * for future use — descriptors do not yet carry a quality tier in
         * the v1 wire schema, so this filter is currently a no-op on the
         * native side.
         *
         * @property tier Minimum tier the candidate must declare.
         */
        class Quality(
            val tier: Int = 1,
        ) : Filter

        /**
         * Filter: drops online candidates when the device is below
         * [minPercent] battery. Offline candidates are unaffected.
         *
         * @property minPercent Minimum battery percentage (0–100) required
         *                      to keep the online candidate eligible.
         */
        class Battery(
            val minPercent: Int = 20,
        ) : Filter

        /**
         * Filter: caller-supplied predicate. The router registers it by
         * [name] in the cross-SDK commons callback table; commons invokes it
         * once per candidate, per request, during its filtering phase. Return
         * `true` to keep the candidate eligible, `false` to drop it.
         *
         * The callback is invoked synchronously on the request thread —
         * keep it fast and side-effect-free.
         *
         * [name] doubles as the wire identity (`CustomFilter.name`) that links
         * the policy proto entry to the registered predicate, so it must be
         * non-blank and unique within a policy.
         *
         * @property name        Wire identity + log label; non-blank, unique.
         * @property description Human-readable purpose for the filter.
         * @property check       Lambda `(modelId) -> Boolean` deciding
         *                       eligibility for the given candidate.
         */
        class CustomDefine(
            val name: String,
            val description: String,
            val check: (modelId: String) -> Boolean,
        ) : Filter

        /**
         * Cascade: when the primary backend's confidence signal falls
         * below [threshold] (or the primary errors out), the router
         * invokes the secondary candidate. The primary result is
         * discarded when the secondary succeeds.
         *
         * @property threshold Confidence value `[0..1]` below which the
         *                     cascade fires.
         */
        class Confidence(
            val threshold: Float,
        ) : Cascade

        /**
         * Prefer the local (offline) candidate when both candidates pass
         * the filter phase.
         */
        val PreferLocalFirst: Rank = HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST

        /**
         * Prefer the online (cloud) candidate when both candidates pass
         * the filter phase.
         */
        val PreferOnlineFirst: Rank = HybridRank.HYBRID_RANK_PREFER_ONLINE_FIRST
    }

    /**
     * Marker for the two policy shapes the router accepts. See
     * [SimpleRouterPolicy] for the one-filter shorthand and
     * [AdvanceRouterPolicy] for the composed builder form.
     */
    sealed interface RouterPolicyBase

    /**
     * Policy that carries one of [Filter], [Cascade], or [Rank]. Convenient
     * when only a single routing primitive is needed:
     *
     *     RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.NETWORK())
     *     RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.Confidence(0.5f))
     *     RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.PreferOnlineFirst)
     *
     * Exactly one of [filter] / [cascade] / [rank] is non-null. Use
     * [AdvanceRouterPolicy] when you need to combine more than one.
     *
     * @property filter  Eligibility predicate, when constructed from a [Filter].
     * @property cascade Mid-request fallback trigger, when constructed from a [Cascade].
     * @property rank    Comparator, when constructed from a [Rank].
     */
    class SimpleRouterPolicy private constructor(
        val filter: Filter?,
        val cascade: Cascade?,
        val rank: Rank?,
    ) : RouterPolicyBase {
        /** Single-filter policy. */
        constructor(filter: Filter) : this(filter = filter, cascade = null, rank = null)

        /** Single-cascade policy (no filters; default rank applied). */
        constructor(cascade: Cascade) : this(filter = null, cascade = cascade, rank = null)

        /** Single-rank policy (no filters or cascade; just order candidates). */
        constructor(rank: Rank) : this(filter = null, cascade = null, rank = rank)
    }

    /**
     * Composed policy — multiple filters (AND), optional cascade, optional
     * rank. Constructed via the lambda invoke convention:
     *
     *     val policy = RACRouter.AdvanceRouterPolicy {
     *         hardFilters = arrayOf(
     *             RACRouter.RoutingPolicy.NETWORK(),
     *             RACRouter.RoutingPolicy.Battery(minPercent = 20),
     *         )
     *         cascadeConditions = RACRouter.RoutingPolicy.Confidence(0.5f)
     *         rankSort = RACRouter.RoutingPolicy.PreferLocalFirst
     *     }
     *
     * @property hardFilters       Filters AND-composed against every candidate.
     * @property cascadeConditions Optional mid-request fallback trigger.
     * @property rankSort          Optional comparator (defaults to PreferLocalFirst).
     */
    class AdvanceRouterPolicy : RouterPolicyBase {
        var hardFilters: Array<Filter> = emptyArray()
        var cascadeConditions: Cascade? = null
        var rankSort: Rank? = null

        companion object {
            /**
             * Construct via lambda: `AdvanceRouterPolicy { hardFilters = ... }`.
             * The receiver inside [init] is the fresh policy instance.
             */
            operator fun invoke(init: AdvanceRouterPolicy.() -> Unit): AdvanceRouterPolicy =
                AdvanceRouterPolicy().apply(init)
        }
    }

    // STT capability slot.

    /**
     * STT-capability slot — owns one native router handle plus one
     * offline + one online native `rac_stt_service_t` handle.
     *
     * Lifecycle: created uninitialised by the parent [RACRouter]. Becomes
     * usable after [configureBackends] (called by the static factory) and
     * [addPair] (called by the app). [transcribe] dispatches a single
     * request; [close] releases all native resources.
     */
    class SttRouter internal constructor() : Closeable {
        private var nativeHandle: Long = 0L
        private var offlineBackend: BackendId? = null
        private var onlineBackend: BackendId? = null
        private var offlineModel: RACModel? = null
        private var onlineModel: RACModel? = null
        private var offlineServiceHandle: Long = 0L
        private var onlineServiceHandle: Long = 0L

        /**
         * Names of the custom filters this router currently has registered in
         * the commons callback table (one per [RoutingPolicy.CustomDefine] in
         * the active policy). Tracked so [addPair] can replace and [close] can
         * unregister them. Commons — not Kotlin — invokes the predicates while
         * filtering candidates.
         */
        private var registeredCustomFilterNames: List<String> = emptyList()

        init {
            RunAnywhereBridge.ensureNativeLibraryLoaded()
        }

        /**
         * Allocate the native router and remember the backend ids for
         * later service creation. Called by [Companion.stt].init(...).
         * Idempotent — calling twice frees the previous handle first.
         */
        internal fun configureBackends(offline: BackendId, online: BackendId) {
            close()
            this.offlineBackend = offline
            this.onlineBackend = online
            nativeHandle = RunAnywhereBridge.racSttHybridRouterCreate()
            check(nativeHandle != 0L) { "racSttHybridRouterCreate returned 0" }
        }

        /**
         * Bind concrete models to the offline + online sides and install
         * the routing policy.
         *
         * Order of [model1] and [model2] doesn't matter — the OFFLINE one
         * is bound to the offline slot, the ONLINE one to the online slot.
         * Calling twice replaces the previous bindings.
         */
        fun addPair(model1: RACModel, model2: RACModel, routerPolicy: RouterPolicyBase) {
            check(nativeHandle != 0L) { "Call RACRouter.stt.init(...) first" }
            val offModel = if (model1.modelType == ROUTER.OFFLINE) model1 else model2
            val onModel = if (model1.modelType == ROUTER.ONLINE) model1 else model2
            require(offModel.modelType == ROUTER.OFFLINE && onModel.modelType == ROUTER.ONLINE) {
                "addPair requires one OFFLINE and one ONLINE model"
            }
            val offBackend = offlineBackend ?: error("init() not called")
            val onBackend = onlineBackend ?: error("init() not called")

            HybridRouterBridgeAdapter.destroyService(offlineServiceHandle)
            HybridRouterBridgeAdapter.destroyService(onlineServiceHandle)

            offlineServiceHandle = HybridRouterBridgeAdapter.createService(offBackend, offModel)
            onlineServiceHandle = HybridRouterBridgeAdapter.createService(onBackend, onModel)
            offlineModel = offModel
            onlineModel = onModel

            val rc1 =
                RunAnywhereBridge.racSttHybridRouterSetOfflineService(
                    routerHandle = nativeHandle,
                    serviceHandle = offlineServiceHandle,
                    descriptorProto =
                        HybridRouterProto.descriptor(
                            offModel,
                            offBackend.kindEnum,
                            offBackend.provider,
                        ),
                )
            check(rc1 == RunAnywhereBridge.RAC_SUCCESS) {
                "racSttHybridRouterSetOfflineService rc=$rc1"
            }
            val rc2 =
                RunAnywhereBridge.racSttHybridRouterSetOnlineService(
                    routerHandle = nativeHandle,
                    serviceHandle = onlineServiceHandle,
                    descriptorProto =
                        HybridRouterProto.descriptor(
                            onModel,
                            onBackend.kindEnum,
                            onBackend.provider,
                        ),
                )
            check(rc2 == RunAnywhereBridge.RAC_SUCCESS) {
                "racSttHybridRouterSetOnlineService rc=$rc2"
            }

            val packed = HybridRouterProto.policy(routerPolicy)

            // Register each custom filter's predicate by NAME with the
            // cross-SDK commons callback table. Commons evaluates them during
            // candidate filtering — the Kotlin layer does NOT pre-filter or
            // toggle router slots. Replace any filters from a previous addPair
            // first so re-binding a new policy doesn't leak stale callbacks.
            unregisterCustomFilters()
            for (custom in packed.customFilters) {
                val rc =
                    RunAnywhereBridge.racHybridRegisterCustomFilter(
                        name = custom.name,
                        predicate = CustomFilterPredicate { modelId -> custom.check(modelId) },
                    )
                check(rc == RunAnywhereBridge.RAC_SUCCESS) {
                    "racHybridRegisterCustomFilter('${custom.name}') rc=$rc"
                }
            }
            registeredCustomFilterNames = packed.customFilters.map { it.name }

            val rc3 = RunAnywhereBridge.racSttHybridRouterSetPolicy(nativeHandle, packed.bytes)
            check(rc3 == RunAnywhereBridge.RAC_SUCCESS) {
                "racSttHybridRouterSetPolicy rc=$rc3"
            }
        }

        /**
         * Unregister every custom-filter predicate this router installed in the
         * commons callback table. Idempotent.
         */
        private fun unregisterCustomFilters() {
            for (name in registeredCustomFilterNames) {
                RunAnywhereBridge.racHybridUnregisterCustomFilter(name)
            }
            registeredCustomFilterNames = emptyList()
        }

        /**
         * Run one transcribe request through the router.
         *
         * @param audioBytes  File-encoded audio (wav/mp3/flac/...) OR raw
         *                    PCM bytes. Each engine decodes per its own
         *                    expectations: the cloud provider (e.g. Sarvam)
         *                    sends the bytes as a
         *                    multipart file part; sherpa parses WAV
         *                    inline.
         * @param language    Optional BCP-47 hint. Empty = auto-detect.
         * @param sampleRate  Hint for raw PCM (0 = engine default 16000).
         * @param audioFormat rac_audio_format_enum_t value (0=PCM, 1=WAV,
         *                    2=MP3, 3=OPUS, 4=AAC, 5=FLAC). 0 leaves it
         *                    unspecified.
         */
        fun transcribe(
            audioBytes: ByteArray,
            language: String = "",
            sampleRate: Int = 0,
            audioFormat: Int = 0,
        ): TranscribeResult {
            check(nativeHandle != 0L) { "Call init() then addPair() first" }
            check(offlineModel != null && onlineModel != null) { "addPair() not called" }

            // Pure pass-through: commons owns the entire routing decision —
            // hard-filter eligibility (including custom-filter callbacks),
            // ranking, and cascade. Kotlin marshals the request and decodes the
            // response; it does NOT pre-filter candidates or toggle slots.
            val responseBytes =
                RunAnywhereBridge.racSttHybridRouterTranscribe(
                    routerHandle = nativeHandle,
                    requestProto =
                        HybridSttRouterProto.request(
                            audioBytes = audioBytes,
                            language = language,
                            sampleRate = sampleRate,
                            audioFormat = audioFormat,
                        ),
                ) ?: error("racSttHybridRouterTranscribe returned null envelope")
            return HybridSttRouterProto.parseResponse(responseBytes)
        }

        /**
         * Tear down the native router and both per-side service handles.
         * Safe to call multiple times. Called from [RACRouter.close].
         */
        override fun close() {
            unregisterCustomFilters()
            if (nativeHandle != 0L) {
                RunAnywhereBridge.racSttHybridRouterSetOfflineService(nativeHandle, 0L, ByteArray(0))
                RunAnywhereBridge.racSttHybridRouterSetOnlineService(nativeHandle, 0L, ByteArray(0))
                RunAnywhereBridge.racSttHybridRouterDestroy(nativeHandle)
                nativeHandle = 0L
            }
            HybridRouterBridgeAdapter.destroyService(offlineServiceHandle)
            offlineServiceHandle = 0L
            HybridRouterBridgeAdapter.destroyService(onlineServiceHandle)
            onlineServiceHandle = 0L
            offlineBackend = null
            onlineBackend = null
            offlineModel = null
            onlineModel = null
        }
    }

    /**
     * Placeholder slot for capabilities not yet wired. Every call surface
     * throws [NotImplementedError] with the capability name — the type
     * exists so `router.tts` / `router.vlm` compile and the
     * multi-capability API surface stays consistent.
     *
     * @property name Capability label used in error messages.
     */
    class NotImplementedCapability internal constructor(
        private val name: String,
    ) {
        /** Throws — TTS/VLM not wired. */
        fun addPair(model1: RACModel, model2: RACModel, routerPolicy: RouterPolicyBase): Nothing =
            throw NotImplementedError("router.$name is not wired yet (STT only)")

        /** Throws — TTS not wired. */
        fun synthesize(text: String): Nothing =
            throw NotImplementedError("router.$name.synthesize is not wired yet")

        /** Throws — VLM/etc. not wired. */
        fun generate(input: Any): Nothing =
            throw NotImplementedError("router.$name.generate is not wired yet")
    }

    // Static entry point: RACRouter.stt.init(backendOffline, backendOnline)

    companion object {
        /** Static factory for STT-capability routers. See [SttFactory.init]. */
        val stt: SttFactory = SttFactory()

        /**
         * Register the host's device-state provider. Wires the Kotlin
         * object into the cross-SDK `rac_hybrid_device_state` vtable in
         * commons so the router's NETWORK / Battery filters see live
         * values on every request.
         *
         * Pass `null` to unregister and fall back to commons' optimistic
         * default (always-online, 100% battery, not-throttled).
         *
         * Typical Android wiring (call once after SDK init):
         *
         *     RACRouter.setDeviceStateProvider(
         *         AndroidDeviceStateProvider(applicationContext)
         *     )
         *
         * Thread-safe. The native vtable swap is atomic.
         */
        @JvmStatic
        fun setDeviceStateProvider(provider: DeviceStateProvider?) {
            RunAnywhereBridge.ensureNativeLibraryLoaded()
            val rc = RunAnywhereBridge.racHybridSetDeviceState(provider)
            check(rc == RunAnywhereBridge.RAC_SUCCESS) {
                "racHybridSetDeviceState rc=$rc"
            }
        }
    }

    /**
     * Static factory that returns a fresh [RACRouter] with its STT slot
     * wired to the requested backends. Equivalent to:
     *
     *     val router = RACRouter()
     *     router.stt.configureBackends(offline, online)
     *
     * The factory exists so the user-facing call reads
     * `RACRouter.stt.init(...)`.
     */
    class SttFactory internal constructor() {
        /**
         * Allocate a new router and configure both STT backends.
         *
         * @param backendOffline The on-device backend (e.g. [BACKEND.SHERPA.STT]).
         * @param backendOnline  The cloud backend (e.g. [BACKEND.CLOUD.STT]).
         * @return Ready-to-`addPair` router. Caller owns and must [close].
         */
        fun init(backendOffline: BackendId, backendOnline: BackendId): RACRouter {
            val router = RACRouter()
            router.stt.configureBackends(offline = backendOffline, online = backendOnline)
            return router
        }
    }
}
