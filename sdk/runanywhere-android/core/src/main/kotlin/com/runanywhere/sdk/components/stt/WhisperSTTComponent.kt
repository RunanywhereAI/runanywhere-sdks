package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.models.WhisperModel
import io.github.givimad.whisperjni.WhisperJNI
import io.github.givimad.whisperjni.WhisperContext
import io.github.givimad.whisperjni.WhisperFullParams
import io.github.givimad.whisperjni.WhisperSamplingStrategy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Path
import java.nio.file.Paths

/**
 * STT Configuration for Whisper
 */
data class WhisperSTTConfig(
    val modelType: WhisperModel.ModelType = WhisperModel.ModelType.TINY,
    val language: String? = null, // null = auto-detect
    val translate: Boolean = false, // Translate to English
    val nThreads: Int = 4,
    val maxSegmentLength: Int = 0, // 0 = no limit
    val suppressBlank: Boolean = true,
    val suppressNonSpeechTokens: Boolean = true,
    val temperature: Float = 0.0f,
    val beamSize: Int = 5, // For beam search
    val patience: Float = -1.0f // For beam search
) : ComponentConfig

/**
 * Whisper STT Component implementation using whisper-jni
 */
class WhisperSTTComponent : STTService {
    private var whisper: WhisperJNI? = null
    private var context: WhisperContext? = null
    private var config: WhisperSTTConfig? = null
    private var modelPath: String? = null

    companion object {
        init {
            try {
                // Initialize whisper-jni library
                WhisperJNI.loadLibrary()
                WhisperJNI.setLibraryLogger(null) // Disable native logging
            } catch (e: Exception) {
                println("Failed to load Whisper JNI library: ${e.message}")
            }
        }
    }

    override val isReady: Boolean
        get() = modelPath != null && context != null

    override val currentModel: String?
        get() = config?.modelType?.name

    override suspend fun initialize(modelPath: String?) {
        if (modelPath == null) {
            throw SDKError.ModelNotFound("Model path is required")
        }

        // Ensure model is available and load it
        val actualPath = modelPath
        this.modelPath = actualPath

        withContext(Dispatchers.IO) {
            whisper = WhisperJNI()
        }
        config = WhisperSTTConfig()
        loadModel()
    }

    override suspend fun loadModel() {
        withContext(Dispatchers.IO) {
            val path = modelPath ?: throw IllegalStateException("Model path not set")
            val modelFile = Paths.get(path)

            // Initialize whisper context with the model
            context = whisper?.init(modelFile)
                ?: throw IllegalStateException("Failed to initialize Whisper context")
        }
    }

    override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions
    ): STTTranscriptionResult {
        require(modelPath != null && context != null) { "Model not loaded" }
        val cfg = config ?: throw IllegalStateException("Component not initialized")

        val audio = audioData.map { it.toFloat() }.toFloatArray()
        val result = withContext(Dispatchers.IO) {
            val ctx = context ?: throw IllegalStateException("Model not loaded")
            val whisperInstance = whisper ?: throw IllegalStateException("Whisper not initialized")

            // Create parameters for transcription
            val params = WhisperFullParams().apply {
                strategy = WhisperSamplingStrategy.WHISPER_SAMPLING_BEAM_SEARCH
                nThreads = cfg.nThreads
                language = cfg.language
                translate = cfg.translate
                suppressBlank = cfg.suppressBlank
                suppressNonSpeechTokens = cfg.suppressNonSpeechTokens
                temperature = cfg.temperature
                beamSearchBeamSize = cfg.beamSize
                beamSearchPatience = cfg.patience
                noContext = false
                singleSegment = false
                printSpecial = false
                printProgress = false
                printRealtime = false
                printTimestamps = false
            }

            // Run transcription
            val result = whisperInstance.full(ctx, params, audio, audio.size)

            if (result != 0) {
                return@withContext STTTranscriptionResult(
                    transcript = "",
                    confidence = 0f,
                    timestamp = System.currentTimeMillis(),
                    segments = emptyList(),
                    error = "Transcription failed with code: $result"
                )
            }

            // Extract segments
            val numSegments = whisperInstance.fullNSegments(ctx)
            val segments = mutableListOf<STTTranscriptionSegment>()
            var fullText = StringBuilder()

            for (i in 0 until numSegments) {
                val text = whisperInstance.fullGetSegmentText(ctx, i)
                val startTime = whisperInstance.fullGetSegmentTimestamp0(ctx, i)
                val endTime = whisperInstance.fullGetSegmentTimestamp1(ctx, i)

                segments.add(
                    STTTranscriptionSegment(
                        text = text,
                        startTime = startTime * 10, // Convert to milliseconds
                        endTime = endTime * 10,
                        confidence = 0.95f // Whisper doesn't provide per-segment confidence
                    )
                )
                fullText.append(text)
            }

            STTTranscriptionResult(
                transcript = fullText.toString().trim(),
                confidence = 0.95f, // Whisper doesn't provide overall confidence
                timestamp = System.currentTimeMillis(),
                segments = segments
            )
        }
        return result
    }

    override suspend fun <T> streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult {
        require(modelPath != null && context != null) { "Model not loaded" }

        val fullText = StringBuilder()

        audioStream.collect { chunk ->
            val partial = withContext(Dispatchers.IO) {
                val audio = chunk.map { it.toFloat() }.toFloatArray()
                val ctx = context ?: throw IllegalStateException("Model not loaded")
                val whisperInstance =
                    whisper ?: throw IllegalStateException("Whisper not initialized")

                // Create parameters for transcription
                val params = WhisperFullParams().apply {
                    strategy = WhisperSamplingStrategy.WHISPER_SAMPLING_BEAM_SEARCH
                    nThreads = 4
                    language = null
                    translate = false
                    suppressBlank = true
                    suppressNonSpeechTokens = true
                    temperature = 0.0f
                    beamSearchBeamSize = 5
                    beamSearchPatience = -1.0f
                    noContext = false
                    singleSegment = false
                    printSpecial = false
                    printProgress = false
                    printRealtime = false
                    printTimestamps = false
                }

                // Run transcription
                val result = whisperInstance.full(ctx, params, audio, audio.size)

                if (result != 0) {
                    return@withContext ""
                }

                // Extract segments
                val numSegments = whisperInstance.fullNSegments(ctx)
                var partialText = StringBuilder()

                for (i in 0 until numSegments) {
                    val text = whisperInstance.fullGetSegmentText(ctx, i)
                    partialText.append(text)
                }

                partialText.toString().trim()
            }
            onPartial(partial)
            fullText.append(partial).append(" ")
        }

        return STTTranscriptionResult(
            transcript = fullText.toString().trim(),
            confidence = 0.95f,
            language = options.language
        )
    }

    override suspend fun cleanup() {
        unloadModel()
        withContext(Dispatchers.IO) {
            whisper = null
        }
    }

    override suspend fun unloadModel() {
        withContext(Dispatchers.IO) {
            context?.let { ctx ->
                whisper?.free(ctx)
                context = null
            }
        }
    }
}
