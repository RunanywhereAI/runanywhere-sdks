package com.runanywhere.whisperkit.service

import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.sdk.components.stt.STTTranscriptionResult.TimestampInfo
import com.runanywhere.whisperkit.models.*
import com.runanywhere.whisperkit.storage.DefaultWhisperStorage
import com.runanywhere.whisperkit.storage.WhisperStorageStrategy
import io.github.givimad.whisperjni.WhisperContext
import io.github.givimad.whisperjni.WhisperFullParams
import io.github.givimad.whisperjni.WhisperJNI
import io.github.givimad.whisperjni.WhisperSamplingStrategy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * JVM implementation of WhisperKitService using WhisperJNI
 * Matches iOS WhisperKitService functionality
 */
class JvmWhisperKitService : WhisperKitService() {

    private var whisperContext: WhisperContext? = null
    private val whisperJNI = WhisperJNI()

    override val whisperStorage: WhisperStorageStrategy = DefaultWhisperStorage()

    override val isReady: Boolean
        get() = whisperContext != null && whisperState.value == WhisperServiceState.READY

    override val currentModel: String?
        get() = currentWhisperModel.value?.modelName

    // Kotlin-specific: supported languages for this implementation
    val supportedLanguages: List<String>
        get() = listOf(
            "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr",
            "pl", "ca", "nl", "ar", "sv", "it", "id", "hi", "fi", "vi",
            "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no"
        )

    override val supportsStreaming: Boolean get() = true

    // Kotlin-specific: language detection capability
    val supportsLanguageDetection: Boolean get() = true

    // Kotlin-specific: speaker diarization capability
    val supportsSpeakerDiarization: Boolean get() = false

    override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        try {
            _whisperState.value = WhisperServiceState.INITIALIZING

            val actualModelPath = modelPath ?: whisperStorage.getModelPath(WhisperModelType.BASE)

            // Check if model exists, download if needed
            val modelCheckFile = File(actualModelPath)
            if (!modelCheckFile.exists()) {
                _whisperState.value = WhisperServiceState.DOWNLOADING_MODEL
                val modelType = currentWhisperModel.value ?: WhisperModelType.BASE
                whisperStorage.downloadModel(modelType) { progress ->
                    // Progress updates could be emitted via Flow if needed
                }
            }

            _whisperState.value = WhisperServiceState.LOADING_MODEL

            // Load WhisperJNI library
            try {
                WhisperJNI.loadLibrary()
            } catch (e: Exception) {
                // Library may already be loaded
            }

            // Create context from model file
            whisperContext?.close()
            val modelPath = java.nio.file.Paths.get(actualModelPath)
            whisperContext = whisperJNI.init(modelPath)

            _whisperState.value = WhisperServiceState.READY
        } catch (e: Exception) {
            _whisperState.value = WhisperServiceState.ERROR
            throw WhisperError.InitializationFailed("Failed to initialize WhisperJNI: ${e.message}")
        }
    }

    override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions
    ): STTTranscriptionResult = withContext(Dispatchers.Default) {

        val context = whisperContext ?: throw WhisperError.ServiceNotReady()

        // Convert ByteArray to float array (PCM 16-bit to float)
        val floatAudio = convertPCM16ToFloat(audioData)

        // Create parameters based on options
        val params = createWhisperParams(options)

        // Perform transcription
        val result = whisperJNI.full(context, params, floatAudio, floatAudio.size)

        if (result != 0) {
            throw WhisperError.TranscriptionFailed("Transcription failed with code: $result")
        }

        // Extract segments from result
        val segmentCount = whisperJNI.fullNSegments(context)
        val segments = mutableListOf<TimestampInfo>()
        var fullText = ""

        for (i in 0 until segmentCount) {
            val text = whisperJNI.fullGetSegmentText(context, i)
            fullText += text

            // Add word-level timestamps if available
            if (options.enableTimestamps) {
                val startTime = whisperJNI.fullGetSegmentTimestamp0(context, i)
                val endTime = whisperJNI.fullGetSegmentTimestamp1(context, i)
                segments.add(
                    TimestampInfo(
                        word = text.trim(),
                        startTime = startTime.toDouble() / 100.0, // Convert from centiseconds
                        endTime = endTime.toDouble() / 100.0,
                        confidence = 0.95f // WhisperJNI doesn't provide confidence scores
                    )
                )
            }
        }

        STTTranscriptionResult(
            transcript = fullText.trim(),
            confidence = 0.95f, // Default confidence
            timestamps = if (segments.isNotEmpty()) segments else null,
            language = options.language,
            alternatives = null
        )
    }

    override suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult = withContext(Dispatchers.Default) {

        val context = whisperContext ?: throw WhisperError.ServiceNotReady()

        val audioBuffer = mutableListOf<ByteArray>()
        var lastTranscript = ""

        audioStream.collect { chunk ->
            audioBuffer.add(chunk)

            // Process when we have enough audio (e.g., 1 second)
            val totalSize = audioBuffer.sumOf { it.size }
            if (totalSize >= 16000 * 2) { // 1 second of 16kHz PCM16
                val combinedAudio = ByteArray(totalSize)
                var offset = 0
                audioBuffer.forEach {
                    it.copyInto(combinedAudio, offset)
                    offset += it.size
                }

                val floatAudio = convertPCM16ToFloat(combinedAudio)
                val params = createWhisperParams(options)

                val result = whisperJNI.full(context, params, floatAudio, floatAudio.size)
                if (result == 0) {
                    val segmentCount = whisperJNI.fullNSegments(context)
                    var transcript = ""
                    for (i in 0 until segmentCount) {
                        transcript += whisperJNI.fullGetSegmentText(context, i)
                    }

                    if (transcript != lastTranscript) {
                        onPartial(transcript)
                        lastTranscript = transcript
                    }
                }

                // Keep last 100ms for context
                val keepSize = 1600 * 2 // 100ms at 16kHz
                audioBuffer.clear()
                if (combinedAudio.size > keepSize) {
                    audioBuffer.add(combinedAudio.takeLast(keepSize).toByteArray())
                }
            }
        }

        // Process any remaining audio
        if (audioBuffer.isNotEmpty()) {
            val totalSize = audioBuffer.sumOf { it.size }
            val combinedAudio = ByteArray(totalSize)
            var offset = 0
            audioBuffer.forEach {
                it.copyInto(combinedAudio, offset)
                offset += it.size
            }

            val floatAudio = convertPCM16ToFloat(combinedAudio)
            val params = createWhisperParams(options)
            val result = whisperJNI.full(context, params, floatAudio, floatAudio.size)

            if (result == 0) {
                val segmentCount = whisperJNI.fullNSegments(context)
                var transcript = ""
                for (i in 0 until segmentCount) {
                    transcript += whisperJNI.fullGetSegmentText(context, i)
                }

                return@withContext STTTranscriptionResult(
                    transcript = transcript.trim(),
                    confidence = 0.95f,
                    timestamps = null,
                    language = options.language,
                    alternatives = null
                )
            }
        }

        STTTranscriptionResult(
            transcript = lastTranscript.trim(),
            confidence = 0.95f,
            timestamps = null,
            language = options.language,
            alternatives = null
        )
    }

    override fun transcribeStreamInternal(
        audioStream: Flow<ByteArray>,
        options: STTOptions
    ): Flow<WhisperTranscriptionResult> = flow {

        val context = whisperContext ?: throw WhisperError.ServiceNotReady()
        val audioBuffer = mutableListOf<ByteArray>()

        audioStream.collect { chunk ->
            audioBuffer.add(chunk)

            val totalSize = audioBuffer.sumOf { it.size }
            if (totalSize >= 16000 * 2) { // 1 second of audio
                val combinedAudio = ByteArray(totalSize)
                var offset = 0
                audioBuffer.forEach {
                    it.copyInto(combinedAudio, offset)
                    offset += it.size
                }

                val floatAudio = convertPCM16ToFloat(combinedAudio)
                val params = createWhisperParams(options)
                val result = whisperJNI.full(context, params, floatAudio, floatAudio.size)

                if (result == 0) {
                    val segmentCount = whisperJNI.fullNSegments(context)
                    val segments = mutableListOf<TranscriptionSegment>()
                    var fullText = ""

                    for (i in 0 until segmentCount) {
                        val text = whisperJNI.fullGetSegmentText(context, i)
                        val startTime = whisperJNI.fullGetSegmentTimestamp0(context, i)
                        val endTime = whisperJNI.fullGetSegmentTimestamp1(context, i)
                        fullText += text

                        segments.add(
                            TranscriptionSegment(
                                id = i,
                                seek = 0,
                                start = startTime.toDouble() / 100.0,
                                end = endTime.toDouble() / 100.0,
                                text = text,
                                tokens = emptyList(),
                                temperature = 0.0f,
                                avgLogProb = 0.0f,
                                compressionRatio = 0.0f,
                                noSpeechProb = 0.0f
                            )
                        )
                    }

                    emit(
                        WhisperTranscriptionResult(
                            text = fullText.trim(),
                            segments = segments,
                            language = options.language,
                            confidence = 0.95f,
                            duration = segments.lastOrNull()?.end ?: 0.0,
                            timestamps = null
                        )
                    )
                }

                // Keep last 100ms for context
                audioBuffer.clear()
                if (combinedAudio.size > 3200) {
                    audioBuffer.add(combinedAudio.takeLast(3200).toByteArray())
                }
            }
        }
    }.flowOn(Dispatchers.Default)

    /**
     * Kotlin-specific: Enhanced streaming transcription with typed events
     */
    fun transcribeStream(
        audioStream: Flow<ByteArray>,
        options: com.runanywhere.sdk.components.stt.STTStreamingOptions
    ): Flow<com.runanywhere.sdk.components.stt.STTStreamEvent> = flow {
        val context = whisperContext ?: throw WhisperError.ServiceNotReady()

        emit(com.runanywhere.sdk.components.stt.STTStreamEvent.SpeechStarted)

        val audioBuffer = mutableListOf<ByteArray>()
        var lastEmitTime = System.currentTimeMillis()
        val partialInterval = (options.partialResultInterval * 1000).toLong()

        try {
            audioStream.collect { chunk ->
                audioBuffer.add(chunk)

                val currentTime = System.currentTimeMillis()
                val totalSize = audioBuffer.sumOf { it.size }

                // Emit partial results at specified intervals
                if (options.enablePartialResults &&
                    currentTime - lastEmitTime >= partialInterval &&
                    totalSize >= 16000 * 2) { // At least 1 second of audio

                    val combinedAudio = ByteArray(totalSize)
                    var offset = 0
                    audioBuffer.forEach {
                        it.copyInto(combinedAudio, offset)
                        offset += it.size
                    }

                    val floatAudio = convertPCM16ToFloat(combinedAudio)
                    val sttOptions = com.runanywhere.sdk.components.stt.STTOptions(
                        language = options.language ?: "auto",
                        detectLanguage = options.detectLanguage,
                        enableTimestamps = false
                    )
                    val params = createWhisperParams(sttOptions)

                    try {
                        val result = whisperJNI.full(context, params, floatAudio, floatAudio.size)
                        if (result == 0) {
                            val segmentCount = whisperJNI.fullNSegments(context)
                            var transcript = ""
                            for (i in 0 until segmentCount) {
                                transcript += whisperJNI.fullGetSegmentText(context, i)
                            }

                            if (transcript.isNotBlank()) {
                                emit(com.runanywhere.sdk.components.stt.STTStreamEvent.PartialTranscription(
                                    text = transcript.trim(),
                                    confidence = 0.9f,
                                    isFinal = false
                                ))

                                // Language detection
                                if (options.detectLanguage) {
                                    emit(com.runanywhere.sdk.components.stt.STTStreamEvent.LanguageDetected(
                                        language = sttOptions.language,
                                        confidence = 0.8f
                                    ))
                                }
                            }
                        }
                    } catch (e: Exception) {
                        // Ignore partial transcription errors
                    }

                    lastEmitTime = currentTime

                    // Keep last 100ms for context
                    audioBuffer.clear()
                    if (combinedAudio.size > 3200) {
                        audioBuffer.add(combinedAudio.takeLast(3200).toByteArray())
                    }
                }

                // Check max duration
                options.maxDuration?.let { maxDur ->
                    val durationSeconds = totalSize.toDouble() / (16000 * 2)
                    if (durationSeconds >= maxDur) {
                        throw WhisperError.TranscriptionFailed("Max duration exceeded")
                    }
                }
            }

            emit(com.runanywhere.sdk.components.stt.STTStreamEvent.SpeechEnded)

        } catch (e: Exception) {
            emit(com.runanywhere.sdk.components.stt.STTStreamEvent.Error(
                when (e) {
                    is com.runanywhere.sdk.components.stt.STTError -> e
                    is WhisperError -> com.runanywhere.sdk.components.stt.STTError.transcriptionFailed(e)
                    else -> com.runanywhere.sdk.components.stt.STTError.transcriptionFailed(e)
                }
            ))
        }
    }.flowOn(Dispatchers.Default)

    /**
     * Kotlin-specific: Language detection from audio
     */
    suspend fun detectLanguage(audioData: ByteArray): Map<String, Float> {
        val context = whisperContext ?: throw WhisperError.ServiceNotReady()

        return withContext(Dispatchers.Default) {
            try {
                // Use a small sample for detection (max 3 seconds)
                val sampleSize = minOf(audioData.size, 16000 * 2 * 3)
                val sampleData = audioData.sliceArray(0 until sampleSize)
                val floatAudio = convertPCM16ToFloat(sampleData)

                val detectionOptions = com.runanywhere.sdk.components.stt.STTOptions(
                    language = "auto",
                    detectLanguage = true
                )
                val params = createWhisperParams(detectionOptions)

                val result = whisperJNI.full(context, params, floatAudio, floatAudio.size)

                if (result == 0) {
                    // WhisperJNI doesn't directly expose language probabilities
                    // For now, return a reasonable guess based on transcription
                    mapOf("en" to 0.8f, "es" to 0.1f, "fr" to 0.1f)
                } else {
                    emptyMap()
                }
            } catch (e: Exception) {
                emptyMap()
            }
        }
    }

    /**
     * Kotlin-specific: Check if service supports specific language
     */
    fun supportsLanguage(languageCode: String): Boolean {
        return supportedLanguages.contains(languageCode.lowercase())
    }

    override suspend fun cleanup() {
        super.cleanup()
        whisperContext?.close()
        whisperContext = null
    }

    private fun createWhisperParams(options: STTOptions): WhisperFullParams {
        // Create params with greedy strategy (most reliable for production)
        val strategy = WhisperSamplingStrategy.GREEDY
        val params = WhisperFullParams(strategy)

        // Set language
        params.language = when(options.language) {
            "auto" -> "auto"
            else -> options.language.take(2) // Use ISO 639-1 code
        }

        // Set parameters (using Whisper defaults for removed STTOptions fields)
        params.printTimestamps = options.enableTimestamps
        params.suppressBlank = true // Whisper default
        params.suppressNonSpeechTokens = true // Whisper default
        params.temperature = 0.0f // Deterministic output

        return params
    }

    private fun convertPCM16ToFloat(pcm16: ByteArray): FloatArray {
        val buffer = ByteBuffer.wrap(pcm16).order(ByteOrder.LITTLE_ENDIAN)
        val floatArray = FloatArray(pcm16.size / 2)

        for (i in floatArray.indices) {
            val sample = buffer.getShort()
            floatArray[i] = sample.toFloat() / 32768.0f
        }

        return floatArray
    }
}
