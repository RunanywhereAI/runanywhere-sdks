/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public model / backend identity + transcribe-result types for the STT
 * hybrid router. Mirrors Swift's HybridModel.swift and the wire enums in
 * idl/hybrid_router.proto.
 */

package com.runanywhere.sdk.hybrid

/**
 * Backend identity for a hybrid candidate. The generated proto enum
 * (`HybridBackendKind` from hybrid_router.proto / `rac_hybrid_backend_kind_t`)
 * is the source of truth; the typealias keeps the wire numbering in one place
 * (mirrors Swift's `HybridBackendKind = RAHybridBackendKind`).
 */
typealias HybridBackendKind = ai.runanywhere.proto.v1.HybridBackendKind

/**
 * Whether a candidate runs on-device or in the cloud. Backed by the generated
 * `HybridModelType` (wire values match `rac_hybrid_model_type_t`).
 */
typealias HybridModelType = ai.runanywhere.proto.v1.HybridModelType

/**
 * STT options carried through the router (mirror of the C `rac_stt_options_t`
 * knobs the router forwards). All optional with backend-default behaviour.
 * Backed by the generated `HybridSttTranscribeOptions` (`language`,
 * `sample_rate`, `audio_format`).
 */
typealias HybridTranscribeOptions = ai.runanywhere.proto.v1.HybridSttTranscribeOptions

/**
 * Metadata describing the routing decision behind a [HybridTranscribeResult].
 * Always populated, including on cascade/fallback scenarios. Backed by the
 * generated `HybridRoutedMetadata` (`chosen_model_id`, `was_fallback`,
 * `attempt_count`, `primary_error_code`, `primary_error_message`,
 * `confidence`, `primary_confidence`).
 */
typealias HybridRoutedMetadata = ai.runanywhere.proto.v1.HybridRoutedMetadata

/**
 * One side of the hybrid pair. `id` is the resolution key:
 *   - offline (sherpa) — the model id the C model registry resolves so the
 *     engine can load the model files.
 *   - online (cloud) — the registry id registered via
 *     [Cloud.register], which supplies the provider, model string +
 *     credentials.
 *
 * @property id        Registry identifier shared with the SDK.
 * @property modelType Whether this side of the pair runs on-device or in the cloud.
 * @property backend   Structured backend identity used to pin the engine the
 *                     router creates the service through.
 * @property provider  Concrete cloud provider when [backend] is
 *                     `HYBRID_BACKEND_CLOUD` (e.g. "sarvam"). Empty for
 *                     non-cloud backends; marshalled into the descriptor's
 *                     `provider` field so the cloud engine selects the HTTP
 *                     backend.
 */
data class HybridModel(
    val id: String,
    val modelType: HybridModelType,
    val backend: HybridBackendKind,
    val provider: String = "",
) {
    companion object {
        /** Convenience for an on-device sherpa model. */
        @JvmStatic
        fun offlineSherpa(id: String): HybridModel =
            HybridModel(
                id = id,
                modelType = HybridModelType.HYBRID_MODEL_TYPE_OFFLINE,
                backend = HybridBackendKind.HYBRID_BACKEND_SHERPA,
            )

        /**
         * Convenience for a cloud model (registered via [Cloud.register]).
         * [provider] defaults to [Cloud.DEFAULT_PROVIDER] ("sarvam") and is
         * carried in the descriptor so the cloud engine picks the HTTP backend.
         */
        @JvmStatic
        @JvmOverloads
        fun onlineCloud(
            id: String,
            provider: String = Cloud.DEFAULT_PROVIDER,
        ): HybridModel =
            HybridModel(
                id = id,
                modelType = HybridModelType.HYBRID_MODEL_TYPE_ONLINE,
                backend = HybridBackendKind.HYBRID_BACKEND_CLOUD,
                provider = provider,
            )
    }
}

/**
 * One transcribe call's outcome through the hybrid STT router.
 *
 * @property text             Transcript text from the chosen backend.
 * @property detectedLanguage BCP-47 language code reported by the backend
 *                            (empty when none surfaced).
 * @property routing          Which side ran, whether it was a fallback, and
 *                            why the primary failed (proto-typed).
 */
data class HybridTranscribeResult(
    val text: String,
    val detectedLanguage: String,
    val routing: HybridRoutedMetadata,
)
