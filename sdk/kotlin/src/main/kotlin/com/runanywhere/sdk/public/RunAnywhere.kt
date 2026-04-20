// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — public Kotlin entry point.

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * The 20-line developer API:
 *
 *     val session = RunAnywhere.solution(VoiceAgentConfig())
 *     session.run().collect { event -> when (event) {
 *         is VoiceEvent.UserSaid     -> transcript.addUser(event.text)
 *         is VoiceEvent.AssistantTok -> transcript.appendToken(event.text)
 *         is VoiceEvent.Audio        -> player.enqueue(event.pcm)
 *         is VoiceEvent.Interrupted  -> player.flush()
 *         is VoiceEvent.Error        -> onError(event)
 *     }}
 */
object RunAnywhere {

    /** Open a VoiceAgent or RAG session from an ergonomic config. */
    @JvmStatic
    fun solution(config: SolutionConfig): VoiceSession =
        VoiceSession.create(config)

    /**
     * Dynamic plugin load — Android/JVM only. Resolves the plugin's ABI
     * version and capabilities before returning. On iOS (compiled
     * statically), this is a no-op that returns false.
     */
    @JvmStatic
    fun loadPlugin(libPath: String): Boolean {
        return if (NativeLibrary.isLoaded) {
            PluginBridge.loadPlugin(libPath)
        } else {
            false
        }
    }

    /** Count of currently-registered engine plugins. */
    @JvmStatic
    val registeredPluginCount: Int
        get() = if (NativeLibrary.isLoaded) PluginBridge.pluginCount() else 0
}

/** Internal bridge to the ra_registry_* JNI shims. */
internal object PluginBridge {
    external fun loadPlugin(path: String): Boolean
    external fun pluginCount(): Int
}

sealed interface SolutionConfig
data class VoiceAgentConfig(
    val llm: String           = "qwen3-4b",
    val stt: String           = "whisper-base",
    val tts: String           = "kokoro",
    val vad: String           = "silero-v5",
    val sampleRateHz: Int     = 16000,
    val chunkMs: Int          = 20,
    val enableBargeIn: Boolean = true,
    val emitPartials: Boolean = true,
    val emitThoughts: Boolean = false,
    val systemPrompt: String  = "",
    val maxContextTokens: Int = 4096,
    val temperature: Float    = 0.7f,
) : SolutionConfig

data class RAGConfig(
    val embedModel: String       = "bge-small-en-v1.5",
    val rerankModel: String      = "bge-reranker-v2-m3",
    val llm: String              = "qwen3-4b",
    val vectorStorePath: String  = "",
    val retrieveK: Int           = 24,
    val rerankTop: Int           = 6,
) : SolutionConfig

data class WakeWordConfig(
    val model: String       = "kws-zipformer-gigaspeech",
    val keyword: String     = "hey mycroft",
    val threshold: Float    = 0.5f,
    val preRollMs: Int      = 250,
) : SolutionConfig
