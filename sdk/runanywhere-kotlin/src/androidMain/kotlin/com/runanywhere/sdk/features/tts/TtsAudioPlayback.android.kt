package com.runanywhere.sdk.features.tts

internal actual object TtsAudioPlayback {
    private val audioPlaybackManager = AudioPlaybackManager()

    actual val isPlaying: Boolean
        get() = audioPlaybackManager.isPlaying

    actual suspend fun play(audioData: ByteArray) {
        audioPlaybackManager.play(audioData)
    }

    actual fun stop() {
        audioPlaybackManager.stop()
    }
}
