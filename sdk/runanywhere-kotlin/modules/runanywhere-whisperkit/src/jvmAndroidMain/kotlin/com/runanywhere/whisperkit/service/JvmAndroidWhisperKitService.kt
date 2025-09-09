package com.runanywhere.whisperkit.service

import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.sdk.components.stt.STTTranscriptionResult.TimestampInfo
import com.runanywhere.whisperkit.models.*
import com.runanywhere.whisperkit.storage.WhisperStorageStrategy
import com.runanywhere.whisperkit.storage.JvmAndroidWhisperStorage
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
 * Shared JVM/Android implementation of WhisperKit service using actual WhisperJNI
 * Both platforms use the same whisper-jni library for real speech transcription
 *
 * This replaces mock implementations with actual WhisperJNI calls
 * to achieve iOS parity for speech-to-text functionality.
 */
class JvmAndroidWhisperKitService : WhisperKitService() {

    private var whisperContext: WhisperContext? = null
    private val whisperJNI = WhisperJNI()

    override val whisperStorage: WhisperStorageStrategy = JvmAndroidWhisperStorage()

    override val isReady: Boolean
        get() = whisperContext != null && whisperState.value == WhisperServiceState.READY

    override val currentModel: String?
        get() = currentWhisperModel.value?.modelName

    override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        try {
            _whisperState.value = WhisperServiceState.INITIALIZING

            val actualModelPath = modelPath ?: whisperStorage.getModelPath(WhisperModelType.BASE)

            // Check if model exists, download if needed
            val modelFile = File(actualModelPath)
            if (!modelFile.exists()) {
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

    override suspend fun <T> streamTranscribe(
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

    override suspend fun cleanup() {
        super.cleanup()
        whisperContext?.close()
        whisperContext = null
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

    private fun createWhisperParams(options: STTOptions): WhisperFullParams {
        // Create params with appropriate strategy based on sensitivity
        val strategy = when (options.sensitivityMode) {
            com.runanywhere.sdk.components.stt.STTSensitivityMode.NORMAL -> WhisperSamplingStrategy.GREEDY
            com.runanywhere.sdk.components.stt.STTSensitivityMode.HIGH,
            com.runanywhere.sdk.components.stt.STTSensitivityMode.MAXIMUM -> WhisperSamplingStrategy.BEAM_SEARCH
        }
        val params = WhisperFullParams(strategy)

        // Set language
        params.language = when(options.language) {
            "auto" -> "auto"
            else -> options.language.take(2) // Use ISO 639-1 code
        }

        // Set other parameters based on STTOptions
        params.printTimestamps = options.enableTimestamps
        params.suppressBlank = options.suppressBlank
        params.suppressNonSpeechTokens = options.suppressNonSpeechTokens

        // Set temperature and beam size based on sensitivity mode
        when (options.sensitivityMode) {
            com.runanywhere.sdk.components.stt.STTSensitivityMode.NORMAL -> {
                params.temperature = 0.0f
            }
            com.runanywhere.sdk.components.stt.STTSensitivityMode.HIGH -> {
                params.temperature = 0.3f
                params.beamSearchBeamSize = 5
            }
            com.runanywhere.sdk.components.stt.STTSensitivityMode.MAXIMUM -> {
                params.temperature = 0.5f
                params.beamSearchBeamSize = 10
            }
        }

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

/**
 * Shared factory for both JVM and Android platforms
 */
actual object WhisperKitFactory {
    actual fun createService(): WhisperKitService {
        return JvmAndroidWhisperKitService()
    }
}
