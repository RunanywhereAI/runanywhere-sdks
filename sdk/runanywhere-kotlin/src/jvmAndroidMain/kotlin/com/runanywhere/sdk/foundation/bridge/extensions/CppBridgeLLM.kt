/*
 * CppBridgeLLM.kt
 *
 * Per-domain split of CppBridgeModalityProto.kt — owns the LLM facade
 * over the rac_llm_*_proto C ABI. Mirrors Swift's
 * Foundation/Bridge/Extensions/CppBridge+LLM.swift one-to-one; logic is
 * copied verbatim, only the enclosing object name changes from
 * the legacy `Proto` suffix to the canonical `CppBridgeLLM` name.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.LLMGenerateRequest
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.SDKEvent
import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RALLMStreamEvent
import com.runanywhere.sdk.public.types.RASDKEvent
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
): RALLMGenerateRequest {
    val options = this ?: RALLMGenerationOptions()
    val schema = options.structured_output?.json_schema ?: options.json_schema.orEmpty()
    return RALLMGenerateRequest(
        prompt = prompt,
        max_tokens = options.max_tokens,
        temperature = options.temperature,
        top_p = options.top_p,
        top_k = options.top_k,
        system_prompt = options.system_prompt.orEmpty(),
        emit_thoughts = options.thinking_pattern != null,
        repetition_penalty = options.repetition_penalty,
        stop_sequences = options.stop_sequences,
        streaming_enabled = streaming || options.streaming_enabled,
        preferred_framework = options.preferred_framework.name,
        json_schema = schema,
        execution_target = options.execution_target?.name.orEmpty(),
    )
}

/**
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+LLM.swift`. Wraps `rac_llm_*_proto` C ABI.
 */
object CppBridgeLLM {
    @Volatile
    private var handle: Long = 0L

    private val lock = Any()

    /**
     * Get the current native handle, creating the component if needed.
     */
    @Throws(SDKException::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) create()
            if (handle == 0L) {
                throw SDKException.notInitialized("LLM component not created")
            }
            return handle
        }
    }

    /**
     * Idempotently create the LLM component. Returns 0 on success.
     */
    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) return 0
            if (!CppBridge.isNativeLibraryLoaded) {
                throw SDKException.notInitialized(
                    "Native library not available. Please ensure the native libraries are bundled in your APK.",
                )
            }
            val result =
                try {
                    RunAnywhereBridge.racLlmComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    throw SDKException.notInitialized(
                        "LLM native library not available: ${e.message}",
                    )
                }
            if (result == 0L) return -1
            handle = result
            return 0
        }
    }

    /**
     * Destroy the native component and release the handle.
     */
    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racLlmComponentDestroy(handle)
            handle = 0L
        }
    }

    fun generate(prompt: String, options: RALLMGenerationOptions?): RALLMGenerationResult {
        val request = options.toGenerateRequest(prompt, streaming = false)
        return decodeOrThrow(
            LLMGenerationResult.ADAPTER,
            RunAnywhereBridge.racLlmGenerateProto(LLMGenerateRequest.ADAPTER.encode(request)),
            "racLlmGenerateProto",
        )
    }

    fun generateStream(
        prompt: String,
        options: RALLMGenerationOptions?,
        onEvent: (RALLMStreamEvent) -> Boolean,
    ) {
        val request = options.toGenerateRequest(prompt, streaming = true)
        val rc =
            RunAnywhereBridge.racLlmGenerateStreamProto(
                LLMGenerateRequest.ADAPTER.encode(request),
                NativeProtoProgressListener { bytes ->
                    onEvent(LLMStreamEvent.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racLlmGenerateStreamProto")
    }

    fun cancel(): RASDKEvent? =
        RunAnywhereBridge.racLlmCancelProto()?.let(SDKEvent.ADAPTER::decode)
}
