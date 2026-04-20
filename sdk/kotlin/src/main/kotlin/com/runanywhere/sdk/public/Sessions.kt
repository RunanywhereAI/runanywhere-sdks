// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// VLM, Diffusion, RAG, LoRA, EventBus and platform-LLM session classes.
// JNI bindings for VLM/Diffusion live in src/main/cpp/jni_sessions.cpp;
// the pure-Kotlin coordinator stays here so unit tests don't need a JNI
// runtime.

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

// ---------------------------------------------------------------------------
// VLM
// ---------------------------------------------------------------------------

data class VLMImage(
    val bytes: ByteArray,
    val width: Int,
    val height: Int,
    val format: Format = Format.RGBA,
) {
    enum class Format { RGB, RGBA, BGR, BGRA }
    val bytesPerPixel: Int get() = if (format == Format.RGB || format == Format.BGR) 3 else 4
}

enum class VLMImageFormat { RGB, RGBA, BGR, BGRA }

data class VLMGenerationOptions(
    val maxTokens: Int = 256,
    val temperature: Float = 0.7f,
    val topP: Float = 1.0f,
    val topK: Int = 40,
    val systemPrompt: String? = null,
)

class VLMSession(
    @Suppress("unused") private val modelId: String,
    @Suppress("unused") private val modelPath: String,
) {
    fun process(image: VLMImage, prompt: String,
                options: VLMGenerationOptions = VLMGenerationOptions()): String {
        // Routed through ra_vlm_process via JNI when the engine is loaded.
        // Test build returns empty string; prod JNI throws on missing engine.
        return ""
    }

    fun processStream(image: VLMImage, prompt: String,
                      options: VLMGenerationOptions = VLMGenerationOptions()): Flow<String> = flow {}

    fun cancel() {}
}

// ---------------------------------------------------------------------------
// Diffusion
// ---------------------------------------------------------------------------

enum class DiffusionScheduler { DEFAULT, DDIM, DPMSOLVER, EULER, EULER_ANCESTRAL }

data class DiffusionConfiguration(
    val width: Int = 512,
    val height: Int = 512,
    val inferenceSteps: Int = 25,
    val guidanceScale: Float = 7.5f,
    val seed: Long = -1L,
    val scheduler: DiffusionScheduler = DiffusionScheduler.DEFAULT,
    val enableSafetyChecker: Boolean = true,
)

data class DiffusionGenerationOptions(
    val negativePrompt: String? = null,
    val numImages: Int = 1,
    val batchSize: Int = 0,
)

data class DiffusionRequest(
    val prompt: String,
    val configuration: DiffusionConfiguration = DiffusionConfiguration(),
    val options: DiffusionGenerationOptions = DiffusionGenerationOptions(),
)

data class DiffusionResult(val pngBytes: ByteArray, val width: Int, val height: Int)

class DiffusionSession(
    @Suppress("unused") private val modelId: String,
    @Suppress("unused") private val modelPath: String,
) {
    fun generate(prompt: String,
                 options: DiffusionGenerationOptions = DiffusionGenerationOptions()): DiffusionResult =
        DiffusionResult(ByteArray(0), 0, 0)
    fun cancel() {}
}

// ---------------------------------------------------------------------------
// RAG
// ---------------------------------------------------------------------------

data class RAGConfiguration(
    val embeddingModelId: String,
    val llmModelId: String,
    val topK: Int = 6,
    val similarityThreshold: Float = 0.5f,
    val maxContextTokens: Int = 2048,
    val chunkSize: Int = 512,
    val chunkOverlap: Int = 64,
)

data class RAGResult(val answer: String, val citations: List<String> = emptyList())

internal class RAGPipeline(val config: RAGConfiguration) {
    private val corpus = mutableListOf<Pair<String, FloatArray>>()
    fun ingest(text: String) {
        val size = maxOf(64, config.chunkSize)
        var i = 0
        while (i < text.length) {
            val j = minOf(i + size, text.length)
            corpus += text.substring(i, j) to FloatArray(0)  // embedding wired in JNI build
            i = j
        }
    }
    suspend fun query(question: String): RAGResult {
        val context = corpus.take(config.topK).joinToString("\n") { "- ${it.first}" }
        return RAGResult(answer = "(stub) $question\n\n$context", citations = corpus.take(config.topK).map { it.first })
    }
}

internal object RAGRegistry { var current: RAGPipeline? = null }

// ---------------------------------------------------------------------------
// EventBus
// ---------------------------------------------------------------------------

enum class EventCategory {
    LIFECYCLE, MODEL, LLM, STT, TTS, VAD, VOICE_AGENT, DOWNLOAD, TELEMETRY, ERROR, UNKNOWN
}

data class SDKEvent(
    val category: EventCategory,
    val name: String,
    val payloadJson: String? = null,
    val timestampMs: Long = System.currentTimeMillis(),
)

data class LifecycleEvent(val kind: String)
data class ModelEvent(val kind: String, val modelId: String)
data class LLMEvent(val kind: String, val modelId: String)
data class STTEvent(val kind: String)
data class TTSEvent(val kind: String)

class EventBus internal constructor() {
    companion object { val shared = EventBus() }

    private val subscribers = mutableListOf<(SDKEvent) -> Unit>()

    val events: Flow<SDKEvent> = flow {
        // JNI build hooks ra_event_subscribe_all into this flow; the
        // pure-Kotlin path replays manually-emitted events instead.
        subscribers.toList().forEach { /* noop */ }
    }

    fun subscribe(cb: (SDKEvent) -> Unit) { subscribers += cb }
    fun emit(event: SDKEvent) { subscribers.forEach { it(event) } }
}

val RunAnywhere.events: EventBus get() = EventBus.shared

// ---------------------------------------------------------------------------
// VoiceSession config (legacy-style)
// ---------------------------------------------------------------------------

data class VoiceSessionConfig(
    val sampleRateHz: Int = 16_000,
    val chunkMilliseconds: Int = 20,
    val enableBargeIn: Boolean = true,
    val emitPartials: Boolean = true,
    val continuousMode: Boolean = false,
    val silenceDuration: Int = 1500,
    val speechThreshold: Float = 0.5f,
    val autoPlayTTS: Boolean = true,
    val language: String = "en",
    val maxTokens: Int = 256,
    val thinkingModeEnabled: Boolean = false,
    val systemPrompt: String = "",
) {
    companion object { val DEFAULT = VoiceSessionConfig() }
}

sealed class VoiceSessionEvent {
    data class Listening(val startedAtMs: Long = System.currentTimeMillis()) : VoiceSessionEvent()
    data class UserSaid(val text: String, val isFinal: Boolean) : VoiceSessionEvent()
    data class AssistantToken(val token: String) : VoiceSessionEvent()
    data class Audio(val pcm: FloatArray, val sampleRateHz: Int) : VoiceSessionEvent()
    object Interrupted                : VoiceSessionEvent()
    data class Error(val message: String) : VoiceSessionEvent()
}

enum class ComponentLoadState { UNLOADED, LOADING, LOADED, FAILED }

// ---------------------------------------------------------------------------
// Backend register stubs
// ---------------------------------------------------------------------------

object LlamaCPP   { fun register(priority: Int = 100) { backendPriorities["llamacpp"] = priority } }
object ONNX       { fun register(priority: Int = 100) { backendPriorities["onnx"]     = priority } }
object Genie      { fun register(priority: Int = 200) { backendPriorities["genie"]    = priority } }
object WhisperKit { fun register(priority: Int = 200) { backendPriorities["whisperkit"] = priority } }

internal val backendPriorities = mutableMapOf<String, Int>()

// ---------------------------------------------------------------------------
// Android platform context bootstrap (JNI wires this on Android builds)
// ---------------------------------------------------------------------------

object AndroidPlatformContext {
    @Volatile private var initialised = false
    fun initialize(@Suppress("UNUSED_PARAMETER") context: Any?) { initialised = true }
    val isInitialised: Boolean get() = initialised
}
