package com.runanywhere.sdk.features.tts

/**
 * Platform audio playback for TTS speak.
 */
internal expect object TtsAudioPlayback {
    suspend fun play(audioData: ByteArray)

    fun stop()

    val isPlaying: Boolean
}
