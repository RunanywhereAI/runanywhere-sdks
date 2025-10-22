package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.events.SDKVoiceEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.public.RunAnywhereSDK
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
// STTOptions, STTResult, and WordTimestamp are defined in this package (ExtensionTypes.kt)

/**
 * Voice/STT extension APIs for RunAnywhereSDK
 * Matches iOS RunAnywhere+Voice.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Voice/RunAnywhere+Voice.swift
 *
 * Note: Phase 2 implementation - provides voice transcription capabilities
 * STTOptions, STTResult, and WordTimestamp are defined in ExtensionTypes.kt
 */

private val voiceLogger = SDKLogger("VoiceAPI")

/**
 * Voice conversation session
 * Matches iOS VoiceConversation class
 */
interface VoiceConversation {
    val sessionId: String
    suspend fun processVoiceTurn(audioData: ByteArray): String
    suspend fun end()
}

/**
 * Voice conversation configuration
 * Matches iOS VoiceConversationConfig struct
 */
data class VoiceConversationConfig(
    val sttModelId: String = "whisper-base",
    val llmModelId: String = "llama-2-7b-chat",
    val language: String = "en",
    val enableVAD: Boolean = true
)

/**
 * Transcribe audio data
 * Matches iOS transcribe(audio:options:) method
 *
 * @param audio Audio data to transcribe
 * @param options Transcription options
 * @return STT result with transcribed text
 */
suspend fun RunAnywhereSDK.transcribe(audio: ByteArray, options: STTOptions = STTOptions()): STTResult {
    voiceLogger.debug("Transcribing audio: ${audio.size} bytes, language=${options.language}")

    // Publish event
    events.publish(SDKVoiceEvent.TranscriptionStarted)

    val result = try {
        // Get or create STT component
        val sttComponent = ServiceContainer.shared.sttComponent

        // Ensure component is initialized
        if (!sttComponent.isReady) {
            voiceLogger.debug("STT component not ready, initializing...")
            sttComponent.initialize()
        }

        // Transcribe using the component
        val sttOutput = sttComponent.transcribe(audio)

        // Publish completion event
        events.publish(SDKVoiceEvent.TranscriptionFinal(sttOutput.text))

        // Convert STTOutput to STTResult
        STTResult(
            text = sttOutput.text,
            confidence = sttOutput.confidence,
            language = options.language,
            duration = sttOutput.metadata.audioLength,
            wordTimestamps = if (options.enableWordTimestamps) {
                sttOutput.wordTimestamps?.map { wt ->
                    WordTimestamp(
                        word = wt.word,
                        startTime = wt.startTime,
                        endTime = wt.endTime,
                        confidence = wt.confidence
                    )
                }
            } else {
                null
            },
            speakerSegments = null,
            processingTime = sttOutput.metadata.processingTime,
            modelUsed = sttOutput.metadata.modelId
        )
    } catch (e: Exception) {
        voiceLogger.error("Transcription failed: ${e.message}")
        events.publish(SDKVoiceEvent.PipelineError(e))
        throw e
    }

    voiceLogger.info("Transcription completed: ${result.text.length} characters")
    return result
}

/**
 * Create a voice conversation session
 * Matches iOS createVoiceConversation(config:) method
 *
 * @param config Voice conversation configuration
 * @return Voice conversation session
 */
suspend fun RunAnywhereSDK.createVoiceConversation(
    config: VoiceConversationConfig = VoiceConversationConfig()
): VoiceConversation {
    voiceLogger.debug("Creating voice conversation: stt=${config.sttModelId}, llm=${config.llmModelId}")

    // Publish event
    events.publish(SDKVoiceEvent.PipelineStarted)

    return try {
        // Create conversation implementation
        VoiceConversationImpl(this, config)
    } catch (e: Exception) {
        voiceLogger.error("Failed to create voice conversation: ${e.message}")
        events.publish(SDKVoiceEvent.PipelineError(e))
        throw e
    }
}

/**
 * Process a voice turn (audio input → text response)
 * Matches iOS processVoiceTurn(audio:) method
 *
 * @param audio Audio data from user
 * @return Generated text response
 */
suspend fun RunAnywhereSDK.processVoiceTurn(audio: ByteArray): String {
    voiceLogger.debug("Processing voice turn: ${audio.size} bytes")

    // Publish event
    events.publish(SDKVoiceEvent.PipelineStarted)

    return try {
        // Step 1: Transcribe audio
        voiceLogger.debug("Step 1: Transcribing audio")
        events.publish(SDKVoiceEvent.SttProcessing)

        val transcriptionResult = transcribe(audio, STTOptions())
        val userText = transcriptionResult.text

        voiceLogger.info("Transcribed: $userText")

        // Step 2: Generate response
        voiceLogger.debug("Step 2: Generating response")
        events.publish(SDKVoiceEvent.LlmProcessing)

        val response = this.chat(userText)

        // Publish completion
        events.publish(SDKVoiceEvent.ResponseGenerated(response))
        events.publish(SDKVoiceEvent.PipelineCompleted)

        voiceLogger.info("Voice turn completed: ${response.length} characters")
        response
    } catch (e: Exception) {
        voiceLogger.error("Voice turn processing failed: ${e.message}")
        events.publish(SDKVoiceEvent.PipelineError(e))
        throw e
    }
}

/**
 * Internal implementation of VoiceConversation
 */
private class VoiceConversationImpl(
    private val sdk: RunAnywhereSDK,
    private val config: VoiceConversationConfig
) : VoiceConversation {

    override val sessionId: String = "voice-session-${System.currentTimeMillis()}"

    private val conversationHistory = mutableListOf<Pair<String, String>>()

    override suspend fun processVoiceTurn(audioData: ByteArray): String {
        voiceLogger.debug("[$sessionId] Processing voice turn: ${audioData.size} bytes")

        // Transcribe audio
        val transcription = sdk.transcribe(audioData, STTOptions(language = config.language))
        val userInput = transcription.text

        voiceLogger.info("[$sessionId] User said: $userInput")

        // Build conversation context
        val contextPrompt = buildContextPrompt(userInput)

        // Generate response
        val response = sdk.chat(contextPrompt)

        // Store in history
        conversationHistory.add(userInput to response)

        voiceLogger.info("[$sessionId] Response: $response")
        return response
    }

    override suspend fun end() {
        voiceLogger.info("[$sessionId] Ending voice conversation")
        conversationHistory.clear()
    }

    private fun buildContextPrompt(userInput: String): String {
        if (conversationHistory.isEmpty()) {
            return userInput
        }

        val context = conversationHistory.takeLast(5).joinToString("\n") { (user, assistant) ->
            "User: $user\nAssistant: $assistant"
        }

        return "$context\nUser: $userInput\nAssistant:"
    }
}
