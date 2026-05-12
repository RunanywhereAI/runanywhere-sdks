package com.runanywhere.sdk.features.TTS.Services

import com.runanywhere.sdk.infrastructure.logging.SDKLogger

internal actual object TtsAudioPlayback {
    private val logger = SDKLogger.tts

    actual val isPlaying: Boolean
        get() = false

    actual suspend fun play(audioData: ByteArray) {
        if (audioData.isNotEmpty()) {
            logger.warning("Audio playback is not supported on JVM targets")
        }
    }

    actual fun stop() {
        // No-op on JVM.
    }
}
