package com.runanywhere.sdk.components.stt

import kotlinx.coroutines.flow.Flow

/**
 * Cross-platform Whisper STT Service
 * Provides high-quality speech-to-text transcription using OpenAI's Whisper model
 */
expect class WhisperSTTService() : STTService {
    override suspend fun initialize(modelPath: String?)
    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTTranscriptionResult
    override suspend fun <T> streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult
    override val isReady: Boolean
    override val currentModel: String?
}
