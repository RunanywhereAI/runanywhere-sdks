package com.runanywhere.sdk.features.TTS.Services

internal object TtsAudioPlayback {
    private val audioPlaybackManager by lazy { AudioPlaybackManager() }

    val isPlaying: Boolean
        get() = audioPlaybackManager.isPlaying

    suspend fun play(audioData: ByteArray) {
        audioPlaybackManager.play(audioData)
    }

    fun stop() {
        audioPlaybackManager.stop()
    }
}
