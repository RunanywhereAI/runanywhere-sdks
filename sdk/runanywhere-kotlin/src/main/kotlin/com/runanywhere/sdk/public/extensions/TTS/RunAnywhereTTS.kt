/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Text-to-Speech operations.
 * Calls C++ directly via CppBridge.TTS for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+TTS.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.TTSSpeakResult
import ai.runanywhere.proto.v1.TTSVoiceInfo
import com.runanywhere.sdk.features.TTS.Services.TtsAudioPlayback
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory

// MARK: - Synthesis

// MARK: - Speak (Simple API)

private val ttsLogger = SDKLogger.tts
private val ttsAudioPlayback = TtsAudioPlayback

/**
 * Internal helper: list available TTS voices from the C ABI.
 *
 * Per Swift parity, the public surface uses the model registry filtered by
 * `MODEL_CATEGORY_SPEECH_SYNTHESIS` to enumerate voices. This helper is
 * retained as INTERNAL for callers that still need the
 * `racTtsComponentListVoicesProto` enumeration.
 */
internal suspend fun RunAnywhere.availableTTSVoicesInternal(): List<TTSVoiceInfo> {
    return CppBridgeTTS.voices()
}

suspend fun RunAnywhere.synthesize(
    text: String,
    options: RATTSOptions = RATTSOptions.defaults(),
): RATTSOutput {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    ensureServicesReady()

    // Lifecycle check: mirrors Swift's `synthesize(_:options:)` which queries
    // `RunAnywhere.currentModel(category: .speechSynthesis)` and throws when
    // no TTS voice is loaded. Querying the lifecycle (canonical source of
    // truth) is required because `CppBridgeTTS` owns its own handle that is
    // separate from the lifecycle's handle.
    val current =
        CppBridgeModelLifecycle.currentModel(
            CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
        )
    if (current?.found != true) {
        throw SDKException.notInitialized("TTS voice not loaded")
    }

    val voiceId = current.model_id.takeIf { it.isNotEmpty() } ?: "unknown"
    ttsLogger.debug("Synthesizing text: ${text.take(50)}${if (text.length > 50) "..." else ""} (voice: $voiceId)")

    val result = CppBridgeTTS.synthesize(text, options)
    ttsLogger.info("Synthesis complete: ${result.duration_ms}ms audio")
    return result
}

fun RunAnywhere.synthesizeStream(
    text: String,
    options: RATTSOptions = RATTSOptions.defaults(),
): Flow<RATTSOutput> =
    callbackFlow {
        if (!isInitialized) {
            close()
            return@callbackFlow
        }

        // Mirror synthesize(): query ModelLifecycle (the canonical source of
        // truth) instead of CppBridgeTTS's own handle. Swift's
        // `synthesizeStream` finishes the stream silently when no voice is
        // loaded; we mirror that by closing the Flow without emitting.
        val current =
            CppBridgeModelLifecycle.currentModel(
                CurrentModelRequest(category = ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
            )
        if (current?.found != true) {
            close()
            return@callbackFlow
        }

        // Cancellation flag observed by the native chunk callback: once the
        // Flow channel is closed (collector cancelled or completed), the
        // listener returns false so the native synthesizer stops emitting.
        val cancelled = AtomicBoolean(false)

        // Run the synchronous native streaming call on the IO dispatcher so
        // the collector coroutine remains free to be cancelled. awaitClose
        // fires when the collector cancels and we ask the lifecycle stop
        // ABI to interrupt the native side; the launched task then exits
        // when racTtsSynthesizeStreamLifecycleProto returns.
        val driver =
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    CppBridgeTTS.synthesizeStream(text, options) { output ->
                        if (cancelled.get()) {
                            false
                        } else {
                            trySend(output).isSuccess
                        }
                    }
                } catch (t: Throwable) {
                    ttsLogger.warn("synthesizeStream errored: ${t.message}")
                } finally {
                    close()
                }
            }

        awaitClose {
            cancelled.set(true)
            // Best-effort: ask the lifecycle TTS stack to stop emitting.
            // withContext(NonCancellable) so this still runs even when the
            // outer coroutine is in cancelling state. The driver coroutine
            // then unblocks once the native stream returns.
            driver.cancel()
            CoroutineScope(NonCancellable).launch {
                withContext(NonCancellable) {
                    try {
                        CppBridgeTTS.stop()
                    } catch (t: Throwable) {
                        ttsLogger.debug("CppBridgeTTS.stop() failed: ${t.message}")
                    }
                }
            }
        }
    }

suspend fun RunAnywhere.stopSynthesis() {
    CppBridgeTTS.stop()
}

suspend fun RunAnywhere.speak(
    text: String,
    options: RATTSOptions = RATTSOptions.defaults(),
): TTSSpeakResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val output = synthesize(text, options)

    // Convert Float32 PCM to WAV format using C++ utility (Swift parity).
    // TTS backends output raw Float32 PCM; AudioPlaybackManager expects a
    // complete WAV file (with header) for MediaPlayer / javax.sound.
    val sampleRate =
        when {
            output.sample_rate > 0 -> output.sample_rate
            options.sample_rate > 0 -> options.sample_rate
            else -> 22_050
        }
    val wavData = convertPcmToWav(output.audio_data.toByteArray(), sampleRate)

    if (wavData.isNotEmpty()) {
        try {
            ttsAudioPlayback.play(wavData)
            ttsLogger.debug("Audio playback completed")
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            // Caller cancelled (navigation, new speak request) — propagate
            // instead of reporting a playback failure.
            throw e
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

/**
 * Convert Float32 PCM to WAV using the C++ audio utility (Swift parity).
 *
 * Mirrors Swift's `convertPCMToWAV(pcmData:sampleRate:)` which calls
 * `rac_audio_float32_to_wav`. Returns an empty ByteArray for empty input
 * and throws on conversion failure.
 */
private fun convertPcmToWav(pcmData: ByteArray, sampleRate: Int): ByteArray {
    if (pcmData.isEmpty()) return ByteArray(0)
    return RunAnywhereBridge.racAudioFloat32ToWav(pcmData, sampleRate)
        ?: throw SDKException.tts("Failed to convert PCM to WAV")
}

suspend fun RunAnywhere.stopSpeaking() {
    ttsAudioPlayback.stop()
    stopSynthesis()
}
