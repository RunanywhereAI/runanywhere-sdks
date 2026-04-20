// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Legacy-compat shims — keep the legacy RunAnywhere.chat / .generate /
// .transcribe / .synthesize / .initialize top-level surface compiling.
// Sample apps migrating from sdk/legacy/kotlin to sdk/kotlin should
// mostly only need to update imports (package is unchanged).

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

// --- Option / result types matching legacy shapes --------------------------

data class LLMGenerationOptions(
    val maxTokens: Int = 512,
    val temperature: Float = 0.8f,
    val topP: Float = 1.0f,
    val stopSequences: List<String> = emptyList(),
    val streamingEnabled: Boolean = false,
    val systemPrompt: String? = null,
)

data class LLMGenerationResult(
    val text: String,
    val tokensUsed: Int = 0,
    val modelUsed: String = "",
    val latencyMs: Long = 0,
    val tokensPerSecond: Double = 0.0,
)

data class LLMStreamingResult(val stream: Flow<String>)

data class STTOptions(val language: String = "en", val enablePartials: Boolean = true)
data class STTOutput(val text: String, val isFinal: Boolean = true,
                     val confidence: Float = 1.0f)

data class TTSOptions(val voice: String = "default", val speakingRate: Float = 1.0f)
data class TTSResult(val pcm: FloatArray, val sampleRateHz: Int) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is TTSResult) return false
        return sampleRateHz == other.sampleRateHz && pcm.contentEquals(other.pcm)
    }
    override fun hashCode(): Int = 31 * sampleRateHz + pcm.contentHashCode()
}

typealias SDKEnvironment = SDKState.Environment

// --- Implicit-session registry ---------------------------------------------

internal object LegacySessionRegistry {
    var currentLLM: LLMSession? = null
    var currentLLMChat: ChatSession? = null
    var currentSTT: STTSession? = null
    var currentTTS: TTSSession? = null
    var currentModelId: String = ""
    var currentModelPath: String = ""
    val registeredTools = mutableListOf<ToolDefinition>()
    val toolExecutors = mutableMapOf<String, suspend (Map<String, Any?>) -> String>()
}

// --- Top-level RunAnywhere surface -----------------------------------------
//
// Legacy sample apps call `RunAnywhere.chat(...)`, `RunAnywhere.generate(...)`,
// etc. `RunAnywhere` is already an `object` defined in RunAnywhere.kt; these
// are extension functions on that object (Kotlin doesn't allow re-opening an
// object, so we use top-level funcs namespaced via JvmName).

@JvmName("runAnywhereInitialize")
fun RunAnywhere.initialize(
    apiKey: String,
    baseURL: String = "",
    environment: SDKState.Environment = SDKState.Environment.PRODUCTION,
    deviceId: String = "",
    logLevel: SDKState.LogLevel = SDKState.LogLevel.INFO,
) = SDKState.initialize(apiKey, environment, baseURL, deviceId, logLevel)

val RunAnywhere.isSDKInitialized: Boolean get() = SDKState.isInitialized
val RunAnywhere.isActive: Boolean         get() = SDKState.isInitialized
val RunAnywhere.version: String           get() = "2.0.0"
val RunAnywhere.currentEnvironment: SDKState.Environment?
    get() = if (SDKState.isInitialized) SDKState.environment else null

fun RunAnywhere.shutdown() = SDKState.reset()

// --- LLM -------------------------------------------------------------------

fun RunAnywhere.loadModel(modelId: String, modelPath: String,
                          format: ModelFormat = ModelFormat.GGUF) {
    val session = LLMSession(modelId, modelPath, format)
    LegacySessionRegistry.currentLLM = session
    LegacySessionRegistry.currentLLMChat = null
    LegacySessionRegistry.currentModelId = modelId
    LegacySessionRegistry.currentModelPath = modelPath
}

fun RunAnywhere.unloadModel() {
    LegacySessionRegistry.currentLLM?.close()
    LegacySessionRegistry.currentLLMChat?.close()
    LegacySessionRegistry.currentLLM = null
    LegacySessionRegistry.currentLLMChat = null
    LegacySessionRegistry.currentModelId = ""
    LegacySessionRegistry.currentModelPath = ""
}

fun RunAnywhere.getCurrentModelId(): String = LegacySessionRegistry.currentModelId

suspend fun RunAnywhere.chat(
    prompt: String,
    options: LLMGenerationOptions = LLMGenerationOptions(),
): String {
    val chat = ensureChatSession(options.systemPrompt)
    return chat.generateText(listOf(ChatMessage.user(prompt)))
}

suspend fun RunAnywhere.generate(
    prompt: String,
    options: LLMGenerationOptions = LLMGenerationOptions(),
): LLMGenerationResult {
    val llm = requireLLM()
    val start = System.currentTimeMillis()
    val buf = StringBuilder()
    var tokens = 0
    llm.generate(prompt).collect { t ->
        if (t.kind == TokenKind.ANSWER) buf.append(t.text)
        tokens++
    }
    val elapsed = System.currentTimeMillis() - start
    val tps = if (elapsed > 0) tokens / (elapsed / 1000.0) else 0.0
    return LLMGenerationResult(
        text = buf.toString(),
        tokensUsed = tokens,
        modelUsed = LegacySessionRegistry.currentModelId,
        latencyMs = elapsed,
        tokensPerSecond = tps)
}

fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions = LLMGenerationOptions(),
): LLMStreamingResult {
    val llm = requireLLM()
    val textFlow: Flow<String> = llm.generate(prompt).let { tokenFlow ->
        tokenFlow.map { it.text }
    }
    return LLMStreamingResult(textFlow)
}

// --- STT -------------------------------------------------------------------

fun RunAnywhere.loadSTT(modelId: String, modelPath: String,
                        format: ModelFormat = ModelFormat.WHISPERKIT) {
    LegacySessionRegistry.currentSTT?.close()
    LegacySessionRegistry.currentSTT = STTSession(modelId, modelPath, format)
}

suspend fun RunAnywhere.transcribe(
    audioData: ByteArray,
    sampleRateHz: Int = 16000,
): String {
    val session = requireSTT()
    val samples = FloatArray(audioData.size / 2)
    for (i in samples.indices) {
        val lo = audioData[i * 2].toInt() and 0xFF
        val hi = audioData[i * 2 + 1].toInt()
        val s = (hi shl 8) or lo
        samples[i] = (s.toShort().toInt() / 32768.0f)
    }
    session.feedAudio(samples, sampleRateHz)
    session.flush()
    var text = ""
    session.transcripts.collect { chunk ->
        if (!chunk.isPartial) { text = chunk.text; return@collect }
    }
    return text
}

suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions = STTOptions(),
    sampleRateHz: Int = 16000,
): STTOutput = STTOutput(transcribe(audioData, sampleRateHz))

// --- TTS -------------------------------------------------------------------

fun RunAnywhere.loadTTS(modelId: String, modelPath: String,
                        format: ModelFormat = ModelFormat.ONNX) {
    LegacySessionRegistry.currentTTS?.close()
    LegacySessionRegistry.currentTTS = TTSSession(modelId, modelPath, format)
}

fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions = TTSOptions(),
): TTSResult {
    val session = requireTTS()
    val r = session.synthesize(text)
    return TTSResult(r.pcm, r.sampleRateHz)
}

// --- Tool calling ----------------------------------------------------------

fun RunAnywhere.registerTool(
    definition: ToolDefinition,
    executor: suspend (Map<String, Any?>) -> String,
) {
    LegacySessionRegistry.registeredTools.add(definition)
    LegacySessionRegistry.toolExecutors[definition.name] = executor
}

suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    options: LLMGenerationOptions = LLMGenerationOptions(),
): LLMGenerationResult {
    require(LegacySessionRegistry.currentModelId.isNotEmpty()) {
        "no model loaded — call RunAnywhere.loadModel(...) first"
    }
    val agent = ToolCallingAgent(
        modelId = LegacySessionRegistry.currentModelId,
        modelPath = LegacySessionRegistry.currentModelPath,
        tools = LegacySessionRegistry.registeredTools,
        systemPrompt = options.systemPrompt ?: "")
    var remaining = 4
    var reply = agent.send(prompt)
    while (remaining > 0) {
        when (reply) {
            is ToolCallingAgent.Reply.Assistant ->
                return LLMGenerationResult(
                    text = reply.text,
                    modelUsed = LegacySessionRegistry.currentModelId)
            is ToolCallingAgent.Reply.ToolCalls -> {
                val results = reply.calls.map { call ->
                    val exec = LegacySessionRegistry.toolExecutors[call.name]
                    call.name to (exec?.invoke(call.arguments) ?: "error")
                }
                reply = agent.continueAfter(results)
                remaining--
            }
        }
    }
    throw RunAnywhereException(-1, "tool-calling agent loop exceeded")
}

// --- Helpers ---------------------------------------------------------------

private fun requireLLM(): LLMSession =
    LegacySessionRegistry.currentLLM
        ?: throw RunAnywhereException(RunAnywhereException.BACKEND_UNAVAILABLE,
            "no LLM loaded — call RunAnywhere.loadModel first")

private fun requireSTT(): STTSession =
    LegacySessionRegistry.currentSTT
        ?: throw RunAnywhereException(RunAnywhereException.BACKEND_UNAVAILABLE,
            "no STT loaded — call RunAnywhere.loadSTT first")

private fun requireTTS(): TTSSession =
    LegacySessionRegistry.currentTTS
        ?: throw RunAnywhereException(RunAnywhereException.BACKEND_UNAVAILABLE,
            "no TTS loaded — call RunAnywhere.loadTTS first")

private fun ensureChatSession(systemPrompt: String?): ChatSession {
    LegacySessionRegistry.currentLLMChat?.let { return it }
    require(LegacySessionRegistry.currentModelId.isNotEmpty()) {
        "no model loaded — call RunAnywhere.loadModel first"
    }
    val chat = ChatSession(
        modelId = LegacySessionRegistry.currentModelId,
        modelPath = LegacySessionRegistry.currentModelPath,
        systemPrompt = systemPrompt ?: "")
    LegacySessionRegistry.currentLLMChat = chat
    return chat
}
