package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.serialization.Serializable
import java.io.File

/**
 * JNI wrapper for whisper.cpp library
 * Provides native speech-to-text functionality using whisper models
 */
object WhisperJNI {
    private val logger = SDKLogger("WhisperJNI")
    private var isLibraryLoaded = false

    // Native library loading
    init {
        loadNativeLibrary()
    }

    /**
     * Load the native whisper library
     */
    private fun loadNativeLibrary() {
        try {
            System.loadLibrary("whisper-jni")
            isLibraryLoaded = true
            logger.info("Successfully loaded whisper-jni native library")
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Failed to load whisper-jni native library", e)
            isLibraryLoaded = false
        }
    }

    /**
     * Check if native library is loaded
     */
    fun isLoaded(): Boolean = isLibraryLoaded

    /**
     * Initialize whisper context with model file
     * @param modelPath Path to the whisper model file (.bin)
     * @return Context handle (pointer to whisper_context), 0 if failed
     */
    external fun whisperInit(modelPath: String): Long

    /**
     * Initialize whisper context with model data buffer
     * @param modelData Binary model data
     * @return Context handle (pointer to whisper_context), 0 if failed
     */
    external fun whisperInitFromBuffer(modelData: ByteArray): Long

    /**
     * Free whisper context
     * @param contextHandle Context handle returned by whisperInit
     */
    external fun whisperFree(contextHandle: Long)

    /**
     * Get model information
     * @param contextHandle Context handle
     * @return WhisperModelInfo containing model details
     */
    external fun whisperGetModelInfo(contextHandle: Long): WhisperModelInfo

    /**
     * Transcribe audio data
     * @param contextHandle Context handle
     * @param audioData Audio samples as float array (16kHz mono)
     * @param language Language code (e.g., "en", "es", null for auto-detect)
     * @param enableTimestamps Enable word-level timestamps
     * @param enableTranslate Translate to English if non-English detected
     * @return WhisperResult containing transcription and metadata
     */
    external fun whisperTranscribe(
        contextHandle: Long,
        audioData: FloatArray,
        language: String?,
        enableTimestamps: Boolean,
        enableTranslate: Boolean,
    ): WhisperResult

    /**
     * Transcribe audio with advanced options
     * @param contextHandle Context handle
     * @param audioData Audio samples as float array
     * @param params WhisperParams containing detailed configuration
     * @return WhisperResult containing transcription and metadata
     */
    external fun whisperTranscribeWithParams(
        contextHandle: Long,
        audioData: FloatArray,
        params: WhisperParams,
    ): WhisperResult

    /**
     * Get number of detected language probabilities
     * @param contextHandle Context handle
     * @return Number of language probabilities available
     */
    external fun whisperGetLanguageCount(contextHandle: Long): Int

    /**
     * Get detected language probabilities
     * @param contextHandle Context handle
     * @return Array of WhisperLanguageProb
     */
    external fun whisperGetLanguageProbs(contextHandle: Long): Array<WhisperLanguageProb>

    /**
     * Convert audio format (e.g., 16-bit PCM to float)
     * @param pcmData 16-bit PCM audio data
     * @param sampleRate Original sample rate
     * @param targetSampleRate Target sample rate (16000 for whisper)
     * @return Float array suitable for whisper processing
     */
    external fun convertPcmToFloat(
        pcmData: ByteArray,
        sampleRate: Int,
        targetSampleRate: Int,
    ): FloatArray

    /**
     * Get whisper.cpp version
     * @return Version string
     */
    external fun getVersion(): String

    /**
     * Check if GPU acceleration is available
     * @return True if GPU acceleration is supported
     */
    external fun isGpuAvailable(): Boolean

    /**
     * Enable/disable GPU acceleration
     * @param enable True to enable GPU acceleration
     * @return True if successfully set
     */
    external fun setGpuAcceleration(enable: Boolean): Boolean
}

/**
 * Whisper model information
 */
@Serializable
data class WhisperModelInfo(
    val name: String,
    val type: String,
    val vocab: Int,
    val nMels: Int,
    val nAudioCtx: Int,
    val nAudioState: Int,
    val nAudioHead: Int,
    val nAudioLayer: Int,
    val nTextCtx: Int,
    val nTextState: Int,
    val nTextHead: Int,
    val nTextLayer: Int,
    val isMultilingual: Boolean,
)

/**
 * Whisper transcription parameters
 */
@Serializable
data class WhisperParams(
    val language: String? = null,
    val enableTimestamps: Boolean = false,
    val enableTranslate: Boolean = false,
    val enableDiarization: Boolean = false,
    val enableSpeedUp: Boolean = false,
    val enableDebug: Boolean = false,
    val audioCtx: Int = 0, // 0 = default
    val beamSize: Int = 1,
    val bestOf: Int = 1,
    val temperature: Float = 0.0f,
    val maxTokens: Int = 0, // 0 = no limit
    val noSpeechThreshold: Float = 0.6f,
    val logprobThreshold: Float = -1.0f,
    val compressionRatioThreshold: Float = 2.4f,
    val prompt: String? = null,
    val suppressBlank: Boolean = true,
    val suppressNonSpeech: Boolean = false,
)

/**
 * Whisper transcription result
 */
@Serializable
data class WhisperResult(
    val text: String,
    val language: String,
    val segments: List<WhisperSegment> = emptyList(),
    val languageProbs: Map<String, Float> = emptyMap(),
    val processingTimeMs: Long = 0,
)

/**
 * Whisper transcription segment with timestamps
 */
@Serializable
data class WhisperSegment(
    val text: String,
    val startTime: Double, // seconds
    val endTime: Double, // seconds
    val confidence: Float = 1.0f,
    val tokens: List<WhisperToken> = emptyList(),
)

/**
 * Individual whisper token with timing
 */
@Serializable
data class WhisperToken(
    val text: String,
    val startTime: Double,
    val endTime: Double,
    val confidence: Float,
    val id: Int,
)

/**
 * Language detection probability
 */
@Serializable
data class WhisperLanguageProb(
    val language: String,
    val probability: Float,
)

/**
 * High-level Whisper service wrapper
 */
class WhisperService {
    private val logger = SDKLogger("WhisperService")
    private var contextHandle: Long = 0L
    private var isInitialized = false

    /**
     * Initialize with model file
     */
    suspend fun initialize(modelPath: String): Boolean {
        if (!WhisperJNI.isLoaded()) {
            logger.error("Whisper JNI library not loaded")
            return false
        }

        if (!File(modelPath).exists()) {
            logger.error("Model file not found: $modelPath")
            return false
        }

        try {
            contextHandle = WhisperJNI.whisperInit(modelPath)
            if (contextHandle == 0L) {
                logger.error("Failed to initialize whisper context")
                return false
            }

            isInitialized = true
            logger.info("Whisper service initialized successfully with model: $modelPath")

            // Log model info
            val modelInfo = WhisperJNI.whisperGetModelInfo(contextHandle)
            logger.debug("Model info: $modelInfo")

            return true
        } catch (e: Exception) {
            logger.error("Error initializing whisper service", e)
            return false
        }
    }

    /**
     * Initialize with model data buffer
     */
    suspend fun initializeFromBuffer(modelData: ByteArray): Boolean {
        if (!WhisperJNI.isLoaded()) {
            logger.error("Whisper JNI library not loaded")
            return false
        }

        try {
            contextHandle = WhisperJNI.whisperInitFromBuffer(modelData)
            if (contextHandle == 0L) {
                logger.error("Failed to initialize whisper context from buffer")
                return false
            }

            isInitialized = true
            logger.info("Whisper service initialized from buffer (${modelData.size} bytes)")
            return true
        } catch (e: Exception) {
            logger.error("Error initializing whisper service from buffer", e)
            return false
        }
    }

    /**
     * Transcribe audio data
     */
    suspend fun transcribe(
        audioData: FloatArray,
        language: String? = null,
        enableTimestamps: Boolean = false,
        enableTranslate: Boolean = false,
    ): WhisperResult {
        if (!isInitialized) {
            throw IllegalStateException("Whisper service not initialized")
        }

        return try {
            val result =
                WhisperJNI.whisperTranscribe(
                    contextHandle = contextHandle,
                    audioData = audioData,
                    language = language,
                    enableTimestamps = enableTimestamps,
                    enableTranslate = enableTranslate,
                )
            logger.debug("Transcription completed: ${result.text.take(50)}...")
            result
        } catch (e: Exception) {
            logger.error("Error during transcription", e)
            WhisperResult(
                text = "",
                language = language ?: "unknown",
            )
        }
    }

    /**
     * Transcribe with advanced parameters
     */
    suspend fun transcribeWithParams(
        audioData: FloatArray,
        params: WhisperParams,
    ): WhisperResult {
        if (!isInitialized) {
            throw IllegalStateException("Whisper service not initialized")
        }

        return try {
            val result =
                WhisperJNI.whisperTranscribeWithParams(
                    contextHandle = contextHandle,
                    audioData = audioData,
                    params = params,
                )
            logger.debug("Advanced transcription completed: ${result.text.take(50)}...")
            result
        } catch (e: Exception) {
            logger.error("Error during advanced transcription", e)
            WhisperResult(
                text = "",
                language = params.language ?: "unknown",
            )
        }
    }

    /**
     * Convert PCM audio to float array suitable for whisper
     */
    fun convertPcmAudio(
        pcmData: ByteArray,
        sampleRate: Int,
    ): FloatArray = WhisperJNI.convertPcmToFloat(pcmData, sampleRate, 16000)

    /**
     * Get detected language probabilities
     */
    fun getLanguageProbabilities(): Array<WhisperLanguageProb> {
        if (!isInitialized) {
            return emptyArray()
        }

        return try {
            WhisperJNI.whisperGetLanguageProbs(contextHandle)
        } catch (e: Exception) {
            logger.error("Error getting language probabilities", e)
            emptyArray()
        }
    }

    /**
     * Get model information
     */
    fun getModelInfo(): WhisperModelInfo? {
        if (!isInitialized) {
            return null
        }

        return try {
            WhisperJNI.whisperGetModelInfo(contextHandle)
        } catch (e: Exception) {
            logger.error("Error getting model info", e)
            null
        }
    }

    /**
     * Check if service is initialized and ready
     */
    fun isReady(): Boolean = isInitialized && contextHandle != 0L

    /**
     * Cleanup resources
     */
    fun cleanup() {
        if (isInitialized && contextHandle != 0L) {
            try {
                WhisperJNI.whisperFree(contextHandle)
                logger.info("Whisper context cleaned up")
            } catch (e: Exception) {
                logger.error("Error cleaning up whisper context", e)
            }
        }

        contextHandle = 0L
        isInitialized = false
    }
}
