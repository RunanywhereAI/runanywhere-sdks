package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.components.TTSOptions
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.stt.STTStreamEvent
import com.runanywhere.sdk.components.stt.STTStreamingOptions
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADResult
import com.runanywhere.sdk.components.vad.VADService
import com.runanywhere.sdk.components.vad.SpeechActivityEvent
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking

private val logger = SDKLogger("ONNXServiceProviderImpl")

/**
 * JVM/Android implementation of ONNX STT service creation
 */
actual suspend fun createONNXSTTService(configuration: STTConfiguration): STTService {
    logger.info("Creating ONNX STT service with configuration: ${configuration.modelId}")

    val service = ONNXCoreService()
    service.initialize()

    // Load model if path provided
    configuration.modelId?.let { modelId ->
        // Model loading will be handled by the calling code with full path
        logger.debug("Model ID specified: $modelId - caller should load model")
    }

    return ONNXSTTServiceWrapper(service)
}

/**
 * JVM/Android implementation of ONNX TTS synthesis
 */
actual suspend fun synthesizeWithONNX(text: String, options: TTSOptions): ByteArray {
    logger.info("Synthesizing with ONNX: ${text.take(50)}...")

    val service = ONNXCoreService()
    service.initialize()

    // TTS model should be loaded before synthesis
    val result = service.synthesize(
        text = text,
        voiceId = options.voiceId,
        speedRate = options.rate,
        pitchShift = options.pitch
    )

    // Convert samples to WAV format
    return convertToWav(result.samples, result.sampleRate)
}

/**
 * JVM/Android implementation of ONNX TTS streaming
 */
actual fun synthesizeStreamWithONNX(text: String, options: TTSOptions): Flow<ByteArray> {
    return flow {
        // ONNX TTS doesn't support true streaming, so we return full audio as single chunk
        val audio = synthesizeWithONNX(text, options)
        emit(audio)
    }
}

/**
 * JVM/Android implementation of ONNX VAD service creation
 */
actual suspend fun createONNXVADService(configuration: VADConfiguration): VADService {
    logger.info("Creating ONNX VAD service")

    val service = ONNXCoreService()
    service.initialize()

    // Load VAD model if path provided
    configuration.modelId?.let { modelId ->
        service.loadVADModel(modelId)
    }

    return ONNXVADServiceWrapper(service, configuration)
}

/**
 * Create ONNX STT service from model path (for ONNXAdapter)
 */
actual suspend fun createONNXSTTServiceFromPath(modelPath: String): Any {
    logger.info("Creating ONNX STT service from path: $modelPath")

    val service = ONNXCoreService()
    service.initialize()

    // Detect model type from path
    val modelType = detectSTTModelType(modelPath)
    service.loadSTTModel(modelPath, modelType)

    return ONNXSTTServiceWrapper(service)
}

/**
 * Create ONNX TTS service from model path (for ONNXAdapter)
 */
actual suspend fun createONNXTTSServiceFromPath(modelPath: String): Any {
    logger.info("Creating ONNX TTS service from path: $modelPath")

    val service = ONNXCoreService()
    service.initialize()
    service.loadTTSModel(modelPath, "vits")

    return ONNXTTSServiceWrapper(service)
}

// MARK: - Service Wrappers

/**
 * Wrapper for ONNX STT Service implementing STTService interface
 */
private class ONNXSTTServiceWrapper(
    private val coreService: ONNXCoreService
) : STTService {

    override val isReady: Boolean
        get() = coreService.isInitialized && coreService.isSTTModelLoaded

    override val currentModel: String? = null

    override val supportsStreaming: Boolean
        get() = coreService.supportsSTTStreaming

    override val supportedLanguages: List<String> = listOf("en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko")

    override suspend fun initialize(modelPath: String?) {
        modelPath?.let { path ->
            val modelType = detectSTTModelType(path)
            coreService.loadSTTModel(path, modelType)
        }
    }

    override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions
    ): STTTranscriptionResult {
        val samples = convertToFloat32Samples(audioData)
        val transcript = coreService.transcribe(samples, 16000, options.language)

        return STTTranscriptionResult(
            transcript = transcript,
            confidence = 1.0f,
            language = options.language
        )
    }

    override suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult {
        // Collect all audio chunks and transcribe
        val audioChunks = mutableListOf<ByteArray>()
        audioStream.collect { chunk ->
            audioChunks.add(chunk)
            // Emit partial result (placeholder)
            onPartial("...")
        }

        // Combine all chunks and transcribe
        val combinedAudio = audioChunks.fold(byteArrayOf()) { acc, chunk -> acc + chunk }
        return transcribe(combinedAudio, options)
    }

    override fun transcribeStream(
        audioStream: Flow<ByteArray>,
        options: STTStreamingOptions
    ): Flow<STTStreamEvent> {
        return flow {
            emit(STTStreamEvent.SpeechStarted)

            val audioChunks = mutableListOf<ByteArray>()
            audioStream.collect { chunk ->
                audioChunks.add(chunk)
                // Emit partial transcription placeholder
                emit(STTStreamEvent.PartialTranscription(text = "...", confidence = 0.5f))
            }

            // Combine all chunks and transcribe
            val combinedAudio = audioChunks.fold(byteArrayOf()) { acc, chunk -> acc + chunk }
            val defaultOptions = STTOptions(language = options.language ?: "en")
            val result = transcribe(combinedAudio, defaultOptions)

            emit(STTStreamEvent.FinalTranscription(result))
            emit(STTStreamEvent.SpeechEnded)
        }
    }

    override suspend fun detectLanguage(audioData: ByteArray): Map<String, Float> {
        // ONNX doesn't support standalone language detection - return default
        return mapOf("en" to 1.0f)
    }

    override fun supportsLanguage(languageCode: String): Boolean {
        return supportedLanguages.contains(languageCode.lowercase().take(2))
    }

    override suspend fun cleanup() {
        coreService.unloadSTTModel()
    }
}

/**
 * Wrapper for ONNX TTS Service
 */
private class ONNXTTSServiceWrapper(
    private val coreService: ONNXCoreService
) {
    val isReady: Boolean
        get() = coreService.isInitialized && coreService.isTTSModelLoaded

    suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        val result = coreService.synthesize(
            text = text,
            voiceId = options.voiceId,
            speedRate = options.rate,
            pitchShift = options.pitch
        )
        return convertToWav(result.samples, result.sampleRate)
    }

    suspend fun cleanup() {
        coreService.unloadTTSModel()
    }
}

/**
 * Wrapper for ONNX VAD Service implementing VADService interface
 */
private class ONNXVADServiceWrapper(
    private val coreService: ONNXCoreService,
    private val initialConfiguration: VADConfiguration
) : VADService {

    // VADService properties
    override var energyThreshold: Float = initialConfiguration.energyThreshold
    override val sampleRate: Int = initialConfiguration.sampleRate
    override val frameLength: Float = initialConfiguration.frameLength
    override var isSpeechActive: Boolean = false
        private set

    override var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null
    override var onAudioBuffer: ((ByteArray) -> Unit)? = null

    override val isReady: Boolean
        get() = coreService.isInitialized && coreService.isVADModelLoaded

    override val configuration: VADConfiguration
        get() = initialConfiguration

    override suspend fun initialize(configuration: VADConfiguration) {
        energyThreshold = configuration.energyThreshold
        // Load VAD model if path provided through model ID
        configuration.modelId?.let { modelId ->
            coreService.loadVADModel(modelId)
        }
    }

    override fun start() {
        // ONNX VAD doesn't require explicit start
    }

    override fun stop() {
        // ONNX VAD doesn't require explicit stop
    }

    override fun reset() {
        isSpeechActive = false
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        // Use runBlocking since processVAD is suspend but this isn't
        val result = runBlocking { coreService.processVAD(audioSamples, sampleRate) }
        val wasActive = isSpeechActive
        isSpeechActive = result.isSpeech

        // Fire callbacks on state change
        if (isSpeechActive && !wasActive) {
            onSpeechActivity?.invoke(SpeechActivityEvent.STARTED)
        } else if (!isSpeechActive && wasActive) {
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }

        return VADResult(
            isSpeechDetected = result.isSpeech,
            confidence = result.probability
        )
    }

    override fun processAudioData(audioData: FloatArray): Boolean {
        return processAudioChunk(audioData).isSpeechDetected
    }

    override suspend fun cleanup() {
        coreService.unloadVADModel()
    }
}

// MARK: - Helper Functions

/**
 * Detect STT model type from path
 */
private fun detectSTTModelType(modelPath: String): String {
    val lowercased = modelPath.lowercase()
    return when {
        lowercased.contains("zipformer") -> "zipformer"
        lowercased.contains("whisper") -> "whisper"
        lowercased.contains("paraformer") -> "paraformer"
        lowercased.contains("sherpa") -> "zipformer" // Default for sherpa-onnx
        else -> "zipformer" // Default
    }
}

/**
 * Convert byte array to float32 samples
 */
private fun convertToFloat32Samples(audioData: ByteArray): FloatArray {
    // Assuming 16-bit PCM input
    val samples = FloatArray(audioData.size / 2)
    for (i in samples.indices) {
        val low = audioData[i * 2].toInt() and 0xFF
        val high = audioData[i * 2 + 1].toInt()
        val sample = (high shl 8) or low
        samples[i] = sample / 32768.0f
    }
    return samples
}

/**
 * Convert float samples to WAV byte array
 */
private fun convertToWav(samples: FloatArray, sampleRate: Int): ByteArray {
    val numSamples = samples.size
    val numChannels = 1
    val bitsPerSample = 16
    val byteRate = sampleRate * numChannels * bitsPerSample / 8
    val blockAlign = numChannels * bitsPerSample / 8
    val dataSize = numSamples * blockAlign
    val fileSize = 36 + dataSize

    val buffer = ByteArray(44 + dataSize)
    var offset = 0

    // RIFF header
    "RIFF".toByteArray().copyInto(buffer, offset); offset += 4
    writeInt32LE(buffer, offset, fileSize); offset += 4
    "WAVE".toByteArray().copyInto(buffer, offset); offset += 4

    // fmt chunk
    "fmt ".toByteArray().copyInto(buffer, offset); offset += 4
    writeInt32LE(buffer, offset, 16); offset += 4  // Chunk size
    writeInt16LE(buffer, offset, 1); offset += 2   // PCM format
    writeInt16LE(buffer, offset, numChannels); offset += 2
    writeInt32LE(buffer, offset, sampleRate); offset += 4
    writeInt32LE(buffer, offset, byteRate); offset += 4
    writeInt16LE(buffer, offset, blockAlign); offset += 2
    writeInt16LE(buffer, offset, bitsPerSample); offset += 2

    // data chunk
    "data".toByteArray().copyInto(buffer, offset); offset += 4
    writeInt32LE(buffer, offset, dataSize); offset += 4

    // Write samples
    for (sample in samples) {
        val intSample = (sample * 32767).toInt().coerceIn(-32768, 32767)
        writeInt16LE(buffer, offset, intSample)
        offset += 2
    }

    return buffer
}

private fun writeInt16LE(buffer: ByteArray, offset: Int, value: Int) {
    buffer[offset] = (value and 0xFF).toByte()
    buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
}

private fun writeInt32LE(buffer: ByteArray, offset: Int, value: Int) {
    buffer[offset] = (value and 0xFF).toByte()
    buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
    buffer[offset + 2] = ((value shr 16) and 0xFF).toByte()
    buffer[offset + 3] = ((value shr 24) and 0xFF).toByte()
}
