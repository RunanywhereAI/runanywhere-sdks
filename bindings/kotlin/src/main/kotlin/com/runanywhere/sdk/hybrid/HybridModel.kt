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
 * Plugin-registry engine name for a hybrid candidate — a free-form string
 * (`rac_plugin_find_for_engine`'s lookup key), not a closed enum.
 * `HybridBackendKind` (the enum) is deleted outright (idl/hybrid_router.proto):
 * `HybridModelDescriptor.backend` + `.provider` were replaced by a single
 * `engine: string` field so a new backend name is not a proto change. Mirrors
 * Swift's `HybridBackendKind = String` typealias.
 */
typealias HybridBackendKind = String

/** Well-known engine names, mirroring Swift's `HybridBackendKind` statics. */
object HybridBackendKinds {
    const val UNSPECIFIED: HybridBackendKind = ""
    const val LLAMACPP: HybridBackendKind = "llamacpp"

    /** On-device speech (sherpa-onnx Whisper / Zipformer / Paraformer). */
    const val SHERPA: HybridBackendKind = "sherpa"

    /**
     * Generic cloud speech (the "cloud" engine). The concrete HTTP provider
     * (Sarvam first) is resolved by the cloud engine from its own config,
     * not carried on the descriptor any more.
     */
    const val CLOUD: HybridBackendKind = "cloud"
}

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
 * @property isLocal   Whether this side of the pair runs on-device (true) or in the cloud (false).
 *                     Marshalled into the descriptor's `is_on_device` field
 *                     (idl/hybrid_router.proto renamed `is_local` -> `is_on_device`).
 * @property backend   Plugin-registry engine name (`rac_plugin_find_for_engine`'s
 *                     lookup key): "sherpa", "llamacpp", "onnx", "qhexrt", "mlx",
 *                     "cloud", or any name passed to `registerCloudProvider`.
 *                     Empty lets the registry pick by priority.
 */
data class HybridModel(
    val id: String,
    val isLocal: Boolean,
    val backend: HybridBackendKind,
) {
    companion object {
        /** Convenience for an on-device sherpa model. */
        @JvmStatic
        fun offlineSherpa(id: String): HybridModel =
            HybridModel(
                id = id,
                isLocal = true,
                backend = HybridBackendKinds.SHERPA,
            )

        /**
         * Convenience for a cloud model (registered via [Cloud.register]).
         * The concrete HTTP provider (Sarvam first) is resolved by the cloud
         * engine from the config the caller registered -- it no longer rides
         * on this descriptor (idl/hybrid_router.proto deleted `provider`
         * outright).
         */
        @JvmStatic
        fun onlineCloud(id: String): HybridModel =
            HybridModel(
                id = id,
                isLocal = false,
                backend = HybridBackendKinds.CLOUD,
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
