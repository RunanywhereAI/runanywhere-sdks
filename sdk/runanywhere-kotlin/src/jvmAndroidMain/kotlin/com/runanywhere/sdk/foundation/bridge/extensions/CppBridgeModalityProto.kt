/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.DiffusionCapabilities
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
import ai.runanywhere.proto.v1.LoRAAdapterInfo
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGStatistics
import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTPartialResult
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSVoiceInfo
import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStatistics
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMResult
import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import ai.runanywhere.proto.v1.VoiceAgentResult
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
    fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput {
        CppBridgeSTT.create()
        return decodeOrThrow(
            STTOutput.ADAPTER,
            RunAnywhereBridge.racSttComponentTranscribeProto(
                CppBridgeSTT.getHandle(),
                audioData,
                STTOptions.ADAPTER.encode(options),
            ),
            "racSttComponentTranscribeProto",
        )
    }

    fun transcribeStream(
        audioData: ByteArray,
        options: STTOptions,
        onPartial: (STTPartialResult) -> Boolean,
    ) {
        CppBridgeSTT.create()
        val rc =
            RunAnywhereBridge.racSttComponentTranscribeStreamProto(
                CppBridgeSTT.getHandle(),
                audioData,
                STTOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onPartial(STTPartialResult.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racSttComponentTranscribeStreamProto")
    }
}

object CppBridgeTTSProto {
    fun voices(): List<TTSVoiceInfo> {
        CppBridgeTTS.create()
        val voices = mutableListOf<TTSVoiceInfo>()
        val rc =
            RunAnywhereBridge.racTtsComponentListVoicesProto(
                CppBridgeTTS.getHandle(),
                NativeProtoProgressListener { bytes ->
                    voices += TTSVoiceInfo.ADAPTER.decode(bytes)
                    true
                },
            )
        checkRc(rc, "racTtsComponentListVoicesProto")
        return voices
    }

    fun synthesize(text: String, options: TTSOptions): TTSOutput {
        CppBridgeTTS.create()
        return decodeOrThrow(
            TTSOutput.ADAPTER,
            RunAnywhereBridge.racTtsComponentSynthesizeProto(
                CppBridgeTTS.getHandle(),
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
        CppBridgeTTS.create()
        val rc =
            RunAnywhereBridge.racTtsComponentSynthesizeStreamProto(
                CppBridgeTTS.getHandle(),
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
    fun configure(configuration: VADConfiguration) {
        CppBridgeVAD.create()
        val rc =
            RunAnywhereBridge.racVadComponentConfigureProto(
                CppBridgeVAD.getHandle(),
                VADConfiguration.ADAPTER.encode(configuration),
            )
        checkRc(rc, "racVadComponentConfigureProto")
    }

    fun process(samples: FloatArray, options: VADOptions = VADOptions()): VADResult {
        CppBridgeVAD.create()
        return decodeOrThrow(
            VADResult.ADAPTER,
            RunAnywhereBridge.racVadComponentProcessProto(
                CppBridgeVAD.getHandle(),
                samples,
                VADOptions.ADAPTER.encode(options),
            ),
            "racVadComponentProcessProto",
        )
    }

    fun statistics(): VADStatistics {
        CppBridgeVAD.create()
        return decodeOrThrow(
            VADStatistics.ADAPTER,
            RunAnywhereBridge.racVadComponentGetStatisticsProto(CppBridgeVAD.getHandle()),
            "racVadComponentGetStatisticsProto",
        )
    }
}

object CppBridgeVLMProto {
    @Volatile private var handle: Long = 0L
    @Volatile private var loadedModelId: String? = null

    @Synchronized
    fun loadModel(modelPath: String, mmprojPath: String?, modelId: String): Int {
        destroy()
        val serviceHandle = RunAnywhereBridge.racVlmCreate(modelId.ifBlank { modelPath })
        if (serviceHandle == 0L) return RunAnywhereBridge.RAC_ERROR_OPERATION_FAILED
        val rc = RunAnywhereBridge.racVlmInitialize(serviceHandle, modelPath, mmprojPath)
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            RunAnywhereBridge.racVlmDestroy(serviceHandle)
            return rc
        }
        handle = serviceHandle
        loadedModelId = modelId
        return rc
    }

    @Synchronized
    fun loadModelById(modelId: String): Int {
        destroy()
        val serviceHandle = RunAnywhereBridge.racVlmCreate(modelId)
        if (serviceHandle == 0L) return RunAnywhereBridge.RAC_ERROR_OPERATION_FAILED
        handle = serviceHandle
        loadedModelId = modelId
        return RunAnywhereBridge.RAC_SUCCESS
    }

    @Synchronized
    fun destroy() {
        if (handle != 0L) RunAnywhereBridge.racVlmDestroy(handle)
        handle = 0L
        loadedModelId = null
    }

    fun isLoaded(): Boolean = handle != 0L

    fun modelId(): String? = loadedModelId

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

    fun capabilities(): DiffusionCapabilities {
        if (handle == 0L) return DiffusionCapabilities()
        return DiffusionCapabilities()
    }

    private fun requireHandle(): Long =
        handle.takeIf { it != 0L } ?: throw SDKException.notInitialized("Diffusion service not loaded")
}

object CppBridgeLoraProto {
    private val loaded = ConcurrentHashMap<String, LoRAAdapterInfo>()

    fun load(config: LoRAAdapterConfig): LoRAAdapterInfo {
        CppBridgeLLM.create()
        val info =
            decodeOrThrow(
                LoRAAdapterInfo.ADAPTER,
                RunAnywhereBridge.racLoraLoadProto(
                    CppBridgeLLM.getHandle(),
                    LoRAAdapterConfig.ADAPTER.encode(config),
                ),
                "racLoraLoadProto",
            )
        loaded[info.adapter_id.ifBlank { info.adapter_path }] = info
        return info
    }

    fun remove(config: LoRAAdapterConfig): LoRAAdapterInfo {
        CppBridgeLLM.create()
        val info =
            decodeOrThrow(
                LoRAAdapterInfo.ADAPTER,
                RunAnywhereBridge.racLoraRemoveProto(
                    CppBridgeLLM.getHandle(),
                    LoRAAdapterConfig.ADAPTER.encode(config),
                ),
                "racLoraRemoveProto",
            )
        loaded.remove(info.adapter_id.ifBlank { info.adapter_path })
        return info
    }

    fun clear(): LoRAAdapterInfo {
        CppBridgeLLM.create()
        val info =
            decodeOrThrow(
                LoRAAdapterInfo.ADAPTER,
                RunAnywhereBridge.racLoraClearProto(CppBridgeLLM.getHandle()),
                "racLoraClearProto",
            )
        loaded.clear()
        return info
    }

    fun getLoaded(): List<LoRAAdapterInfo> = loaded.values.toList()

    fun compatibility(config: LoRAAdapterConfig): LoraCompatibilityResult {
        CppBridgeLLM.create()
        return decodeOrThrow(
            LoraCompatibilityResult.ADAPTER,
            RunAnywhereBridge.racLoraCompatibilityProto(
                CppBridgeLLM.getHandle(),
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

    fun processVoiceTurn(handle: Long, audioData: ByteArray): VoiceAgentResult =
        decodeOrThrow(
            VoiceAgentResult.ADAPTER,
            RunAnywhereBridge.racVoiceAgentProcessVoiceTurnProto(handle, audioData),
            "racVoiceAgentProcessVoiceTurnProto",
        )
}
