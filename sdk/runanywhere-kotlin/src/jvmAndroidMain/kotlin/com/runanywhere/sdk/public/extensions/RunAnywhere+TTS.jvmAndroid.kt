/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Text-to-Speech operations.
 * Wave 2 KOTLIN: now uses proto-canonical TTSOptions / TTSOutput / TTSSpeakResult.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.AudioFormat
import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSSpeakResult
import ai.runanywhere.proto.v1.TTSVoiceInfo
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory
import com.runanywhere.sdk.features.tts.TtsAudioPlayback
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTSProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

private val ttsLogger = SDKLogger.tts
private val ttsAudioPlayback = TtsAudioPlayback

private fun currentTtsVoiceIdFromLifecycle(): String? =
    CppBridgeModelLifecycleProto.currentModel(
        CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
    )?.model_id?.takeIf { it.isNotEmpty() }

actual suspend fun RunAnywhere.loadTTSModel(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    ttsLogger.debug("Loading TTS model: $modelId")
    val modelInfo =
        CppBridgeModelRegistry.get(modelId)
            ?: throw SDKException.tts("TTS model '$modelId' not found in registry")
    val localPath =
        modelInfo.local_path.takeIf { it.isNotEmpty() }
            ?: throw SDKException.tts("TTS model '$modelId' is not downloaded")
    val result =
        loadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                framework = modelInfo.framework,
            ),
        )
    if (!result.success) {
        throw SDKException.tts(
            result.error_message.ifBlank { "Failed to load TTS model '$modelId' from $localPath" },
        )
    }
    ttsLogger.info("TTS model loaded: $modelId")
}

actual suspend fun RunAnywhere.unloadTTSModel() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    unloadModel(ModelUnloadRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS))
    ttsLogger.info("TTS model unloaded")
}

actual suspend fun RunAnywhere.loadTTSVoice(voiceId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ttsLogger.debug("Loading TTS voice: $voiceId")

    val modelInfo =
        CppBridgeModelRegistry.get(voiceId)
            ?: throw SDKException.tts("Voice '$voiceId' not found in registry")

    val localPath =
        modelInfo.local_path.takeIf { it.isNotEmpty() }
            ?: throw SDKException.tts("Voice '$voiceId' is not downloaded")

    val result =
        loadModel(
            ModelLoadRequest(
                model_id = voiceId,
                category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                framework = modelInfo.framework,
            ),
        )
    if (!result.success) {
        val message = result.error_message.ifBlank { "Failed to load TTS voice '$voiceId' from $localPath" }
        ttsLogger.error(message)
        throw SDKException.tts(message)
    }
    ttsLogger.info("TTS voice loaded: $voiceId")
}

actual suspend fun RunAnywhere.unloadTTSVoice() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    unloadModel(ModelUnloadRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS))
}

actual val RunAnywhere.isTTSVoiceLoaded: Boolean
    get() =
        CppBridgeModelLifecycleProto.snapshot(SDKComponent.SDK_COMPONENT_TTS)
            ?.let {
                it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    it.model_id.isNotEmpty()
            } ?: false

actual val RunAnywhere.currentTTSVoiceId: String?
    get() = currentTtsVoiceIdFromLifecycle()

actual val RunAnywhere.isTTSVoiceLoadedSync: Boolean
    get() = isTTSVoiceLoaded

actual suspend fun RunAnywhere.availableTTSVoices(): List<TTSVoiceInfo> {
    return CppBridgeTTSProto.voices()
}

actual suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions,
): TTSOutput {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val voiceId = currentTtsVoiceIdFromLifecycle() ?: "unknown"
    ttsLogger.debug("Synthesizing text: ${text.take(50)}${if (text.length > 50) "..." else ""} (voice: $voiceId)")

    val result = CppBridgeTTSProto.synthesize(text, options)
    ttsLogger.info("Synthesis complete: ${result.duration_ms}ms audio")
    return result
}

actual fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions,
): Flow<ByteArray> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        try {
            CppBridgeTTSProto.synthesizeStream(text, options) { output ->
                trySend(output.audio_data.toByteArray())
                true
            }
        } finally {
            close()
        }
        awaitClose()
    }

actual suspend fun RunAnywhere.stopSynthesis() {
    // TTS generated-proto streaming is synchronous; cancellation is handled
    // by the native generation call and collector closure.
}

actual suspend fun RunAnywhere.speak(
    text: String,
    options: TTSOptions,
): TTSSpeakResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val output = synthesize(text, options)

    if (output.audio_data.size > 0) {
        try {
            ttsAudioPlayback.play(output.audio_data.toByteArray())
            ttsLogger.debug("Audio playback completed")
        } catch (e: Exception) {
            ttsLogger.error("Audio playback failed: ${e.message}", throwable = e)
            throw if (e is SDKException) e else SDKException.tts("Failed to play audio: ${e.message}")
        }
    }

    return TTSSpeakResult(
        audio_format = output.audio_format,
        sample_rate = output.sample_rate,
        duration_ms = output.duration_ms,
        audio_size_bytes = output.audio_data.size.toLong(),
        metadata = output.metadata,
        timestamp_ms = output.timestamp_ms,
    )
}

actual val RunAnywhere.isSpeaking: Boolean
    get() = ttsAudioPlayback.isPlaying

actual suspend fun RunAnywhere.stopSpeaking() {
    ttsAudioPlayback.stop()
    stopSynthesis()
}
