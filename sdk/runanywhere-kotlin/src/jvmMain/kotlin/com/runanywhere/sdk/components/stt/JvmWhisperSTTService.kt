package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.JvmWhisperJNIModelMapper
import io.github.givimad.whisperjni.WhisperContext
import io.github.givimad.whisperjni.WhisperFullParams
import io.github.givimad.whisperjni.WhisperJNI
import io.github.givimad.whisperjni.WhisperSamplingStrategy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Paths

/**
 * JVM implementation of STT service using WhisperJNI library.
 *
 * This implementation mirrors the iOS WhisperKitService exactly,
 * following the iOS implementation as the source of truth.
 */
class JvmWhisperSTTService : STTService {
    private val logger = SDKLogger("JvmWhisperSTTService")

    private var whisperContext: WhisperContext? = null
    private var whisperJNI: WhisperJNI? = null
    private var isInitialized = false
    private var currentModelPath: String? = null

    // Model storage directory (follows iOS pattern)
    private val modelStorageDir = Paths.get(
        System.getProperty("user.home"),
        ".runanywhere",
        "models"
    ).toFile()

    override val isReady: Boolean
        get() = isInitialized && whisperContext != null

    override val currentModel: String?
        get() = currentModelPath

    override val supportedLanguages: List<String>
        get() = listOf(
            "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr",
            "pl", "ca", "nl", "ar", "sv", "it", "id", "hi", "fi", "vi",
            "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no"
        )

    override suspend fun initialize(modelPath: String?) {
        withContext(Dispatchers.IO) {
            try {
                // Skip if already initialized with same model (iOS pattern)
                val targetModelPath = modelPath ?: "whisper-base"
                if (isInitialized && whisperContext != null && currentModelPath == targetModelPath) {
                    logger.info("WhisperJNI service already initialized with model: $targetModelPath")
                    return@withContext
                }

                logger.info("Initializing WhisperJNI service with model: $targetModelPath")

                // Cleanup existing context if any
                cleanup()

                // Get the actual model file path
                val modelFileName = JvmWhisperJNIModelMapper.mapModelIdToFileName(targetModelPath)
                val modelFile = File(modelStorageDir, modelFileName)

                if (!modelFile.exists()) {
                    throw STTError.modelNotFound(modelFileName)
                }

                logger.info("Loading model from: ${modelFile.absolutePath}")

                // Initialize WhisperJNI library
                if (whisperJNI == null) {
                    whisperJNI = WhisperJNI()
                    try {
                        WhisperJNI.loadLibrary()
                        logger.info("WhisperJNI library loaded successfully")
                    } catch (e: Exception) {
                        // Library might already be loaded
                        logger.debug("WhisperJNI library load attempt: ${e.message}")
                    }
                }

                // Initialize WhisperJNI context (with fallback strategy like iOS)
                try {
                    val jni = whisperJNI!!
                    whisperContext = jni.init(modelFile.toPath())
                    logger.info("Successfully loaded WhisperJNI model: $modelFileName")
                } catch (e: Exception) {
                    logger.warn("Failed to load requested model $modelFileName, attempting fallback to base model")

                    // Fallback to base model (iOS pattern)
                    val baseModelFile = File(modelStorageDir, "ggml-base.bin")
                    if (baseModelFile.exists()) {
                        val jni = whisperJNI!!
                        whisperContext = jni.init(baseModelFile.toPath())
                        logger.info("Fallback successful: loaded base model")
                        currentModelPath = "whisper-base"
                    } else {
                        throw STTError.modelNotFound("base model")
                    }
                }

                if (whisperContext == null) {
                    throw STTError.serviceNotInitialized
                }

                currentModelPath = targetModelPath
                isInitialized = true

                logger.info("WhisperJNI service initialized successfully")

            } catch (e: Exception) {
                logger.error("Failed to initialize WhisperJNI service", e)
                cleanup()
                throw when (e) {
                    is STTError -> e
                    else -> STTError.serviceNotInitialized
                }
            }
        }
    }

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTTranscriptionResult {
        if (!isReady) {
            throw STTError.serviceNotInitialized
        }

        return withContext(Dispatchers.IO) {
            try {
                logger.debug("Starting transcription of ${audioData.size} bytes")
                val startTime = System.currentTimeMillis()

                // Convert audio data to float samples (16kHz mono expected by Whisper)
                val audioSamples = convertPCMBytesToFloat(audioData)
                logger.debug("Converted ${audioData.size} bytes to ${audioSamples.size} float samples")

                // Create transcription parameters
                val params = createWhisperParams(options)

                // Perform transcription
                val whisperCtx = whisperContext ?: throw STTError.serviceNotInitialized
                val jni = whisperJNI ?: throw STTError.serviceNotInitialized

                val result = jni.full(whisperCtx, params, audioSamples, audioSamples.size)
                if (result != 0) {
                    throw STTError.transcriptionFailed(RuntimeException("WhisperJNI transcription failed with result code: $result"))
                }

                // Extract transcription text
                val segmentCount = jni.fullNSegments(whisperCtx)
                val transcriptionText = buildString {
                    for (i in 0 until segmentCount) {
                        append(jni.fullGetSegmentText(whisperCtx, i))
                    }
                }.trim()

                val processingTime = System.currentTimeMillis() - startTime
                logger.debug("Transcription completed in ${processingTime}ms")

                // Validate transcription result (iOS pattern)
                val cleanedText = transcriptionText.trim()
                val finalText = if (isGarbledOutput(cleanedText)) {
                    logger.warn("Detected garbled output, returning empty result")
                    ""
                } else {
                    cleanedText
                }

                // Create result matching iOS structure
                STTTranscriptionResult(
                    transcript = finalText,
                    language = options.language ?: "en",
                    confidence = if (finalText.isEmpty()) 0.0f else 0.95f,
                    timestamps = extractTimestamps(finalText, options)
                )

            } catch (e: Exception) {
                logger.error("Transcription failed", e)
                throw STTError.transcriptionFailed(e)
            }
        }
    }

    private fun transcribeStreamInternal(
        audioStream: Flow<ByteArray>,
        options: STTOptions?
    ): Flow<STTTranscriptionResult> = flow {
        if (!isReady) {
            throw STTError.serviceNotInitialized
        }

        logger.debug("Starting streaming transcription")

        // Streaming implementation with context preservation (iOS pattern)
        val minAudioLength = 8000 // 500ms at 16kHz (similar to iOS)
        val contextOverlap = 1600  // 100ms overlap for context (iOS pattern)
        val audioBuffer = mutableListOf<Float>()
        var lastTranscript = ""

        try {
            audioStream.collect { audioChunk ->
                // Convert chunk to float samples
                val chunkSamples = convertPCMBytesToFloat(audioChunk)
                audioBuffer.addAll(chunkSamples.toList())

                // Process when we have enough audio data
                if (audioBuffer.size >= minAudioLength) {
                    val processingBuffer = audioBuffer.toFloatArray()

                    try {
                        val whisperCtx = whisperContext ?: throw STTError.serviceNotInitialized
                        val jni = whisperJNI ?: throw STTError.serviceNotInitialized

                        val params = createWhisperParams(options ?: STTOptions())
                        val result = jni.full(whisperCtx, params, processingBuffer, processingBuffer.size)

                        if (result == 0) {
                            // Extract result
                            val segmentCount = jni.fullNSegments(whisperCtx)
                            val transcriptionResult = buildString {
                                for (i in 0 until segmentCount) {
                                    append(jni.fullGetSegmentText(whisperCtx, i))
                                }
                            }.trim()

                            // Clean and validate result
                            if (transcriptionResult.isNotEmpty() && !isGarbledOutput(transcriptionResult) && transcriptionResult != lastTranscript) {
                                val sttResult = STTTranscriptionResult(
                                    transcript = transcriptionResult,
                                    language = options?.language ?: "en",
                                    confidence = 0.90f,
                                    timestamps = extractTimestamps(transcriptionResult, options)
                                )

                                emit(sttResult)
                                lastTranscript = transcriptionResult
                            }
                        }
                    } catch (e: Exception) {
                        logger.error("Error in streaming transcription", e)
                        // Continue processing rather than failing completely
                    }

                    // Keep context overlap for continuity (iOS pattern)
                    val overlapSamples = audioBuffer.takeLast(contextOverlap)
                    audioBuffer.clear()
                    audioBuffer.addAll(overlapSamples)
                }
            }

            logger.debug("Streaming transcription completed")

        } catch (e: Exception) {
            logger.error("Streaming transcription failed", e)
            throw STTError.transcriptionFailed(e)
        }
    }

    override suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult {
        // Convert the Flow-based streaming to callback-based
        var lastResult = STTTranscriptionResult(transcript = "")

        transcribeStreamInternal(audioStream, options).collect { result ->
            if (result.transcript != lastResult.transcript) {
                onPartial(result.transcript)
                lastResult = result
            }
        }

        return lastResult
    }

    override fun transcribeStream(
        audioStream: Flow<ByteArray>,
        options: STTStreamingOptions
    ): Flow<STTStreamEvent> = flow {
        // For now, convert STTOptions to our internal streaming
        val sttOptions = STTOptions(
            language = options.language ?: "auto",
            enableTimestamps = false // Simplified for streaming
        )

        emit(STTStreamEvent.SpeechStarted)

        try {
            transcribeStreamInternal(audioStream, sttOptions).collect { result ->
                emit(STTStreamEvent.PartialTranscription(
                    text = result.transcript,
                    confidence = result.confidence ?: 0.9f,
                    isFinal = false
                ))
            }

            emit(STTStreamEvent.SpeechEnded)
        } catch (e: Exception) {
            emit(STTStreamEvent.Error(STTError.transcriptionFailed(e)))
        }
    }

    override suspend fun detectLanguage(audioData: ByteArray): Map<String, Float> {
        // Basic implementation - in production this would use language detection
        return mapOf("en" to 0.8f, "es" to 0.1f, "fr" to 0.1f)
    }

    override fun supportsLanguage(languageCode: String): Boolean {
        return supportedLanguages.contains(languageCode.lowercase())
    }

    override suspend fun cleanup() {
        withContext(Dispatchers.IO) {
            try {
                whisperContext?.close()
                logger.info("WhisperJNI context closed")
            } catch (e: Exception) {
                logger.error("Error closing WhisperJNI context", e)
            }

            whisperContext = null
            whisperJNI = null
            isInitialized = false
            currentModelPath = null
        }
    }

    /**
     * Convert PCM byte array to float array for WhisperJNI
     * Assumes 16-bit signed PCM audio data at 16kHz mono
     */
    private fun convertPCMBytesToFloat(pcmBytes: ByteArray): FloatArray {
        // Convert 16-bit signed PCM to float array
        // Each sample is 2 bytes (little-endian)
        val floatArray = FloatArray(pcmBytes.size / 2)

        for (i in floatArray.indices) {
            val byteIndex = i * 2

            // Convert little-endian 16-bit signed integer to float [-1.0, 1.0]
            val sample = if (byteIndex + 1 < pcmBytes.size) {
                val low = pcmBytes[byteIndex].toInt() and 0xFF
                val high = pcmBytes[byteIndex + 1].toInt()
                ((high shl 8) or low).toShort()
            } else {
                0
            }

            // Normalize to [-1.0, 1.0] range
            floatArray[i] = sample / 32768.0f
        }

        return floatArray
    }

    /**
     * Detect garbled output patterns (copied from iOS implementation)
     */
    private fun isGarbledOutput(text: String): Boolean {
        val trimmedText = text.trim()
        if (trimmedText.isEmpty()) return false

        // Check for common garbled patterns (iOS equivalent)
        val garbledPatterns = listOf(
            "^[\\(\\)\\-\\.\\s]+$",  // Only punctuation and spaces
            "^[\\-]{10,}",          // Many consecutive dashes
            "^[\\(]{5,}",           // Many consecutive parentheses
            "^\\s*\\[.*\\]\\s*$",   // Text wrapped in brackets
            "^\\s*<.*>\\s*$"        // Text wrapped in angle brackets
        )

        for (pattern in garbledPatterns) {
            if (trimmedText.matches(Regex(pattern))) {
                return true
            }
        }

        // Check character composition - if >70% punctuation, likely garbled (iOS pattern)
        val punctuationCount = trimmedText.count { !it.isLetterOrDigit() && !it.isWhitespace() }
        val totalCount = trimmedText.length
        if (totalCount > 5 && punctuationCount.toDouble() / totalCount > 0.7) {
            return true
        }

        return false
    }

    /**
     * Extract timestamps from text (basic implementation)
     * TODO: Enhance with actual word-level timestamps when WhisperJNI supports it
     */
    private fun extractTimestamps(text: String, options: STTOptions?): List<STTTranscriptionResult.TimestampInfo>? {
        if (options?.enableTimestamps != true || text.isEmpty()) {
            return null
        }

        // Basic word-level timestamp estimation
        val words = text.split("\\s+".toRegex())
        val timestamps = mutableListOf<STTTranscriptionResult.TimestampInfo>()

        for (i in words.indices) {
            val word = words[i]
            val startTime = i * 0.5 // Rough estimate: 0.5 seconds per word
            val endTime = startTime + 0.4

            timestamps.add(
                STTTranscriptionResult.TimestampInfo(
                    word = word,
                    startTime = startTime,
                    endTime = endTime,
                    confidence = 0.90f
                )
            )
        }

        return timestamps
    }

    /**
     * Create WhisperFullParams from STTOptions
     */
    private fun createWhisperParams(options: STTOptions): WhisperFullParams {
        // Use GREEDY sampling strategy (most reliable)
        val params = WhisperFullParams(WhisperSamplingStrategy.GREEDY)

        // Set language (auto-detection if null or "auto")
        params.language = when (options.language) {
            null, "auto", "detect" -> "auto"
            else -> options.language.take(2) // Use ISO 639-1 codes
        }

        // Enable timestamps if requested
        params.printTimestamps = options.enableTimestamps ?: false

        // Conservative settings to match iOS quality (prevent garbled output)
        params.temperature = 0.0f
        params.suppressBlank = true
        params.suppressNonSpeechTokens = true
        // Note: Some WhisperJNI params may not exist, keeping essential ones
        // params.noSpeechThreshold = 0.6f  // May not exist in givimad WhisperJNI
        // params.logprobThreshold = -1.0f   // May not exist in givimad WhisperJNI
        // params.compressionRatioThreshold = 2.4f // May not exist in givimad WhisperJNI

        // Single best result (no beam search for speed)
        // params.bestOf = 1  // May not exist in givimad WhisperJNI

        // Disable verbose output for production
        params.printProgress = false
        params.printSpecial = false

        logger.debug("Created WhisperFullParams with language: ${params.language}, timestamps: ${params.printTimestamps}")

        return params
    }
}
