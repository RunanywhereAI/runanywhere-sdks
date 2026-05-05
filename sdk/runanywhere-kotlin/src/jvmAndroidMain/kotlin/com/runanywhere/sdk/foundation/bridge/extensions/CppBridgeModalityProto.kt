/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.DiffusionConfig
import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionProgress
import ai.runanywhere.proto.v1.DiffusionResult
import ai.runanywhere.proto.v1.EmbeddingsRequest
import ai.runanywhere.proto.v1.EmbeddingsResult
import ai.runanywhere.proto.v1.LLMGenerateRequest
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.LoRAAdapterConfig
import ai.runanywhere.proto.v1.LoRAApplyRequest
import ai.runanywhere.proto.v1.LoRAApplyResult
import ai.runanywhere.proto.v1.LoRARemoveRequest
import ai.runanywhere.proto.v1.LoRAState
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedRequest
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedResult
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTStreamEvent
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSVoiceInfo
import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStatistics
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMLoadResolvedArtifactsRequest
import ai.runanywhere.proto.v1.VLMLoadResolvedArtifactsResponse
import ai.runanywhere.proto.v1.VLMResult
import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter
import java.util.concurrent.ConcurrentHashMap

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

private fun LLMGenerationOptions?.toGenerateRequest(
    prompt: String,
    streaming: Boolean,
): LLMGenerateRequest {
    val options = this ?: LLMGenerationOptions()
    val schema = options.structured_output?.json_schema ?: options.json_schema.orEmpty()
    return LLMGenerateRequest(
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

object CppBridgeLLMProto {
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

    fun generate(prompt: String, options: LLMGenerationOptions?): LLMGenerationResult {
        val request = options.toGenerateRequest(prompt, streaming = false)
        return decodeOrThrow(
            LLMGenerationResult.ADAPTER,
            RunAnywhereBridge.racLlmGenerateProto(LLMGenerateRequest.ADAPTER.encode(request)),
            "racLlmGenerateProto",
        )
    }

    fun generateStream(
        prompt: String,
        options: LLMGenerationOptions?,
        onEvent: (LLMStreamEvent) -> Boolean,
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

    fun cancel(): SDKEvent? =
        RunAnywhereBridge.racLlmCancelProto()?.let(SDKEvent.ADAPTER::decode)
}

object CppBridgeSTTProto {
    @Volatile
    private var handle: Long = 0L

    private val lock = Any()

    @Throws(SDKException::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) create()
            if (handle == 0L) {
                throw SDKException.notInitialized("STT component not created")
            }
            return handle
        }
    }

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
                    RunAnywhereBridge.racSttComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    throw SDKException.notInitialized(
                        "STT native library not available: ${e.message}",
                    )
                }
            if (result == 0L) return -1
            handle = result
            return 0
        }
    }

    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racSttComponentDestroy(handle)
            handle = 0L
        }
    }

    fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput {
        create()
        return decodeOrThrow(
            STTOutput.ADAPTER,
            RunAnywhereBridge.racSttComponentTranscribeProto(
                getHandle(),
                audioData,
                STTOptions.ADAPTER.encode(options),
            ),
            "racSttComponentTranscribeProto",
        )
    }

    fun transcribeStream(
        audioData: ByteArray,
        options: STTOptions,
        onEvent: (STTStreamEvent) -> Boolean,
    ) {
        create()
        // Native emits canonical STTStreamEvent envelopes (STARTED / PARTIAL /
        // FINAL / ERROR with monotonically-increasing seq and timestamp_us).
        // Kotlin simply decodes and forwards.
        val rc =
            RunAnywhereBridge.racSttComponentTranscribeStreamProto(
                getHandle(),
                audioData,
                STTOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onEvent(STTStreamEvent.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racSttComponentTranscribeStreamProto")
    }
}

object CppBridgeTTSProto {
    @Volatile
    private var handle: Long = 0L

    private val lock = Any()

    @Throws(SDKException::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) create()
            if (handle == 0L) {
                throw SDKException.notInitialized("TTS component not created")
            }
            return handle
        }
    }

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
                    RunAnywhereBridge.racTtsComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    throw SDKException.notInitialized(
                        "TTS native library not available: ${e.message}",
                    )
                }
            if (result == 0L) return -1
            handle = result
            return 0
        }
    }

    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racTtsComponentDestroy(handle)
            handle = 0L
        }
    }

    fun voices(): List<TTSVoiceInfo> {
        create()
        val voices = mutableListOf<TTSVoiceInfo>()
        val rc =
            RunAnywhereBridge.racTtsComponentListVoicesProto(
                getHandle(),
                NativeProtoProgressListener { bytes ->
                    voices += TTSVoiceInfo.ADAPTER.decode(bytes)
                    true
                },
            )
        checkRc(rc, "racTtsComponentListVoicesProto")
        return voices
    }

    fun synthesize(text: String, options: TTSOptions): TTSOutput {
        create()
        return decodeOrThrow(
            TTSOutput.ADAPTER,
            RunAnywhereBridge.racTtsComponentSynthesizeProto(
                getHandle(),
                text,
                TTSOptions.ADAPTER.encode(options),
            ),
            "racTtsComponentSynthesizeProto",
        )
    }

    fun synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: (TTSOutput) -> Boolean,
    ) {
        create()
        val rc =
            RunAnywhereBridge.racTtsComponentSynthesizeStreamProto(
                getHandle(),
                text,
                TTSOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onChunk(TTSOutput.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racTtsComponentSynthesizeStreamProto")
    }
}

object CppBridgeVADProto {
    @Volatile
    private var handle: Long = 0L

    private val lock = Any()

    /**
     * Whether the underlying native component has been created.
     * Replaces the legacy isReady/isLoaded — readiness should be queried
     * through `CppBridgeModelLifecycleProto.snapshot(SDK_COMPONENT_VAD)`.
     */
    val isReady: Boolean
        get() = handle != 0L

    @Throws(SDKException::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) create()
            if (handle == 0L) {
                throw SDKException.notInitialized("VAD component not created")
            }
            return handle
        }
    }

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
                    RunAnywhereBridge.racVadComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    throw SDKException.notInitialized(
                        "VAD native library not available: ${e.message}",
                    )
                }
            if (result == 0L) return -1
            handle = result
            return 0
        }
    }

    /**
     * Cancel the current detection. Native ABI is the source of truth;
     * the previous Kotlin-side `isCancelled` flag was deleted.
     */
    fun cancel() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racVadComponentCancel(handle)
        }
    }

    /**
     * Reset the VAD state for a new audio stream.
     */
    fun reset() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racVadComponentReset(handle)
        }
    }

    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racVadComponentDestroy(handle)
            handle = 0L
        }
    }

    fun configure(configuration: VADConfiguration) {
        create()
        val rc =
            RunAnywhereBridge.racVadComponentConfigureProto(
                getHandle(),
                VADConfiguration.ADAPTER.encode(configuration),
            )
        checkRc(rc, "racVadComponentConfigureProto")
    }

    fun process(samples: FloatArray, options: VADOptions = VADOptions()): VADResult {
        create()
        return decodeOrThrow(
            VADResult.ADAPTER,
            RunAnywhereBridge.racVadComponentProcessProto(
                getHandle(),
                samples,
                VADOptions.ADAPTER.encode(options),
            ),
            "racVadComponentProcessProto",
        )
    }

    fun statistics(): VADStatistics {
        create()
        return decodeOrThrow(
            VADStatistics.ADAPTER,
            RunAnywhereBridge.racVadComponentGetStatisticsProto(getHandle()),
            "racVadComponentGetStatisticsProto",
        )
    }
}

object CppBridgeVLMProto {
    @Volatile private var handle: Long = 0L

    @Synchronized
    fun loadResolvedArtifacts(
        modelId: String,
        primaryModelPath: String,
        visionProjectorPath: String,
    ): Int {
        destroy()
        val request =
            VLMLoadResolvedArtifactsRequest(
                model_id = modelId,
                primary_model_path = primaryModelPath,
                mmproj_path = visionProjectorPath.takeIf { it.isNotBlank() },
            )
        val response =
            decodeOrThrow(
                VLMLoadResolvedArtifactsResponse.ADAPTER,
                RunAnywhereBridge.racVlmComponentLoadResolvedArtifactsProto(
                    VLMLoadResolvedArtifactsRequest.ADAPTER.encode(request),
                ),
                "racVlmComponentLoadResolvedArtifactsProto",
            )
        if (response.result_code != RunAnywhereBridge.RAC_SUCCESS || response.handle == 0L) {
            return if (response.result_code != RunAnywhereBridge.RAC_SUCCESS) {
                response.result_code
            } else {
                RunAnywhereBridge.RAC_ERROR_OPERATION_FAILED
            }
        }
        handle = response.handle
        return RunAnywhereBridge.RAC_SUCCESS
    }

    @Synchronized
    fun destroy() {
        if (handle != 0L) RunAnywhereBridge.racVlmDestroy(handle)
        handle = 0L
    }

    fun isLoaded(): Boolean = handle != 0L

    fun cancel() {
        if (handle != 0L) RunAnywhereBridge.racVlmCancelProto(handle)
    }

    fun process(image: VLMImage, options: VLMGenerationOptions): VLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessProto(
                requireHandle(),
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
            ),
            "racVlmProcessProto",
        )

    fun processStream(
        image: VLMImage,
        options: VLMGenerationOptions,
        onEvent: (SDKEvent) -> Boolean,
    ): VLMResult =
        decodeOrThrow(
            VLMResult.ADAPTER,
            RunAnywhereBridge.racVlmProcessStreamProto(
                requireHandle(),
                VLMImage.ADAPTER.encode(image),
                VLMGenerationOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onEvent(SDKEvent.ADAPTER.decode(bytes))
                },
            ),
            "racVlmProcessStreamProto",
        )

    private fun requireHandle(): Long =
        handle.takeIf { it != 0L } ?: throw SDKException.notInitialized("VLM service not loaded")
}

object CppBridgeEmbeddingsProto {
    private val handles = ConcurrentHashMap<String, Long>()

    fun embed(request: EmbeddingsRequest, modelId: String): EmbeddingsResult {
        val handle =
            handles.computeIfAbsent(modelId) {
                RunAnywhereBridge.racEmbeddingsCreate(it).also { created ->
                    if (created == 0L) throw SDKException.operation("racEmbeddingsCreate returned 0")
                }
            }
        return decodeOrThrow(
            EmbeddingsResult.ADAPTER,
            RunAnywhereBridge.racEmbeddingsEmbedBatchProto(
                handle,
                EmbeddingsRequest.ADAPTER.encode(request),
            ),
            "racEmbeddingsEmbedBatchProto",
        )
    }
}

object CppBridgeRAGProto {
    @Volatile private var sessionHandle: Long = 0L

    @Synchronized
    fun create(config: RAGConfiguration) {
        destroy()
        val handle =
            RunAnywhereBridge.racRagSessionCreateProto(RAGConfiguration.ADAPTER.encode(config))
        if (handle == 0L) {
            throw SDKException.operation("racRagSessionCreateProto returned 0")
        }
        sessionHandle = handle
    }

    @Synchronized
    fun destroy() {
        if (sessionHandle != 0L) RunAnywhereBridge.racRagSessionDestroyProto(sessionHandle)
        sessionHandle = 0L
    }

    fun ingest(document: RAGDocument): RAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagIngestProto(
                requireSession(),
                RAGDocument.ADAPTER.encode(document),
            ),
            "racRagIngestProto",
        )

    fun query(options: RAGQueryOptions): RAGResult =
        decodeOrThrow(
            RAGResult.ADAPTER,
            RunAnywhereBridge.racRagQueryProto(
                requireSession(),
                RAGQueryOptions.ADAPTER.encode(options),
            ),
            "racRagQueryProto",
        )

    fun clear(): RAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagClearProto(requireSession()),
            "racRagClearProto",
        )

    fun stats(): RAGStatistics =
        decodeOrThrow(
            RAGStatistics.ADAPTER,
            RunAnywhereBridge.racRagStatsProto(requireSession()),
            "racRagStatsProto",
        )

    private fun requireSession(): Long =
        sessionHandle.takeIf { it != 0L } ?: throw SDKException.notInitialized("RAG session not created")
}

object CppBridgeDiffusionProto {
    @Volatile private var handle: Long = 0L

    @Volatile private var modelId: String? = null

    @Synchronized
    fun load(config: DiffusionConfig) {
        unload()
        val serviceHandle =
            RunAnywhereBridge.racDiffusionCreate(config.model_id.ifBlank { config.model_path })
        if (serviceHandle == 0L) {
            throw SDKException.operation("racDiffusionCreate returned 0")
        }
        if (config.model_path.isNotBlank()) {
            val rc = RunAnywhereBridge.racDiffusionInitialize(serviceHandle, config.model_path)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                RunAnywhereBridge.racDiffusionDestroy(serviceHandle)
                checkRc(rc, "racDiffusionInitialize")
            }
        }
        handle = serviceHandle
        modelId = config.model_id.ifBlank { config.model_path }
    }

    @Synchronized
    fun unload() {
        if (handle != 0L) RunAnywhereBridge.racDiffusionDestroy(handle)
        handle = 0L
        modelId = null
    }

    fun generate(prompt: String, options: DiffusionGenerationOptions?): DiffusionResult {
        val request = (options ?: DiffusionGenerationOptions()).copy(prompt = prompt)
        return decodeOrThrow(
            DiffusionResult.ADAPTER,
            RunAnywhereBridge.racDiffusionGenerateProto(
                requireHandle(),
                DiffusionGenerationOptions.ADAPTER.encode(request),
            ),
            "racDiffusionGenerateProto",
        )
    }

    fun generateWithProgress(
        prompt: String,
        options: DiffusionGenerationOptions?,
        onProgress: (DiffusionProgress) -> Boolean,
    ): DiffusionResult {
        val request = (options ?: DiffusionGenerationOptions()).copy(prompt = prompt)
        return decodeOrThrow(
            DiffusionResult.ADAPTER,
            RunAnywhereBridge.racDiffusionGenerateWithProgressProto(
                requireHandle(),
                DiffusionGenerationOptions.ADAPTER.encode(request),
                NativeProtoProgressListener { bytes ->
                    onProgress(DiffusionProgress.ADAPTER.decode(bytes))
                },
            ),
            "racDiffusionGenerateWithProgressProto",
        )
    }

    fun cancel() {
        checkRc(RunAnywhereBridge.racDiffusionCancelProto(requireHandle()), "racDiffusionCancelProto")
    }

    fun isLoaded(): Boolean = handle != 0L

    fun currentModelId(): String? = modelId

    private fun requireHandle(): Long =
        handle.takeIf { it != 0L } ?: throw SDKException.notInitialized("Diffusion service not loaded")
}

object CppBridgeLoraProto {
    private fun nativeCatalogUnavailable(
        operation: String,
        cause: UnsatisfiedLinkError,
    ): String = "$operation native JNI symbol is unavailable: ${cause.message.orEmpty()}"

    fun apply(request: LoRAApplyRequest): LoRAApplyResult {
        CppBridgeLLMProto.create()
        return decodeOrThrow(
            LoRAApplyResult.ADAPTER,
            RunAnywhereBridge.racLoraApplyProto(
                CppBridgeLLMProto.getHandle(),
                LoRAApplyRequest.ADAPTER.encode(request),
            ),
            "racLoraApplyProto",
        )
    }

    fun remove(request: LoRARemoveRequest): LoRAState {
        CppBridgeLLMProto.create()
        return decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraRemoveProto(
                CppBridgeLLMProto.getHandle(),
                LoRARemoveRequest.ADAPTER.encode(request),
            ),
            "racLoraRemoveProto",
        )
    }

    fun list(request: LoRAState): LoRAState {
        CppBridgeLLMProto.create()
        return decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraListProto(
                CppBridgeLLMProto.getHandle(),
                LoRAState.ADAPTER.encode(request),
            ),
            "racLoraListProto",
        )
    }

    fun state(request: LoRAState): LoRAState {
        CppBridgeLLMProto.create()
        return decodeOrThrow(
            LoRAState.ADAPTER,
            RunAnywhereBridge.racLoraStateProto(
                CppBridgeLLMProto.getHandle(),
                LoRAState.ADAPTER.encode(request),
            ),
            "racLoraStateProto",
        )
    }

    fun compatibility(config: LoRAAdapterConfig): LoraCompatibilityResult {
        CppBridgeLLMProto.create()
        return decodeOrThrow(
            LoraCompatibilityResult.ADAPTER,
            RunAnywhereBridge.racLoraCompatibilityProto(
                CppBridgeLLMProto.getHandle(),
                LoRAAdapterConfig.ADAPTER.encode(config),
            ),
            "racLoraCompatibilityProto",
        )
    }

    fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry =
        decodeOrThrow(
            LoraAdapterCatalogEntry.ADAPTER,
            RunAnywhereBridge.racLoraRegisterProto(LoraAdapterCatalogEntry.ADAPTER.encode(entry)),
            "racLoraRegisterProto",
        )

    fun listCatalog(request: LoraAdapterCatalogListRequest): LoraAdapterCatalogListResult =
        try {
            decodeOrThrow(
                LoraAdapterCatalogListResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogListProto(
                    LoraAdapterCatalogListRequest.ADAPTER.encode(request),
                ),
                "racLoraCatalogListProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterCatalogListResult(
                success = false,
                error_message = nativeCatalogUnavailable("racLoraCatalogListProto", e),
            )
        }

    fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult =
        try {
            decodeOrThrow(
                LoraAdapterCatalogListResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogQueryProto(
                    LoraAdapterCatalogQuery.ADAPTER.encode(query),
                ),
                "racLoraCatalogQueryProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterCatalogListResult(
                success = false,
                error_message = nativeCatalogUnavailable("racLoraCatalogQueryProto", e),
            )
        }

    fun getCatalogEntry(request: LoraAdapterCatalogGetRequest): LoraAdapterCatalogGetResult =
        try {
            decodeOrThrow(
                LoraAdapterCatalogGetResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogGetProto(
                    LoraAdapterCatalogGetRequest.ADAPTER.encode(request),
                ),
                "racLoraCatalogGetProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterCatalogGetResult(
                found = false,
                error_message = nativeCatalogUnavailable("racLoraCatalogGetProto", e),
            )
        }

    fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult =
        try {
            decodeOrThrow(
                LoraAdapterDownloadCompletedResult.ADAPTER,
                RunAnywhereBridge.racLoraCatalogMarkDownloadCompletedProto(
                    LoraAdapterDownloadCompletedRequest.ADAPTER.encode(request),
                ),
                "racLoraCatalogMarkDownloadCompletedProto",
            )
        } catch (e: UnsatisfiedLinkError) {
            LoraAdapterDownloadCompletedResult(
                success = false,
                persisted = false,
                error_message =
                    nativeCatalogUnavailable("racLoraCatalogMarkDownloadCompletedProto", e),
            )
        }
}

object CppBridgeVoiceAgentProto {
    fun initialize(handle: Long, config: VoiceAgentComposeConfig): VoiceAgentComponentStates =
        decodeOrThrow(
            VoiceAgentComponentStates.ADAPTER,
            RunAnywhereBridge.racVoiceAgentInitializeProto(
                handle,
                VoiceAgentComposeConfig.ADAPTER.encode(config),
            ),
            "racVoiceAgentInitializeProto",
        )

    fun states(handle: Long): VoiceAgentComponentStates =
        decodeOrThrow(
            VoiceAgentComponentStates.ADAPTER,
            RunAnywhereBridge.racVoiceAgentComponentStatesProto(handle),
            "racVoiceAgentComponentStatesProto",
        )
}
