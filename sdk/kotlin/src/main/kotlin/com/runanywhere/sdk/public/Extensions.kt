// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// VLM / Diffusion / RAG / LoRA / Voice / Tools — RunAnywhere extension
// surface used by the Android sample app.

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

// MARK: - VLM ---------------------------------------------------------------

internal object VLMState { var modelId: String = "" }

val RunAnywhere.isVLMModelLoaded: Boolean get() = VLMState.modelId.isNotEmpty()
val RunAnywhere.currentVLMModelId: String? get() = VLMState.modelId.takeIf { it.isNotEmpty() }

fun RunAnywhere.loadVLMModel(modelId: String, modelPath: String) {
    VLMState.modelId = modelId
}

fun RunAnywhere.unloadVLMModel() { VLMState.modelId = "" }

fun RunAnywhere.processImage(image: VLMImage, prompt: String,
                               options: VLMGenerationOptions = VLMGenerationOptions()): String {
    val info = ModelCatalog.get(VLMState.modelId)
        ?: throw IllegalStateException("no VLM loaded")
    return VLMSession(info.id, info.localPath ?: "").process(image, prompt, options)
}

fun RunAnywhere.processImageStream(image: VLMImage, prompt: String,
                                      options: VLMGenerationOptions = VLMGenerationOptions()): Flow<String> {
    val info = ModelCatalog.get(VLMState.modelId)
        ?: return flow { throw IllegalStateException("no VLM loaded") }
    return VLMSession(info.id, info.localPath ?: "").processStream(image, prompt, options)
}

fun RunAnywhere.cancelVLMGeneration() {}

// MARK: - Diffusion ---------------------------------------------------------

internal object DiffusionState { var modelId: String = "" }

val RunAnywhere.isDiffusionModelLoaded: Boolean get() = DiffusionState.modelId.isNotEmpty()
val RunAnywhere.currentDiffusionModelId: String? get() = DiffusionState.modelId.takeIf { it.isNotEmpty() }

fun RunAnywhere.loadDiffusionModel(modelId: String, modelPath: String,
                                       configuration: DiffusionConfiguration = DiffusionConfiguration()) {
    DiffusionState.modelId = modelId
}

fun RunAnywhere.unloadDiffusionModel() { DiffusionState.modelId = "" }

suspend fun RunAnywhere.generateImage(request: DiffusionRequest): DiffusionResult {
    val info = ModelCatalog.get(DiffusionState.modelId)
        ?: throw IllegalStateException("no diffusion model loaded")
    return DiffusionSession(info.id, info.localPath ?: "")
        .generate(request.prompt, request.options)
}

fun RunAnywhere.cancelImageGeneration() {}

// MARK: - LoRA --------------------------------------------------------------

fun RunAnywhere.loadLoraAdapter(config: LoRAAdapterConfig)         = ModelCatalog.setLoraLoaded(config)
fun RunAnywhere.removeLoraAdapter(id: String)                      = ModelCatalog.setLoraUnloaded(id)
fun RunAnywhere.clearLoraAdapters()                                = ModelCatalog.clearLora()
val RunAnywhere.allRegisteredLoraAdapters: List<LoRAAdapterConfig> get() = ModelCatalog.allRegisteredLora()
fun RunAnywhere.getLoadedLoraAdapters(): List<LoRAAdapterConfig>   = ModelCatalog.allRegisteredLora()
fun RunAnywhere.loraAdaptersForModel(id: String): List<LoRAAdapterConfig> = ModelCatalog.adaptersFor(id)
fun RunAnywhere.checkLoraCompatibility(adapterId: String, modelId: String) =
    if (loraAdaptersForModel(modelId).any { it.id == adapterId })
        LoraCompatibilityResult(true)
    else LoraCompatibilityResult(false, "adapter and model bases don't match")
fun RunAnywhere.loraAdapterLocalPath(id: String): String? =
    ModelCatalog.allRegisteredLora().firstOrNull { it.id == id }?.localPath
suspend fun RunAnywhere.downloadLoraAdapter(id: String): String =
    error("use a download manager to fetch LoRA adapters")
fun RunAnywhere.deleteDownloadedLoraAdapter(id: String) {}

// MARK: - RAG ---------------------------------------------------------------

fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration) {
    RAGRegistry.current = RAGPipeline(config)
}

fun RunAnywhere.ragIngest(text: String) {
    val p = RAGRegistry.current ?: error("call ragCreatePipeline first")
    p.ingest(text)
}

suspend fun RunAnywhere.ragQuery(question: String): RAGResult {
    val p = RAGRegistry.current ?: error("call ragCreatePipeline first")
    return p.query(question)
}

fun RunAnywhere.ragDestroyPipeline() { RAGRegistry.current = null }

// MARK: - Voice agent -------------------------------------------------------

fun RunAnywhere.startVoiceSession(config: VoiceSessionConfig = VoiceSessionConfig.DEFAULT): Flow<VoiceSessionEvent> = flow {
    // JNI build wires this to ra_pipeline_*; pure-Kotlin path emits nothing.
}

fun RunAnywhere.stopVoiceSession() {}

fun RunAnywhere.processVoice(pcm: FloatArray, sampleRateHz: Int) {}

fun RunAnywhere.voiceAgentComponentStates(): Map<String, ComponentLoadState> = mapOf(
    "stt" to ComponentLoadState.UNLOADED,
    "llm" to ComponentLoadState.UNLOADED,
    "tts" to ComponentLoadState.UNLOADED,
)

fun RunAnywhere.getVoiceAgentComponentStates(): Map<String, ComponentLoadState> =
    voiceAgentComponentStates()

val RunAnywhere.isVoiceAgentReady: Boolean get() = false

// MARK: - LLM model lifecycle (modelId-based shorthand) --------------------

internal object LLMModelState { var id: String = "" }
internal object STTModelState { var id: String = "" }
internal object TTSVoiceState { var id: String = "" }
internal object VADModelState { var id: String = "" }

fun RunAnywhere.loadLLMModel(modelId: String) { LLMModelState.id = modelId }
fun RunAnywhere.unloadLLMModel() { LLMModelState.id = "" }
val RunAnywhere.currentLLMModel: ModelInfo? get() = ModelCatalog.get(LLMModelState.id)
val RunAnywhere.currentLLMModelId: String? get() = LLMModelState.id.takeIf { it.isNotEmpty() }
val RunAnywhere.isLLMModelLoaded: Boolean get() = LLMModelState.id.isNotEmpty()
fun RunAnywhere.isLLMModelLoadedSync(): Boolean = isLLMModelLoaded
fun RunAnywhere.cancelGeneration() {}
val RunAnywhere.supportsLLMStreaming: Boolean get() = true

fun RunAnywhere.loadSTTModel(modelId: String) { STTModelState.id = modelId }
fun RunAnywhere.loadSTTModel(modelId: String, category: ModelCategory) { STTModelState.id = modelId }
fun RunAnywhere.unloadSTTModel() { STTModelState.id = "" }
val RunAnywhere.currentSTTModel: ModelInfo? get() = ModelCatalog.get(STTModelState.id)
val RunAnywhere.currentSTTModelId: String? get() = STTModelState.id.takeIf { it.isNotEmpty() }
val RunAnywhere.isSTTModelLoaded: Boolean get() = STTModelState.id.isNotEmpty()
fun RunAnywhere.isSTTModelLoadedSync(): Boolean = isSTTModelLoaded

fun RunAnywhere.loadTTSVoice(voiceId: String) { TTSVoiceState.id = voiceId }
fun RunAnywhere.loadTTSVoice(voiceId: String, category: ModelCategory) { TTSVoiceState.id = voiceId }
fun RunAnywhere.loadTTSModel(voiceId: String) = loadTTSVoice(voiceId)
fun RunAnywhere.unloadTTSVoice() { TTSVoiceState.id = "" }
fun RunAnywhere.unloadTTSModel() { TTSVoiceState.id = "" }
val RunAnywhere.currentTTSVoiceId: String? get() = TTSVoiceState.id.takeIf { it.isNotEmpty() }
val RunAnywhere.isTTSVoiceLoaded: Boolean get() = TTSVoiceState.id.isNotEmpty()
fun RunAnywhere.isTTSVoiceLoadedSync(): Boolean = isTTSVoiceLoaded

fun RunAnywhere.loadVADModel(modelId: String) { VADModelState.id = modelId }
fun RunAnywhere.unloadVADModel() { VADModelState.id = "" }
val RunAnywhere.currentVADModel: ModelInfo? get() = ModelCatalog.get(VADModelState.id)
val RunAnywhere.isVADReady: Boolean get() = VADModelState.id.isNotEmpty()
suspend fun RunAnywhere.initializeVAD(modelId: String) { VADModelState.id = modelId }
fun RunAnywhere.detectSpeech(pcm: FloatArray, sampleRateHz: Int): Boolean = false

// MARK: - Tool registry helpers --------------------------------------------

fun RunAnywhere.clearTools() {
    SessionRegistry.registeredTools.clear()
    SessionRegistry.toolExecutors.clear()
}

fun RunAnywhere.getRegisteredTools(): List<ToolDefinition> =
    SessionRegistry.registeredTools.toList()

object RunAnywhereTools {
    fun registerTool(definition: ToolDefinition,
                     executor: suspend (Map<String, Any?>) -> String) =
        RunAnywhere.registerTool(definition, executor)
    fun getRegisteredTools(): List<ToolDefinition> =
        SessionRegistry.registeredTools.toList()
}

object RunAnywhereToolCalling {
    fun getRegisteredTools(): List<ToolDefinition> =
        SessionRegistry.registeredTools.toList()
    suspend fun generateWithTools(prompt: String,
                                    options: ToolCallingOptions = ToolCallingOptions()): LLMGenerationResult =
        LLMGenerationResult(text = "(stub) $prompt")
}

object RunAnywhereRAG {
    fun ragCreatePipeline(config: RAGConfiguration) = RunAnywhere.ragCreatePipeline(config)
    fun ragIngest(text: String) = RunAnywhere.ragIngest(text)
    suspend fun ragQuery(question: String) = RunAnywhere.ragQuery(question)
    fun ragDestroyPipeline() = RunAnywhere.ragDestroyPipeline()
}

// Tool calling option shape used by the Android ChatViewModel.
data class ToolCallingOptions(
    val autoExecute: Boolean = true,
    val maxToolCalls: Int = 4,
    val maxTokens: Int = 1024,
    val temperature: Float = 0.7f,
    val systemPrompt: String? = null,
    val format: ToolCallFormat = ToolCallFormat.DEFAULT,
)

enum class ToolCallFormat { DEFAULT, LFM2 }

enum class ToolParameterType { STRING, NUMBER, INTEGER, BOOLEAN, OBJECT, ARRAY }

sealed class ToolValue {
    data class Str(val value: String): ToolValue()
    data class Num(val value: Double): ToolValue()
    data class Int_(val value: Long): ToolValue()
    data class Bool(val value: Boolean): ToolValue()
    object Null : ToolValue()
}
