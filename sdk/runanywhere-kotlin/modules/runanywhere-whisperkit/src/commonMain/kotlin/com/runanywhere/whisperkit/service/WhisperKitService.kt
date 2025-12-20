package com.runanywhere.whisperkit.service

import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.stt.STTOptions
import com.runanywhere.sdk.features.stt.STTTranscriptionResult
import com.runanywhere.whisperkit.models.*
import com.runanywhere.whisperkit.storage.WhisperStorageStrategy
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * WhisperKit-specific implementation of the generic STTService interface
 * This is the Whisper-specific adapter that extends the generic STT abstractions
 * Matches iOS WhisperKitService architecture
 */
abstract class WhisperKitService : STTService {

    // WhisperKit-specific state management (not part of generic STT)
    protected val _whisperState = MutableStateFlow(WhisperServiceState.UNINITIALIZED)
    val whisperState: StateFlow<WhisperServiceState> = _whisperState

    protected val _currentWhisperModel = MutableStateFlow<WhisperModelType?>(null)
    val currentWhisperModel: StateFlow<WhisperModelType?> = _currentWhisperModel

    // Whisper-specific storage strategy
    protected abstract val whisperStorage: WhisperStorageStrategy

    /**
     * Initialize with a specific Whisper model type
     * This is a Whisper-specific convenience method
     */
    suspend fun initializeWithWhisperModel(modelType: WhisperModelType = WhisperModelType.BASE) {
        val modelPath = whisperStorage.getModelPath(modelType)
        initialize(modelPath)
        _currentWhisperModel.value = modelType
        _whisperState.value = WhisperServiceState.READY
    }

    /**
     * Transcribe with Whisper-specific options
     * This extends the generic transcribe with Whisper-specific parameters
     * Note: Whisper-specific options (temperature, suppressBlank, etc.) are passed via
     * WhisperTranscriptionOptions and applied in platform implementations
     */
    suspend fun transcribeWithWhisperOptions(
        audioData: ByteArray,
        options: WhisperTranscriptionOptions
    ): WhisperTranscriptionResult {
        // Convert Whisper options to generic STT options (iOS-compatible subset)
        val sttOptions = STTOptions(
            language = options.language,
            enableTimestamps = options.enableTimestamps,
            detectLanguage = options.detectLanguage
        )

        // Use generic transcribe method
        val result = transcribe(audioData, sttOptions)

        // Convert generic result to Whisper-specific result with additional metadata
        return WhisperTranscriptionResult(
            text = result.transcript,
            segments = extractWhisperSegments(result),
            language = result.language,
            confidence = result.confidence ?: 0.0f,
            duration = estimateDuration(audioData),
            timestamps = result.timestamps?.map { timestamp ->
                WordTimestamp(
                    word = timestamp.word,
                    startTime = timestamp.startTime,
                    endTime = timestamp.endTime,
                    confidence = timestamp.confidence ?: 0.0f
                )
            }
        )
    }

    /**
     * Stream transcription with Whisper-specific options
     * Note: Whisper-specific options are passed to platform implementations
     */
    fun transcribeStreamWithWhisperOptions(
        audioStream: Flow<ByteArray>,
        options: WhisperTranscriptionOptions
    ): Flow<WhisperTranscriptionResult> {
        val sttOptions = STTOptions(
            language = options.language,
            enableTimestamps = options.enableTimestamps,
            detectLanguage = options.detectLanguage
        )
        return transcribeStreamInternal(audioStream, sttOptions)
    }

    /**
     * Internal streaming implementation to be provided by platform
     */
    protected abstract fun transcribeStreamInternal(
        audioStream: Flow<ByteArray>,
        options: STTOptions
    ): Flow<WhisperTranscriptionResult>

    /**
     * Whisper-specific: Switch to a different model
     */
    open suspend fun switchWhisperModel(modelType: WhisperModelType) {
        cleanup()
        initializeWithWhisperModel(modelType)
    }

    /**
     * Whisper-specific: Get available Whisper models
     */
    open suspend fun getAvailableWhisperModels(): List<WhisperModelInfo> {
        return whisperStorage.getAllModels()
    }

    /**
     * Whisper-specific: Download a Whisper model if not available
     */
    open suspend fun downloadWhisperModel(
        modelType: WhisperModelType,
        onProgress: (Float) -> Unit = {}
    ) {
        _whisperState.value = WhisperServiceState.DOWNLOADING_MODEL
        whisperStorage.downloadModel(modelType) { progress ->
            onProgress(progress.percentage.toFloat())
        }
        _whisperState.value = WhisperServiceState.READY
    }

    /**
     * Implementation of generic cleanup
     */
    override suspend fun cleanup() {
        _whisperState.value = WhisperServiceState.UNINITIALIZED
        _currentWhisperModel.value = null
    }

    // Helper methods for Whisper-specific processing
    protected open fun extractWhisperSegments(result: STTTranscriptionResult): List<TranscriptionSegment> {
        // Platform implementations can override to provide actual segments
        return emptyList()
    }

    protected fun estimateDuration(audioData: ByteArray): Double {
        // Estimate based on 16kHz, 16-bit PCM
        return audioData.size.toDouble() / (16000 * 2)
    }
}

/**
 * Factory for creating WhisperKit service instances
 */
expect object WhisperKitFactory {
    fun createService(): WhisperKitService
}
