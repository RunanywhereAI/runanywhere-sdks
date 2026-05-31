/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Hybrid router facade.
 *
 * Mirrors the syntax declared in thoughts/file.txt. Nested types live on
 * the RACRouter class so the user-visible accessors read exactly as:
 *   RACRouter.llm.init(...)
 *   RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.NETWORK())
 *   RACRouter.AdvanceRouterPolicy { hardFilters = arrayOf(...) ... }
 *   router.llm.addPair(model1, model2, routerPolicy)
 *   router.llm.generate(prompt)
 *   router.stt.transcribe(audio)
 *   router.tts.synthesize(text)
 *
 * Multi-capability container: `router.stt` / `router.tts` / `router.vlm`
 * accessors exist for the syntax to compile, but raise NotImplementedError
 * — the POC only wires the LLM capability.
 */

package com.runanywhere.sdk.public.hybrid

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.Closeable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch

/**
 * Multi-capability hybrid router.
 *
 * One [RACRouter] instance can hold a wired LLM slot today and STT / TTS /
 * VLM slots once those are implemented. Instances are obtained from the
 * static [Companion.llm] factory:
 *
 *     val router = RACRouter.llm.init(
 *         backendOffline = BACKEND.LLAMACPP.TEXTGEN,
 *         backendOnline  = BACKEND.OPENROUTER.TEXTGEN,
 *     )
 *     router.llm.addPair(
 *         model1 = RACModel(id = "tinyllama-q4", modelType = ROUTER.OFFLINE),
 *         model2 = RACModel(id = "claude-haiku", modelType = ROUTER.ONLINE),
 *         routerPolicy = RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.NETWORK()),
 *     )
 *     val result = router.llm.generate("Hello")
 *     router.close()
 *
 * Owns native resources (router handle + per-side service handles).
 * Always release via [close] or use as a `Closeable` in a `use { }` block.
 */
class RACRouter internal constructor() : Closeable {

    /** LLM capability slot. Lazy-initialised — see [LlmRouter]. */
    val llm: LlmRouter = LlmRouter()

    /** STT capability slot. See [SttRouter]. */
    val stt: SttRouter = SttRouter()

    /** TTS slot — currently throws on use (LLM-only POC). */
    val tts: NotImplementedCapability = NotImplementedCapability("tts")

    /** VLM slot — currently throws on use (LLM-only POC). */
    val vlm: NotImplementedCapability = NotImplementedCapability("vlm")

    /**
     * Release all native resources owned by this router. After [close]
     * returns, any further call on `router.llm.*` / `router.stt.*` will
     * throw. Safe to call multiple times.
     */
    override fun close() {
        llm.close()
        stt.close()
    }

    // ----------------------------------------------------------------------
    // Filter / Cascade / Rank interfaces and the RoutingPolicy accessor.
    // ----------------------------------------------------------------------

    /**
     * Hard eligibility predicate. Each filter drops candidates that don't
     * pass; surviving candidates are then ranked. Filters compose with AND
     * — every filter in a policy must pass for a candidate to be eligible.
     *
     * Concrete filters live under [RoutingPolicy] (e.g.
     * [RoutingPolicy.NETWORK], [RoutingPolicy.Quality],
     * [RoutingPolicy.Battery], [RoutingPolicy.CustomDefine]).
     *
     * @property kind Wire tag (`HybridFilter.kind` in hybrid_router.proto).
     */
    interface Filter {
        /** Discriminator for JSON marshalling. */
        val kind: Int
    }

    /**
     * Mid-request fallback trigger. At most one cascade per policy. The
     * configured cascade fires when the primary candidate succeeds with
     * a sub-threshold confidence signal, OR when the primary errors out
     * (errors are treated as "no confidence" at the C level).
     *
     * @property kind Wire tag (`HybridCascade.kind` in hybrid_router.proto).
     */
    interface Cascade {
        /** Discriminator for JSON marshalling. */
        val kind: Int
    }

    /**
     * Comparator that orders eligible candidates. Exactly one rank per
     * policy.
     *
     * @property value Wire value matching `HybridRank` in hybrid_router.proto.
     */
    enum class Rank(val value: Int) {
        /** Prefer the offline candidate when both are eligible. */
        PreferLocalFirst(1),

        /** Prefer the online candidate when both are eligible. */
        PreferOnlineFirst(2),
    }

    /**
     * Catalog of routing-policy primitives. Modeled on the
     * `#Routing Conditions or Routing Policies` list in thoughts/file.txt.
     *
     * Filters, cascades, and ranks are constructed via the nested types
     * here, e.g. `RACRouter.RoutingPolicy.NETWORK()`,
     * `RACRouter.RoutingPolicy.Confidence(0.6f)`,
     * `RACRouter.RoutingPolicy.PreferLocalFirst`.
     */
    object RoutingPolicy {
        /**
         * Filter: drops online candidates when the device has no network.
         * Offline candidates are unaffected. The network state is detected
         * by the SDK internally before each request — callers don't pass
         * it in.
         */
        class NETWORK : Filter {
            override val kind: Int = 1
        }

        /**
         * Filter: requires the candidate to meet at least [tier]. Reserved
         * for future use — descriptors do not yet carry a quality tier in
         * the v1 wire schema, so this filter is currently a no-op on the
         * native side.
         *
         * @property tier Minimum tier the candidate must declare.
         */
        class Quality(val tier: Int = 1) : Filter {
            override val kind: Int = 3
        }

        /**
         * Filter: drops online candidates when the device is below
         * [minPercent] battery. Offline candidates are unaffected.
         *
         * @property minPercent Minimum battery percentage (0–100) required
         *                      to keep the online candidate eligible.
         */
        class Battery(val minPercent: Int = 20) : Filter {
            override val kind: Int = 4
        }

        /**
         * Filter: caller-supplied predicate evaluated host-side, once per
         * candidate, per request. Return `true` to keep the candidate
         * eligible, `false` to drop it. Matches the "Custom Define" entry
         * in the file.txt routing-conditions list.
         *
         * The callback is invoked synchronously on the request thread —
         * keep it fast and side-effect-free.
         *
         * @property name        Short label for logs.
         * @property description Human-readable purpose for the filter.
         * @property check       Lambda `(modelId) -> Boolean` deciding
         *                       eligibility for the given candidate.
         */
        class CustomDefine(
            val name: String,
            val description: String,
            val check: (modelId: String) -> Boolean,
        ) : Filter {
            override val kind: Int = 5
        }

        /**
         * Cascade: when the primary backend's confidence signal falls
         * below [threshold] (or the primary errors out), the router
         * invokes the secondary candidate. The primary result is
         * discarded when the secondary succeeds.
         *
         * @property threshold Confidence value `[0..1]` below which the
         *                     cascade fires.
         */
        class Confidence(val threshold: Float) : Cascade {
            override val kind: Int = 1
        }

        /**
         * Prefer the local (offline) candidate when both candidates pass
         * the filter phase.
         */
        val PreferLocalFirst: Rank = Rank.PreferLocalFirst

        /**
         * Prefer the online (cloud) candidate when both candidates pass
         * the filter phase.
         */
        val PreferOnlineFirst: Rank = Rank.PreferOnlineFirst
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
     *     RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.Confidence(0.6f))
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
     *         cascadeConditions = RACRouter.RoutingPolicy.Confidence(0.6f)
     *         rankSort = RACRouter.RoutingPolicy.PreferLocalFirst
     *     }
     *
     * Spelling ("Advance", "cascadeConditions", "rankSort") preserved from
     * thoughts/file.txt.
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

    // ----------------------------------------------------------------------
    // LLM capability slot.
    // ----------------------------------------------------------------------

    /**
     * LLM-capability slot — owns one native router handle plus one
     * offline + one online native service handle.
     *
     * Lifecycle: created uninitialised by the parent [RACRouter]. Becomes
     * usable after [configureBackends] (called by the static factory) and
     * [addPair] (called by the app). [generate] dispatches a single
     * request; [close] releases all native resources.
     */
    class LlmRouter internal constructor() : Closeable {
        private var nativeHandle: Long = 0L
        private var offlineBackend: BackendId? = null
        private var onlineBackend: BackendId? = null
        private var offlineModel: RACModel? = null
        private var onlineModel: RACModel? = null
        private var offlineServiceHandle: Long = 0L
        private var onlineServiceHandle: Long = 0L
        private var pendingCustomFilters: List<RoutingPolicy.CustomDefine> = emptyList()

        init {
            RunAnywhereBridge.ensureNativeLibraryLoaded()
        }

        /**
         * Allocate the native router and remember the backend ids for
         * later service creation. Called by [Companion.llm].init(...).
         * Idempotent — calling twice frees the previous handle first.
         */
        internal fun configureBackends(offline: BackendId, online: BackendId) {
            close()
            this.offlineBackend = offline
            this.onlineBackend = online
            nativeHandle = RunAnywhereBridge.racLlmHybridRouterCreate()
            check(nativeHandle != 0L) { "racLlmHybridRouterCreate returned 0" }
        }

        /**
         * Bind concrete models to the offline + online sides and install
         * the routing policy.
         *
         * Order of [model1] and [model2] doesn't matter — the OFFLINE one
         * is bound to the offline slot, the ONLINE one to the online slot.
         * Calling twice replaces the previous bindings.
         *
         * @param model1       One of the two RACModel descriptors.
         * @param model2       The other; must have the opposite [ModelType].
         * @param routerPolicy [SimpleRouterPolicy] or [AdvanceRouterPolicy].
         * @throws IllegalArgumentException if [model1] and [model2] don't
         *                                  form one OFFLINE + one ONLINE pair.
         * @throws IllegalStateException if [configureBackends] hasn't run
         *                               or a native call fails.
         */
        fun addPair(model1: RACModel, model2: RACModel, routerPolicy: RouterPolicyBase) {
            check(nativeHandle != 0L) { "Call RACRouter.llm.init(...) first" }
            val offModel = if (model1.modelType == ModelType.OFFLINE) model1 else model2
            val onModel = if (model1.modelType == ModelType.ONLINE) model1 else model2
            require(offModel.modelType == ModelType.OFFLINE && onModel.modelType == ModelType.ONLINE) {
                "addPair requires one OFFLINE and one ONLINE model"
            }
            val offBackend = offlineBackend ?: error("init() not called")
            val onBackend = onlineBackend ?: error("init() not called")

            HybridRouterBridgeAdapter.destroyService(offBackend, offlineServiceHandle)
            HybridRouterBridgeAdapter.destroyService(onBackend, onlineServiceHandle)

            offlineServiceHandle = HybridRouterBridgeAdapter.createService(offBackend, offModel)
            onlineServiceHandle = HybridRouterBridgeAdapter.createService(onBackend, onModel)
            offlineModel = offModel
            onlineModel = onModel

            val rc1 = RunAnywhereBridge.racLlmHybridRouterSetOfflineService(
                routerHandle = nativeHandle,
                serviceHandle = offlineServiceHandle,
                descriptorProto = HybridRouterProto.descriptor(offModel, offBackend.kind),
            )
            check(rc1 == RunAnywhereBridge.RAC_SUCCESS) {
                "racLlmHybridRouterSetOfflineService rc=$rc1"
            }
            val rc2 = RunAnywhereBridge.racLlmHybridRouterSetOnlineService(
                routerHandle = nativeHandle,
                serviceHandle = onlineServiceHandle,
                descriptorProto = HybridRouterProto.descriptor(onModel, onBackend.kind),
            )
            check(rc2 == RunAnywhereBridge.RAC_SUCCESS) {
                "racLlmHybridRouterSetOnlineService rc=$rc2"
            }

            val packed = HybridRouterProto.policy(routerPolicy)
            pendingCustomFilters = packed.customFilters
            val rc3 = RunAnywhereBridge.racLlmHybridRouterSetPolicy(nativeHandle, packed.bytes)
            check(rc3 == RunAnywhereBridge.RAC_SUCCESS) {
                "racLlmHybridRouterSetPolicy rc=$rc3"
            }
        }

        /**
         * Run one text-generation request through the router. Returns the
         * winning backend's text and a [RoutedMetadata] describing the
         * dispatch decision.
         *
         * Host-side evaluation: any [RoutingPolicy.CustomDefine] filters
         * in the active policy are evaluated here against each candidate
         * id; ineligible sides are temporarily detached from the native
         * router for the duration of the call. Native filters (network,
         * privacy, etc.) run inside the C router.
         *
         * @param prompt User-supplied input passed verbatim to the backend.
         * @return [GenerateResult] containing the text + dispatch metadata.
         * @throws IllegalStateException if [configureBackends] or
         *                               [addPair] hasn't been called.
         */
        fun generate(prompt: String): GenerateResult {
            check(nativeHandle != 0L) { "Call init() then addPair() first" }
            val offModel = offlineModel ?: error("addPair() not called")
            val onModel = onlineModel ?: error("addPair() not called")
            val offBackend = offlineBackend ?: error("init() not called")
            val onBackend = onlineBackend ?: error("init() not called")

            val offlineEligible = pendingCustomFilters.all { it.check(offModel.id) }
            val onlineEligible = pendingCustomFilters.all { it.check(onModel.id) }

            if (!offlineEligible) {
                RunAnywhereBridge.racLlmHybridRouterSetOfflineService(nativeHandle, 0L, ByteArray(0))
            }
            if (!onlineEligible) {
                RunAnywhereBridge.racLlmHybridRouterSetOnlineService(nativeHandle, 0L, ByteArray(0))
            }

            try {
                val responseBytes = RunAnywhereBridge.racLlmHybridRouterGenerate(
                    routerHandle = nativeHandle,
                    requestProto = HybridRouterProto.request(prompt),
                ) ?: error("racLlmHybridRouterGenerate returned null envelope")
                return HybridRouterProto.parseResponse(responseBytes)
            } finally {
                if (!offlineEligible) {
                    RunAnywhereBridge.racLlmHybridRouterSetOfflineService(
                        routerHandle = nativeHandle,
                        serviceHandle = offlineServiceHandle,
                        descriptorProto = HybridRouterProto.descriptor(offModel, offBackend.kind),
                    )
                }
                if (!onlineEligible) {
                    RunAnywhereBridge.racLlmHybridRouterSetOnlineService(
                        routerHandle = nativeHandle,
                        serviceHandle = onlineServiceHandle,
                        descriptorProto = HybridRouterProto.descriptor(onModel, onBackend.kind),
                    )
                }
            }
        }

        /**
         * Streaming variant of [generate]. Emits [StreamEvent.Token] for
         * each generated token and exactly one terminal [StreamEvent.Done]
         * carrying the routing decision.
         *
         * Cancellation: when the collecting coroutine is cancelled (e.g.
         * structured-concurrency teardown or a manual `job.cancel()`),
         * `awaitClose` fires [RunAnywhereBridge.racLlmHybridRouterCancel]
         * which forwards to the active service's cancel op.
         *
         * @param prompt User-supplied input.
         */
        fun generateStream(prompt: String): Flow<StreamEvent> = callbackFlow {
            check(nativeHandle != 0L) { "Call init() then addPair() first" }
            check(offlineModel != null && onlineModel != null) { "addPair() not called" }

            val callback = object : HybridStreamCallback {
                override fun onToken(token: String): Boolean =
                    trySend(StreamEvent.Token(token)).isSuccess

                override fun onDone(rc: Int, responseProto: ByteArray) {
                    val routing = if (responseProto.isEmpty()) {
                        RoutedMetadata(chosenModelId = "", wasFallback = false, attemptCount = 0)
                    } else {
                        HybridRouterProto.parseResponse(responseProto).routing
                    }
                    trySend(StreamEvent.Done(routing))
                    close()
                }
            }

            // Native stream is blocking; run it off the collector's thread
            // so cancellation can still reach awaitClose. The launched job
            // returns when the native call returns; awaitClose has already
            // resolved by then if the collector cancelled.
            val handleAtLaunch = nativeHandle
            val job = launch(Dispatchers.IO) {
                RunAnywhereBridge.racLlmHybridRouterGenerateStream(
                    routerHandle = handleAtLaunch,
                    requestProto = HybridRouterProto.request(prompt),
                    callback = callback,
                )
            }

            awaitClose {
                RunAnywhereBridge.racLlmHybridRouterCancel(handleAtLaunch)
                job.cancel()
            }
        }.flowOn(Dispatchers.IO)

        /**
         * Tear down the native router and both per-side service handles.
         * Safe to call multiple times. Called from [RACRouter.close].
         */
        override fun close() {
            if (nativeHandle != 0L) {
                RunAnywhereBridge.racLlmHybridRouterSetOfflineService(nativeHandle, 0L, ByteArray(0))
                RunAnywhereBridge.racLlmHybridRouterSetOnlineService(nativeHandle, 0L, ByteArray(0))
                RunAnywhereBridge.racLlmHybridRouterDestroy(nativeHandle)
                nativeHandle = 0L
            }
            HybridRouterBridgeAdapter.destroyService(offlineBackend, offlineServiceHandle)
            offlineServiceHandle = 0L
            HybridRouterBridgeAdapter.destroyService(onlineBackend, onlineServiceHandle)
            onlineServiceHandle = 0L
            offlineBackend = null
            onlineBackend = null
            offlineModel = null
            onlineModel = null
            pendingCustomFilters = emptyList()
        }
    }

    // ----------------------------------------------------------------------
    // STT capability slot.
    // ----------------------------------------------------------------------

    /**
     * STT-capability slot — owns one native router handle plus one
     * offline + one online native `rac_stt_service_t` handle.
     *
     * Lifecycle mirrors [LlmRouter]: created uninitialised by the parent
     * [RACRouter]. Becomes usable after [configureBackends] (called by the
     * static factory) and [addPair] (called by the app). [transcribe]
     * dispatches a single request; [close] releases all native resources.
     */
    class SttRouter internal constructor() : Closeable {
        private var nativeHandle: Long = 0L
        private var offlineBackend: BackendId? = null
        private var onlineBackend: BackendId? = null
        private var offlineModel: RACModel? = null
        private var onlineModel: RACModel? = null
        private var offlineServiceHandle: Long = 0L
        private var onlineServiceHandle: Long = 0L
        private var pendingCustomFilters: List<RoutingPolicy.CustomDefine> = emptyList()

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
         * the routing policy. Same offline/online contract as
         * [LlmRouter.addPair].
         */
        fun addPair(model1: RACModel, model2: RACModel, routerPolicy: RouterPolicyBase) {
            check(nativeHandle != 0L) { "Call RACRouter.stt.init(...) first" }
            val offModel = if (model1.modelType == ModelType.OFFLINE) model1 else model2
            val onModel = if (model1.modelType == ModelType.ONLINE) model1 else model2
            require(offModel.modelType == ModelType.OFFLINE && onModel.modelType == ModelType.ONLINE) {
                "addPair requires one OFFLINE and one ONLINE model"
            }
            val offBackend = offlineBackend ?: error("init() not called")
            val onBackend = onlineBackend ?: error("init() not called")

            HybridRouterBridgeAdapter.destroyService(offBackend, offlineServiceHandle)
            HybridRouterBridgeAdapter.destroyService(onBackend, onlineServiceHandle)

            offlineServiceHandle = HybridRouterBridgeAdapter.createService(offBackend, offModel)
            onlineServiceHandle = HybridRouterBridgeAdapter.createService(onBackend, onModel)
            offlineModel = offModel
            onlineModel = onModel

            val rc1 = RunAnywhereBridge.racSttHybridRouterSetOfflineService(
                routerHandle = nativeHandle,
                serviceHandle = offlineServiceHandle,
                descriptorProto = HybridRouterProto.descriptor(offModel, offBackend.kind),
            )
            check(rc1 == RunAnywhereBridge.RAC_SUCCESS) {
                "racSttHybridRouterSetOfflineService rc=$rc1"
            }
            val rc2 = RunAnywhereBridge.racSttHybridRouterSetOnlineService(
                routerHandle = nativeHandle,
                serviceHandle = onlineServiceHandle,
                descriptorProto = HybridRouterProto.descriptor(onModel, onBackend.kind),
            )
            check(rc2 == RunAnywhereBridge.RAC_SUCCESS) {
                "racSttHybridRouterSetOnlineService rc=$rc2"
            }

            val packed = HybridRouterProto.policy(routerPolicy)
            pendingCustomFilters = packed.customFilters
            val rc3 = RunAnywhereBridge.racSttHybridRouterSetPolicy(nativeHandle, packed.bytes)
            check(rc3 == RunAnywhereBridge.RAC_SUCCESS) {
                "racSttHybridRouterSetPolicy rc=$rc3"
            }
        }

        /**
         * Run one transcribe request through the router.
         *
         * @param audioBytes  File-encoded audio (wav/mp3/flac/...) OR raw
         *                    PCM bytes. Each engine decodes per its own
         *                    expectations: Sarvam sends the bytes as a
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
            val offModel = offlineModel ?: error("addPair() not called")
            val onModel = onlineModel ?: error("addPair() not called")
            val offBackend = offlineBackend ?: error("init() not called")
            val onBackend = onlineBackend ?: error("init() not called")

            val offlineEligible = pendingCustomFilters.all { it.check(offModel.id) }
            val onlineEligible = pendingCustomFilters.all { it.check(onModel.id) }

            if (!offlineEligible) {
                RunAnywhereBridge.racSttHybridRouterSetOfflineService(nativeHandle, 0L, ByteArray(0))
            }
            if (!onlineEligible) {
                RunAnywhereBridge.racSttHybridRouterSetOnlineService(nativeHandle, 0L, ByteArray(0))
            }

            try {
                val responseBytes = RunAnywhereBridge.racSttHybridRouterTranscribe(
                    routerHandle = nativeHandle,
                    requestProto = HybridSttRouterProto.request(
                        audioBytes = audioBytes,
                        language = language,
                        sampleRate = sampleRate,
                        audioFormat = audioFormat,
                    ),
                ) ?: error("racSttHybridRouterTranscribe returned null envelope")
                return HybridSttRouterProto.parseResponse(responseBytes)
            } finally {
                if (!offlineEligible) {
                    RunAnywhereBridge.racSttHybridRouterSetOfflineService(
                        routerHandle = nativeHandle,
                        serviceHandle = offlineServiceHandle,
                        descriptorProto = HybridRouterProto.descriptor(offModel, offBackend.kind),
                    )
                }
                if (!onlineEligible) {
                    RunAnywhereBridge.racSttHybridRouterSetOnlineService(
                        routerHandle = nativeHandle,
                        serviceHandle = onlineServiceHandle,
                        descriptorProto = HybridRouterProto.descriptor(onModel, onBackend.kind),
                    )
                }
            }
        }

        /**
         * Tear down the native router and both per-side service handles.
         * Safe to call multiple times. Called from [RACRouter.close].
         */
        override fun close() {
            if (nativeHandle != 0L) {
                RunAnywhereBridge.racSttHybridRouterSetOfflineService(nativeHandle, 0L, ByteArray(0))
                RunAnywhereBridge.racSttHybridRouterSetOnlineService(nativeHandle, 0L, ByteArray(0))
                RunAnywhereBridge.racSttHybridRouterDestroy(nativeHandle)
                nativeHandle = 0L
            }
            HybridRouterBridgeAdapter.destroyService(offlineBackend, offlineServiceHandle)
            offlineServiceHandle = 0L
            HybridRouterBridgeAdapter.destroyService(onlineBackend, onlineServiceHandle)
            onlineServiceHandle = 0L
            offlineBackend = null
            onlineBackend = null
            offlineModel = null
            onlineModel = null
            pendingCustomFilters = emptyList()
        }
    }

    /**
     * Placeholder slot for capabilities not yet wired in this POC. Every
     * call surface throws [NotImplementedError] with the capability name —
     * the type exists so `router.tts` / `router.vlm` compile and the
     * multi-capability API surface stays consistent.
     *
     * @property name Capability label used in error messages.
     */
    class NotImplementedCapability internal constructor(private val name: String) {
        /** Throws — STT/TTS/VLM not wired. */
        fun addPair(model1: RACModel, model2: RACModel, routerPolicy: RouterPolicyBase): Nothing =
            throw NotImplementedError("router.$name is not wired in the POC (LLM only)")

        /** Throws — STT not wired. */
        fun transcribe(audio: Any): Nothing =
            throw NotImplementedError("router.$name.transcribe is not wired in the POC")

        /** Throws — TTS not wired. */
        fun synthesize(text: String): Nothing =
            throw NotImplementedError("router.$name.synthesize is not wired in the POC")

        /** Throws — VLM/etc. not wired. */
        fun generate(input: Any): Nothing =
            throw NotImplementedError("router.$name.generate is not wired in the POC")
    }

    // ----------------------------------------------------------------------
    // Static entry point: RACRouter.llm.init(backendOffline, backendOnline)
    // ----------------------------------------------------------------------

    companion object {
        /** Static factory for LLM-capability routers. See [LlmFactory.init]. */
        val llm: LlmFactory = LlmFactory()

        /** Static factory for STT-capability routers. See [SttFactory.init]. */
        val stt: SttFactory = SttFactory()

        /**
         * Register the host's device-state provider. Wires the Kotlin
         * object into the cross-SDK `rac_hybrid_device_state` vtable in
         * commons so the router's NETWORK / Battery filters see live
         * values on every generate() call.
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
     * Static factory that returns a fresh [RACRouter] with its LLM slot
     * wired to the requested backends. Equivalent to:
     *
     *     val router = RACRouter()
     *     router.llm.configureBackends(offline, online)
     *
     * The factory exists so the user-facing call reads
     * `RACRouter.llm.init(...)` exactly as in thoughts/file.txt.
     */
    class LlmFactory internal constructor() {
        /**
         * Allocate a new router and configure both LLM backends.
         *
         * @param backendOffline The on-device backend (e.g. [BACKEND.LLAMACPP.TEXTGEN]).
         * @param backendOnline  The cloud backend (e.g. [BACKEND.OPENROUTER.TEXTGEN]).
         * @return Ready-to-`addPair` router. Caller owns and must [close].
         */
        fun init(backendOffline: BackendId, backendOnline: BackendId): RACRouter {
            val router = RACRouter()
            router.llm.configureBackends(offline = backendOffline, online = backendOnline)
            return router
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
     * `RACRouter.stt.init(...)` exactly as in the LLM facade.
     */
    class SttFactory internal constructor() {
        /**
         * Allocate a new router and configure both STT backends.
         *
         * @param backendOffline The on-device backend (e.g. [BACKEND.SHERPA.STT]).
         * @param backendOnline  The cloud backend (e.g. [BACKEND.SARVAM.STT]).
         * @return Ready-to-`addPair` router. Caller owns and must [close].
         */
        fun init(backendOffline: BackendId, backendOnline: BackendId): RACRouter {
            val router = RACRouter()
            router.stt.configureBackends(offline = backendOffline, online = backendOnline)
            return router
        }
    }
}
