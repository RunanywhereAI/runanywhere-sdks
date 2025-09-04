package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.foundation.SDKLogger
import io.github.givimad.whisperjni.WhisperContext
import io.github.givimad.whisperjni.WhisperFullParams
import io.github.givimad.whisperjni.WhisperJNI
import io.github.givimad.whisperjni.WhisperSamplingStrategy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Paths

/**
 * Whisper STT Service implementation using whisper-jni library
 * Provides high-quality speech-to-text transcription using OpenAI's Whisper model
 */
actual class WhisperSTTService : STTService {
    private val logger = SDKLogger("WhisperSTTService")
    private var whisperJNI: WhisperJNI? = null
    private var whisperContext: WhisperContext? = null
    private var modelPath: String? = null
    private var isInitialized = false

    companion object {
        private val logger = SDKLogger("WhisperSTTService")

        init {
            try {
                // Load the Whisper JNI library
                WhisperJNI.loadLibrary()
                logger.info("Whisper JNI library loaded successfully")
            } catch (e: Exception) {
                logger.error("Failed to load Whisper JNI library", e)
            }
        }
    }

    actual override suspend fun initialize(modelPath: String?) {
        withContext(Dispatchers.IO) {
            if (modelPath == null) {
                throw STTError.ModelNotFound("Model path is required")
            }

            this@WhisperSTTService.modelPath = modelPath

            try {
                // Check if model file exists
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    throw STTError.ModelNotFound("Model file not found: $modelPath")
                }

                logger.info("Initializing Whisper model from: $modelPath")

                // Initialize WhisperJNI
                whisperJNI = WhisperJNI()

                // Load the model
                val path = Paths.get(modelPath)
                whisperContext = whisperJNI?.init(path)

                if (whisperContext == null) {
                    throw STTError.ServiceNotInitialized
                }

                isInitialized = true
                logger.info("Whisper model initialized successfully")

                // Check if model is multilingual
                val isMultilingual = whisperJNI?.isMultilingual(whisperContext!!) ?: false
                logger.info("Model is ${if (isMultilingual) "multilingual" else "English-only"}")

            } catch (e: Exception) {
                logger.error("Failed to initialize Whisper model", e)
                throw STTError.ServiceNotInitialized
            }
        }
    }

    actual override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions
    ): STTTranscriptionResult {
        if (!isInitialized || whisperContext == null || whisperJNI == null) {
            throw STTError.ServiceNotInitialized
        }

        return withContext(Dispatchers.IO) {
            try {
                logger.debug("Transcribing ${audioData.size} bytes of audio")

                // Convert ByteArray to float array (Whisper expects normalized float samples)
                val floatSamples = convertToFloatArray(audioData)

                // Configure Whisper parameters
                val params = createWhisperParams(options)

                // Run transcription
                val result =
                    whisperJNI!!.full(whisperContext!!, params, floatSamples, floatSamples.size)

                if (result != 0) {
                    logger.error("Whisper transcription failed with code: $result")
                    throw STTError.TranscriptionFailed(Exception("Transcription failed"))
                }

                // Get transcription segments
                val numSegments = whisperJNI!!.fullNSegments(whisperContext!!)
                val transcript = StringBuilder()
                val timestamps = mutableListOf<STTTranscriptionResult.TimestampInfo>()

                for (i in 0 until numSegments) {
                    val text = whisperJNI!!.fullGetSegmentText(whisperContext!!, i)
                    val startTime = whisperJNI!!.fullGetSegmentTimestamp0(whisperContext!!, i)
                    val endTime = whisperJNI!!.fullGetSegmentTimestamp1(whisperContext!!, i)

                    transcript.append(text).append(" ")

                    if (options.enableTimestamps) {
                        // Whisper timestamps are in centiseconds (1/100 second)
                        timestamps.add(
                            STTTranscriptionResult.TimestampInfo(
                                word = text.trim(),
                                startTime = startTime / 100.0,
                                endTime = endTime / 100.0,
                                confidence = 0.95f // Whisper doesn't provide per-segment confidence
                            )
                        )
                    }
                }

                STTTranscriptionResult(
                    transcript = transcript.toString().trim(),
                    confidence = 0.95f, // Whisper doesn't provide overall confidence
                    language = options.language,
                    timestamps = if (options.enableTimestamps) timestamps else null
                )

            } catch (e: Exception) {
                logger.error("Error during transcription", e)
                throw STTError.TranscriptionFailed(e)
            }
        }
    }

    actual override suspend fun <T> streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult {
        if (!isInitialized || whisperContext == null || whisperJNI == null) {
            throw STTError.ServiceNotInitialized
        }

        // For streaming, we'll accumulate audio and transcribe in chunks
        val audioBuffer = mutableListOf<Byte>()
        val fullTranscript = StringBuilder()

        audioStream.collect { chunk ->
            audioBuffer.addAll(chunk.toList())

            // Process when we have enough audio (e.g., 3 seconds worth at 16kHz)
            if (audioBuffer.size >= 16000 * 2 * 3) { // 16kHz, 2 bytes per sample, 3 seconds
                val audioData = audioBuffer.toByteArray()
                audioBuffer.clear()

                val result = transcribe(audioData, options)
                onPartial(result.transcript)
                fullTranscript.append(result.transcript).append(" ")
            }
        }

        // Process any remaining audio
        if (audioBuffer.isNotEmpty()) {
            val audioData = audioBuffer.toByteArray()
            val result = transcribe(audioData, options)
            fullTranscript.append(result.transcript)
        }

        return STTTranscriptionResult(
            transcript = fullTranscript.toString().trim(),
            confidence = 0.92f,
            language = options.language
        )
    }

    actual override val isReady: Boolean
        get() = isInitialized && whisperContext != null

    actual override val currentModel: String?
        get() = modelPath?.substringAfterLast("/")?.substringBeforeLast(".")

    override suspend fun cleanup() {
        withContext(Dispatchers.IO) {
            logger.info("Cleaning up Whisper resources")

            try {
                // Free Whisper context
                whisperContext?.let { context ->
                    whisperJNI?.free(context)
                }

                whisperContext = null
                whisperJNI = null
                isInitialized = false
                modelPath = null

            } catch (e: Exception) {
                logger.error("Error during cleanup", e)
            }
        }
    }

    /**
     * Convert byte array (16-bit PCM) to normalized float array
     */
    private fun convertToFloatArray(audioData: ByteArray): FloatArray {
        val floatArray = FloatArray(audioData.size / 2)

        for (i in floatArray.indices) {
            // Convert two bytes to a 16-bit signed integer
            val sample = (audioData[i * 2].toInt() and 0xFF) or
                    (audioData[i * 2 + 1].toInt() shl 8)

            // Convert to signed 16-bit
            val signedSample = if (sample > 32767) sample - 65536 else sample

            // Normalize to [-1.0, 1.0]
            floatArray[i] = signedSample / 32768.0f
        }

        return floatArray
    }

    /**
     * Create Whisper parameters from STT options
     */
    private fun createWhisperParams(options: STTOptions): WhisperFullParams {
        // Create params with GREEDY strategy (better for real-time)
        return WhisperFullParams(WhisperSamplingStrategy.GREEDY).apply {

            // Set number of threads for processing
            nThreads = Runtime.getRuntime().availableProcessors()

            // Set language if specified
            language = when (options.language) {
                "auto" -> null // Let Whisper auto-detect
                else -> options.language
            }

            // Disable translation (we want transcription)
            translate = false

            // Enable timestamps if requested
            printTimestamps = options.enableTimestamps

            // Other useful parameters
            noContext = false // Use context for better accuracy
            singleSegment = false // Allow multiple segments
            printSpecial = false // Don't print special tokens
            printProgress = false // Don't print progress
            printRealtime = false // Don't print realtime

            // Performance settings
            // speedUp is not available in whisper-jni
            audioCtx = 0 // Use default audio context

            // Temperature for sampling (0 = deterministic)
            temperature = 0.0f

            // Beam search parameters (for better accuracy)
            beamSearchBeamSize = 5

            // Suppress blanks
            suppressBlank = true
            suppressNonSpeechTokens = true
        }
    }
}
