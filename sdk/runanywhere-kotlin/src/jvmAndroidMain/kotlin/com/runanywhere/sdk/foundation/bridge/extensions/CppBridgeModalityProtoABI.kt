/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Documentation/contract for the modality-domain proto C ABI symbols the
 * Kotlin SDK depends on. Sister object to [CppBridgeNativeProtoABI].
 *
 * Mirrors iOS [CppBridge+ModalityProtoABI.swift]
 * (../../../../../../../../../../../../sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModalityProtoABI.swift).
 *
 * On Swift (Darwin), each proto symbol must be resolved at runtime via
 * `dlsym(RTLD_DEFAULT, ...)` because the SwiftPM-vended XCFramework links the
 * commons archive with optional symbols that may not be exported. The Swift
 * file pre-loads every symbol into a typed function pointer and asserts each
 * one is available before invoking.
 *
 * On Kotlin/JNI, the equivalent surface is reached through `external fun`
 * declarations on [com.runanywhere.sdk.native.bridge.RunAnywhereBridge].
 * Symbol resolution happens implicitly at link time when the JVM resolves
 * `Java_*_RunAnywhereBridge_*` symbols inside `librunanywhere_jni.so`. There
 * is no `dlsym` ceremony — if a JNI symbol is missing the JVM throws
 * `UnsatisfiedLinkError` on first invocation.
 *
 * This object therefore serves three purposes:
 * 1. Document the canonical list of `rac_*_proto` C symbols the SDK depends
 *    on, so reviewers can audit the JNI surface against the C++ headers.
 * 2. Provide a single [assertAvailable] method that callers can invoke to
 *    verify the native library is loaded before attempting any modality
 *    proto operation. The check is cheap: it queries the cached
 *    `nativeLibraryLoaded` flag on [RunAnywhereBridge] which is flipped by
 *    [com.runanywhere.sdk.native.bridge.RunAnywhereBridge.ensureNativeLibraryLoaded].
 * 3. Act as a stable anchor for kotlin.md inconsistency tracking — keeping
 *    the modality and native ABI contracts visible side by side with the
 *    Swift sources of truth.
 *
 * NOTE: This file documents *contract*. Callers should continue to invoke
 * the per-domain [CppBridgeLLM], [CppBridgeSTT], etc. wrappers for actual
 * proto operations. Nothing in this object dispatches inference work.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Catalog of `rac_*_proto` C ABI symbols required by the modality-domain
 * Kotlin bridges. Mirrors the private symbol-name constants in the Swift
 * `CppBridge+ModalityProtoABI.swift` file (`LLMGeneratedProtoABI`,
 * `STTGeneratedProtoABI`, `TTSGeneratedProtoABI`, `VADGeneratedProtoABI`,
 * `VADLifecycleProtoABI`, `VoiceAgentGeneratedProtoABI`,
 * `VLMGeneratedProtoABI`, `EmbeddingsGeneratedProtoABI`,
 * `RAGGeneratedProtoABI`, `LoRAGeneratedProtoABI`).
 *
 * Each Kotlin `external fun` listed under "JNI counterpart" on
 * [RunAnywhereBridge] eventually calls into the matching `rac_*` symbol from
 * `librac_commons.so`. If the C++ shared library is rebuilt without one of
 * these symbols (e.g. because a backend was disabled at compile time), the
 * JVM raises `UnsatisfiedLinkError` on first call and the SDK surfaces the
 * failure as an [SDKException].
 */
object CppBridgeModalityProtoABI {
    // ====================================================================
    // LLM (rac_llm_service.h)
    //   - rac_llm_generate_proto         → racLlmGenerateProto
    //   - rac_llm_generate_stream_proto  → racLlmGenerateStreamProto
    //   - rac_llm_cancel_proto           → racLlmCancelProto
    //   - rac_llm_apply_chat_template_proto → racLlmApplyChatTemplateProto
    // ====================================================================

    // ====================================================================
    // STT (rac_stt_component.h, rac_stt_service.h)
    //   - rac_stt_transcribe_lifecycle_proto         → racSttTranscribeLifecycleProto
    //   - rac_stt_transcribe_stream_lifecycle_proto  → racSttTranscribeStreamLifecycleProto
    //
    // Lifecycle-owned transcribe takes no handle parameter and resolves the
    // currently-loaded STT component from the commons lifecycle. See the
    // Swift comment block on STTGeneratedProtoABI for the actor-handle
    // separation bug that motivated the lifecycle surface.
    // ====================================================================

    // ====================================================================
    // TTS (rac_tts_component.h)
    //   - rac_tts_component_list_voices_proto         → racTtsListVoicesProto
    //   - rac_tts_synthesize_lifecycle_proto          → racTtsSynthesizeLifecycleProto
    //   - rac_tts_synthesize_stream_lifecycle_proto   → racTtsSynthesizeStreamLifecycleProto
    // ====================================================================

    // ====================================================================
    // VAD (rac_vad_component.h, rac_vad_stream.h)
    //   - rac_vad_component_configure_proto                 → racVadConfigureProto
    //   - rac_vad_component_process_proto                   → racVadProcessProto
    //   - rac_vad_component_get_statistics_proto            → racVadGetStatisticsProto
    //   - rac_vad_component_set_activity_proto_callback    → racVadSetActivityCallback
    //
    // Lifecycle-owned VAD operations (handle-less, route through commons
    // lifecycle — see SWIFT-VAD-001):
    //   - rac_vad_process_lifecycle_proto    → racVadProcessLifecycleProto
    //   - rac_vad_configure_lifecycle_proto  → racVadConfigureLifecycleProto
    //   - rac_vad_start_lifecycle_proto      → racVadStartLifecycleProto
    //   - rac_vad_stop_lifecycle_proto       → racVadStopLifecycleProto
    //   - rac_vad_reset_lifecycle_proto      → racVadResetLifecycleProto
    // ====================================================================

    // ====================================================================
    // VLM (rac_vlm_service.h)
    //   - rac_vlm_process_proto         → racVlmProcessProto
    //   - rac_vlm_process_stream_proto  → racVlmProcessStreamProto
    //   - rac_vlm_cancel_proto          → racVlmCancelProto
    // ====================================================================

    // ====================================================================
    // Voice Agent (rac_voice_agent.h)
    //   - rac_voice_agent_initialize_proto          → racVoiceAgentInitializeProto
    //   - rac_voice_agent_component_states_proto    → racVoiceAgentComponentStatesProto
    //   - rac_voice_agent_process_voice_turn_proto  → racVoiceAgentProcessVoiceTurnProto
    // ====================================================================

    // ====================================================================
    // Embeddings (rac_embeddings_service.h)
    //   - rac_embeddings_embed_batch_proto → racEmbeddingsEmbedBatchProto
    // ====================================================================

    // ====================================================================
    // RAG (rac_rag_pipeline.h)
    //   - rac_rag_session_create_proto  → racRagSessionCreateProto
    //   - rac_rag_session_destroy_proto → racRagSessionDestroyProto
    //   - rac_rag_ingest_proto          → racRagIngestProto
    //   - rac_rag_query_proto           → racRagQueryProto
    //   - rac_rag_clear_proto           → racRagClearProto
    //   - rac_rag_stats_proto           → racRagStatsProto
    // ====================================================================

    // ====================================================================
    // Tool Calling (rac_tool_calling.h)
    //   - rac_tool_calling_session_create_proto            → racToolCallingSessionCreateProto
    //   - rac_tool_calling_session_step_with_result_proto  → racToolCallingSessionStepWithResultProto
    //   - rac_tool_calling_session_destroy_proto           → racToolCallingSessionDestroyProto
    // ====================================================================

    // ====================================================================
    // Structured Output (rac_structured_output.h)
    //   - racStructuredOutputGenerateProto / matching `rac_structured_output_*_proto`
    //     C symbols, see the C++ header for the canonical list.
    // ====================================================================

    // ====================================================================
    // LoRA (rac_lora_service.h)
    //   Registry-handle-bound symbols:
    //   - rac_lora_register_proto                       → racLoraRegisterProto
    //   - rac_lora_catalog_list_proto                   → racLoraCatalogListProto
    //   - rac_lora_catalog_query_proto                  → racLoraCatalogQueryProto
    //   - rac_lora_catalog_get_proto                    → racLoraCatalogGetProto
    //   - rac_lora_catalog_mark_download_completed_proto → racLoraCatalogMarkDownloadCompletedProto
    //
    //   LLM-handle-bound symbols:
    //   - rac_lora_compatibility_proto → racLoraCompatibilityProto
    //   - rac_lora_apply_proto         → racLoraApplyProto
    //   - rac_lora_remove_proto        → racLoraRemoveProto
    //   - rac_lora_list_proto          → racLoraListProto
    //   - rac_lora_state_proto         → racLoraStateProto
    // ====================================================================

    // ====================================================================
    // Diffusion (rac_diffusion_service.h)
    //   - rac_diffusion_generate_proto                → racDiffusionGenerateProto
    //   - rac_diffusion_generate_with_progress_proto  → racDiffusionGenerateWithProgressProto
    //   - rac_diffusion_cancel_proto                  → racDiffusionCancelProto
    // ====================================================================

    /**
     * Verifies the runanywhere_jni native library is loaded so that the
     * `external fun` declarations enumerated above can be safely invoked.
     *
     * Unlike the Swift counterpart in `NativeProtoABI.canReceiveProtoBuffer`,
     * this check does not actually resolve any `rac_*_proto` symbol — JNI
     * resolution happens lazily on first call and there is no equivalent of
     * `dlsym` here. This is purely a guard against calling proto wrappers
     * before [com.runanywhere.sdk.native.bridge.RunAnywhereBridge.ensureNativeLibraryLoaded]
     * has succeeded.
     *
     * @throws SDKException with category `not supported` if the native
     *   library has not been loaded.
     */
    fun assertAvailable() {
        if (!RunAnywhereBridge.isNativeLibraryLoaded()) {
            throw SDKException.operation(
                "Modality proto ABI not available: librunanywhere_jni.so is not loaded",
            )
        }
    }
}
