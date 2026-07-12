/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeLLM.kt
 *
 * LLM component bridge — manages C++ LLM component lifecycle and the
 * proto-canonical `rac_llm_*_proto` C ABI.
 *
 * All generic scaffolding (handle creation, isLoaded, loadModel, unload,
 * destroy) lives in [ComponentActor]; this object only adds the
 * LLM-specific surfaces (`generate`, `generateStream`, `cancel`) on top.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+LLM.swift` (W3-1).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.LLMGenerateRequest
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.SDKEvent
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAChatMessage
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RALLMStreamEvent
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

private fun <M : Message<M, *>> decodeOrThrow(
    adapter: ProtoAdapter<M>,
    bytes: ByteArray?,
    operation: String,
): M {
    val payload = bytes ?: throw SDKException.operation("$operation returned null")
    return try {
        adapter.decode(payload)
    } catch (e: Exception) {
        throw SDKException.operation("Failed to decode $operation result: ${e.message}")
    }
}

private fun checkRc(rc: Int, operation: String) {
    if (rc != RunAnywhereBridge.RAC_SUCCESS) {
        throw SDKException.operation("$operation failed with rc=$rc")
    }
}

private fun RALLMGenerationOptions?.toGenerateRequest(
    prompt: String,
    streaming: Boolean,
    history: List<RAChatMessage> = emptyList(),
): RALLMGenerateRequest {
    val options = this ?: RALLMGenerationOptions()
    val requestOptions =
        options.copy(
            max_tokens = options.max_tokens.takeIf { it > 0 } ?: 100,
            temperature = options.temperature.takeIf { it > 0.0f } ?: 0.8f,
            top_p = options.top_p.takeIf { it > 0.0f } ?: 1.0f,
            repetition_penalty = options.repetition_penalty.takeIf { it > 0.0f } ?: 1.0f,
            streaming_enabled = streaming || options.streaming_enabled,
        )
    val schema = options.structured_output?.json_schema ?: options.json_schema.orEmpty()
    return RALLMGenerateRequest(
        prompt = prompt,
        max_tokens = requestOptions.max_tokens,
        temperature = requestOptions.temperature,
        top_p = requestOptions.top_p,
        top_k = requestOptions.top_k,
        system_prompt = options.system_prompt.orEmpty(),
        emit_thoughts = options.thinking_pattern != null,
        repetition_penalty = requestOptions.repetition_penalty,
        stop_sequences = options.stop_sequences,
        streaming_enabled = requestOptions.streaming_enabled,
        preferred_framework = options.preferred_framework.name,
        json_schema = schema,
        // Constrained-decoding grammar. Prefer the structured_output grammar, fall back to the top-level
        // field; without this the grammar set on the options was silently dropped on the public generate
        // path (C++ options_from_request already forwards it to rac_llm_options_t.grammar).
        grammar = options.structured_output?.grammar ?: options.grammar.orEmpty(),
        execution_target = options.execution_target?.name.orEmpty(),
        options = requestOptions,
        history = history,
    )
}

/**
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+LLM.swift`. Wraps
 * `rac_llm_*_proto` C ABI. Handle lifecycle lives in [inner].
 */
object CppBridgeLLM {
    /** Generic scaffold (handle / isLoaded / loadModel / unload / destroy). */
    internal val inner = ComponentActor(ComponentVTable.llm)

    // MARK: - Handle Management

    /** Get or create the LLM component handle. */
    suspend fun getHandle(): Long = inner.getHandle()

    // MARK: - State

    /** Whether a model is loaded. */
    val isLoaded: Boolean
        get() = inner.isLoaded

    /** Currently-loaded model id, or null. */
    val currentModelId: String?
        get() = inner.currentAssetId

    // MARK: - Model Lifecycle

    /** Load an LLM model. */
    suspend fun loadModel(modelPath: String, modelId: String, modelName: String) {
        inner.loadModel(path = modelPath, id = modelId, name = modelName)
    }

    /** Unload the current model. */
    suspend fun unload() {
        inner.unload()
    }

    // MARK: - Cleanup

    /** Destroy the component. */
    suspend fun destroy() {
        inner.destroy()
    }

    // MARK: - LLM-specific operations

    /**
     * Per-handle cancel of the in-flight generation on this component's
     * handle. Mirrors Swift's `CppBridge.LLM.cancel()`
     * (`rac_llm_component_cancel(handle)`). No-op if the handle is not
     * created. Use [cancelProto] for the lifecycle-aware public cancel path.
     */
    suspend fun cancel() {
        val handle = inner.existingHandle()
        if (handle == 0L) return
        RunAnywhereBridge.racLlmComponentCancel(handle)
    }

    /**
     * Lifecycle-aware cancel of the lifecycle-loaded generation. Mirrors
     * Swift's `LLMGeneratedProtoABI.cancelProto()` (`rac_llm_cancel_proto`),
     * which the public `cancelGeneration()` path drives. Returns the emitted
     * cancellation [SDKEvent], or null when no generation was in flight.
     */
    suspend fun cancelProto(): SDKEvent? =
        RunAnywhereBridge.racLlmCancelProto()?.let(SDKEvent.ADAPTER::decode)

    /** One-shot generation. */
    suspend fun generate(
        prompt: String,
        options: RALLMGenerationOptions?,
        history: List<RAChatMessage> = emptyList(),
    ): RALLMGenerationResult {
        val request = options.toGenerateRequest(prompt, streaming = false, history = history)
        return generate(request)
    }

    /** One-shot generation through the generated request ABI. */
    suspend fun generate(request: RALLMGenerateRequest): RALLMGenerationResult {
        inner.getHandle()
        return decodeOrThrow(
            LLMGenerationResult.ADAPTER,
            RunAnywhereBridge.racLlmGenerateProto(LLMGenerateRequest.ADAPTER.encode(request)),
            "racLlmGenerateProto",
        )
    }

    /**
     * Streaming generation. Native emits canonical [LLMStreamEvent]
     * envelopes. Kotlin simply decodes and forwards.
     *
     * **Streaming model — divergence note (W3-7):**
     *
     * Kotlin uses the *single-call* streaming path
     * (`rac_llm_generate_stream_proto`), where the per-request listener
     * is passed alongside the request bytes. Each new call installs its
     * own callback; there is no per-handle `set/unset` lifecycle.
     *
     * Swift's `CppBridge.LLM.generateStream` follows the same shape:
     * it calls into the generated `ProtoStreamContext` single-call path
     * (`Sources/RunAnywhere/Generated/ModalityProtoABI+Generated.swift`)
     * rather than registering once via
     * `rac_llm_set_stream_proto_callback` / `rac_llm_unset_stream_proto_callback`.
     * Both SDKs keep a `LLMStreamAdapter` typealias around
     * ([com.runanywhere.sdk.adapters.LLMStreamAdapter] /
     * `Sources/RunAnywhere/Adapters/LLMStreamAdapter.swift`) as a
     * future-migration shape over the per-handle ABI, but neither wires
     * the public API to it today.
     *
     * The C ABI symbols `rac_llm_set_stream_proto_callback` /
     * `rac_llm_unset_stream_proto_callback` exist in
     * `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_stream.h`,
     * but the Kotlin JNI bridge in
     * [com.runanywhere.sdk.native.bridge.RunAnywhereBridge] intentionally
     * does **not** expose `racLlmSetStreamProtoCallback` /
     * `racLlmUnsetStreamProtoCallback`. Adding them is the prerequisite
     * for migrating callers to the fan-out [LLMStreamAdapter] from W2-4
     * (which already specializes the generic [HandleStreamAdapter] fan-out
     * for `RALLMStreamEvent` + the `is_final` terminal-event predicate).
     *
     * TODO(KOT-W3-7-FOLLOWUP): When the JNI thunks for
     * `racLlmSetStreamProtoCallback` / `racLlmUnsetStreamProtoCallback`
     * land, switch this method (and
     * [com.runanywhere.sdk.public.extensions.generateStream]) over to
     * `llmStreamAdapter(handle, register=..., unregister=...).stream()`
     * to gain multi-collector fan-out (same change Swift would make in
     * `RunAnywhere+TextGeneration.swift`).
     *
     * The current single-callback model is functionally complete: the
     * caller-supplied `onEvent` predicate stops streaming when it returns
     * `false` (typically on `event.is_final`), and the `callbackFlow`
     * wrapper in `RunAnywhereTextGeneration.jvmAndroid.kt` cancels the
     * driver coroutine + tears down via [cancel] on collector
     * cancellation. The only thing missing is multi-Flow-collector
     * fan-out, which is rare in practice for LLM streams.
     */
    suspend fun generateStream(
        prompt: String,
        options: RALLMGenerationOptions?,
        history: List<RAChatMessage> = emptyList(),
        onEvent: (RALLMStreamEvent) -> Boolean,
    ) {
        val request = options.toGenerateRequest(prompt, streaming = true, history = history)
        generateStream(request, onEvent)
    }

    /** Streaming generation through the generated request ABI. */
    suspend fun generateStream(
        request: RALLMGenerateRequest,
        onEvent: (RALLMStreamEvent) -> Boolean,
    ) {
        inner.getHandle()
        val rc =
            RunAnywhereBridge.racLlmGenerateStreamProto(
                LLMGenerateRequest.ADAPTER.encode(request),
                NativeProtoProgressListener { bytes ->
                    onEvent(LLMStreamEvent.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racLlmGenerateStreamProto")
    }
}
