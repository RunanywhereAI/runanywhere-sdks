package com.runanywhere.sdk.public

import android.annotation.SuppressLint
import android.content.Context
import com.runanywhere.sdk.audio.AndroidAudioCapture
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTStreamEvent
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelStorage
import com.runanywhere.sdk.models.ModelDownloader
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.last
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * Android implementation of RunAnywhere SDK
 * Simplified version using platform abstractions
 */
@SuppressLint("StaticFieldLeak") // TODO: double check this later
actual object RunAnywhere : BaseRunAnywhereSDK() {

    private val androidLogger = SDKLogger("RunAnywhere.Android")
    private lateinit var modelDownloader: ModelDownloader
    private var sttComponent: STTComponent? = null
    private var vadComponent: VADComponent? = null
    private val modelStorage by lazy { ModelStorage() }
    private var audioCapture: AndroidAudioCapture? = null

    // SDK's own coroutine scope for background operations
    private val sdkScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // For simple recording mode - accumulate audio while recording
    private val recordingBuffer = ByteArrayOutputStream()
    private var isRecording = false
    private var recordingJob: Job? = null

    // Store the Android context
    private var androidContext: Context? = null

    // Device ID storage key
    private const val DEVICE_ID_KEY = "com.runanywhere.sdk.deviceId"

    // MARK: - Device Registration Storage (Platform-Specific)

    override suspend fun getStoredDeviceId(): String? {
        androidLogger.debug("Getting stored device ID from secure storage")
        return try {
            val secureStorage = com.runanywhere.sdk.storage.createSecureStorage()
            val deviceId = secureStorage.getSecureString(DEVICE_ID_KEY)
            if (!deviceId.isNullOrEmpty()) {
                androidLogger.debug("Found stored device ID: ${deviceId.take(8)}...")
            }
            deviceId
        } catch (e: Exception) {
            androidLogger.warn("Failed to get stored device ID: ${e.message}")
            null
        }
    }

    override suspend fun storeDeviceId(deviceId: String) {
        androidLogger.debug("Storing device ID in secure storage")
        try {
            val secureStorage = com.runanywhere.sdk.storage.createSecureStorage()
            secureStorage.setSecureString(DEVICE_ID_KEY, deviceId)
            androidLogger.info("Device ID stored successfully")
        } catch (e: Exception) {
            androidLogger.error("Failed to store device ID: ${e.message}")
            throw com.runanywhere.sdk.data.models.SDKError.StorageError("Failed to store device ID: ${e.message}")
        }
    }

    override fun generateDeviceIdentifier(): String {
        // Use Java UUID for device identifier (same as JVM)
        return java.util.UUID.randomUUID().toString()
    }

    /**
     * Android-specific initialization with Context
     */
    suspend fun initialize(
        context: Context,
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    ) {
        androidContext = context.applicationContext
        initialize(apiKey, baseURL, environment)
    }

    override suspend fun storeCredentialsSecurely(params: SDKInitParams) {
        val context = androidContext ?: throw IllegalStateException(
            "Android context not provided. Use RunAnywhere.initialize(context, ...) on Android"
        )

        // Android uses EncryptedSharedPreferences for secure storage
        androidLogger.info("Storing credentials in Android secure storage")

        // Initialize AndroidPlatformContext if not already done
        if (!com.runanywhere.sdk.storage.AndroidPlatformContext.isInitialized()) {
            com.runanywhere.sdk.storage.AndroidPlatformContext.initialize(context)
        }

        // Store API key securely
        val secureStorage = com.runanywhere.sdk.storage.createSecureStorage()
        secureStorage.setSecureString("com.runanywhere.sdk.apiKey", params.apiKey)
    }

    override suspend fun initializeDatabase() {
        val context = androidContext ?: throw IllegalStateException(
            "Android context not provided. Use RunAnywhere.initialize(context, ...) on Android"
        )

        // Android uses Room database (local only, no network)
        androidLogger.info("Initializing local database for Android")

        // Initialize audio capture with context
        audioCapture = AndroidAudioCapture(context)

        // Initialize Android-specific services
        val platformContext = com.runanywhere.sdk.foundation.PlatformContext(context)
        val apiKey = _initParams?.apiKey
        val baseURL = _initParams?.baseURL
        ServiceContainer.shared.initialize(platformContext, currentEnvironment, apiKey, baseURL)

        androidLogger.info("ServiceContainer initialized with environment: $currentEnvironment")
    }

    // These methods are no longer called during initialization (Phase 1)
    // They're kept for backward compatibility but are now unused
    // Authentication and device registration happen lazily via ensureDeviceRegistered()

    override suspend fun authenticateWithBackend(params: SDKInitParams) {
        // This method is no longer called during initialization
        // Authentication happens lazily during ensureDeviceRegistered()
        androidLogger.debug("authenticateWithBackend() called (unused in Phase 1)")
    }

    override suspend fun performHealthCheck() {
        // This method is no longer called during initialization
        // Health check is optional and can be done after initialization
        androidLogger.debug("performHealthCheck() called (unused in Phase 1)")
    }

    override suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return serviceContainer.modelInfoService.getAllModels()
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()
        val modelInfo = serviceContainer.modelInfoService.getModel(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        // Use downloadModelStream which returns a Flow<DownloadProgress>
        return serviceContainer.downloadService.downloadModelStream(modelInfo).map { progress ->
            progress.percentage.toFloat()
        }
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()

        // Get the STT component from the service container
        val sttComponent = serviceContainer.sttComponent

        // Perform transcription using STTComponent
        val result = sttComponent.transcribe(
            audioData = audioData,
            format = com.runanywhere.sdk.components.stt.AudioFormat.WAV,
            language = "en"
        )

        return result.text
    }

    override suspend fun loadModel(modelId: String): Boolean {
        requireInitialized()

        androidLogger.info("Loading model: $modelId")

        // Check if model is downloaded
        val model = serviceContainer.modelInfoService.getModel(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        if (model.localPath == null) {
            androidLogger.warn("Model $modelId not downloaded. Download it first.")
            return false
        }

        // Load model into memory using ModelManager
        return try {
            serviceContainer.modelManager.loadModel(model)
            androidLogger.info("Model $modelId loaded successfully")
            true
        } catch (e: Exception) {
            androidLogger.error("Failed to load model $modelId: ${e.message}")
            false
        }
    }

    override suspend fun generate(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): String {
        requireInitialized()

        androidLogger.info("Generating response for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions = com.runanywhere.sdk.generation.GenerationOptions(
            model = null, // Model will be auto-selected
            temperature = options?.temperature ?: 0.7f,
            maxTokens = options?.maxTokens ?: 100,
            stopSequences = options?.stopSequences ?: emptyList()
        )

        // Use generation service from service container
        val result = serviceContainer.generationService.generate(prompt, generationOptions)

        androidLogger.info("Generated response: ${result.text.take(50)}...")
        return result.text
    }

    override fun generateStream(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): Flow<String> {
        requireInitialized()

        androidLogger.info("Starting streaming generation for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions = com.runanywhere.sdk.generation.GenerationOptions(
            model = null, // Model will be auto-selected
            temperature = options?.temperature ?: 0.7f,
            maxTokens = options?.maxTokens ?: 100,
            stopSequences = options?.stopSequences ?: emptyList()
        )

        // Use streaming service from service container
        return serviceContainer.streamingService.stream(prompt, generationOptions)
            .map { chunk -> chunk.text }
    }

    // MARK: - Audio and STT Methods

    override fun transcribeStream(
        audioStream: Flow<ByteArray>,
        chunkSizeMs: Int
    ): Flow<STTStreamEvent> {
        requireInitialized()

        androidLogger.info("Starting streaming transcription")

        return flow {
            audioStream.collect { audioChunk ->
                val result = transcribe(audioChunk)
                val transcriptionResult = STTTranscriptionResult(
                    transcript = result,
                    confidence = 1.0f
                )
                emit(STTStreamEvent.FinalTranscription(transcriptionResult))
            }
        }.catch { e ->
            androidLogger.error("Error in streaming transcription", e)
            throw e
        }
    }

    override suspend fun transcribeWithRecording(durationSeconds: Int): String {
        requireInitialized()

        androidLogger.info("Recording audio for $durationSeconds seconds and transcribing...")

        val audioCapture =
            this.audioCapture ?: throw IllegalStateException("Audio capture not initialized")

        // Record audio for the specified duration
        val audioData = audioCapture.recordAudio(durationSeconds * 1000L)

        androidLogger.info("Recorded ${audioData.size} bytes of audio, transcribing...")

        // Transcribe the recorded audio
        return transcribe(audioData)
    }

    fun startRecordingWithWaveform(): Flow<STTStreamEvent.AudioLevelChanged> = flow {
        requireInitialized()

        val audioCapture = this@RunAnywhere.audioCapture
            ?: throw IllegalStateException("Audio capture not initialized")

        androidLogger.info("Starting audio recording with waveform")

        try {
            // Start continuous audio capture
            val audioChunkFlow = audioCapture.startContinuousCapture()

            // Buffer for accumulating audio for transcription
            val audioBuffer = mutableListOf<Float>()
            var chunkCount = 0

            audioChunkFlow.collect { chunk ->
                // Calculate RMS for waveform
                val rms = chunk.samples.map { it * it }.average().toFloat()
                val decibelLevel = if (rms > 0) {
                    20 * kotlin.math.log10(rms.toDouble()).toFloat()
                } else {
                    -80f // Silence threshold
                }

                // Emit audio level for waveform
                emit(
                    STTStreamEvent.AudioLevelChanged(
                        decibelLevel,
                        System.currentTimeMillis() / 1000.0
                    )
                )

                // Accumulate audio samples for transcription
                audioBuffer.addAll(chunk.samples.toList())
                chunkCount++

                // Process transcription every ~0.5 seconds (5 chunks of 100ms each)
                if (chunkCount >= 5) {
                    try {
                        // Convert accumulated samples to PCM bytes
                        val pcmBytes = convertFloatSamplesToPCM(audioBuffer.toFloatArray())

                        if (pcmBytes.isNotEmpty()) {
                            // Perform transcription
                            val transcription = transcribe(pcmBytes)

                            if (transcription.isNotBlank()) {
                                // Emit transcription result (placeholder)
                                androidLogger.debug("Transcription: $transcription")
                            }
                        }

                        // Clear buffer for next batch
                        audioBuffer.clear()
                        chunkCount = 0

                    } catch (e: Exception) {
                        androidLogger.error("Error processing audio chunk", e)
                    }
                }
            }

        } catch (e: Exception) {
            androidLogger.error("Error in audio recording with waveform", e)
            throw e
        } finally {
            audioCapture.stopCapture()
            androidLogger.info("Audio capture stopped")
        }
    }

    /**
     * Stop streaming transcription
     */
    override fun stopStreamingTranscription() {
        androidLogger.info("Stopping streaming transcription")
        audioCapture?.stopCapture()
    }

    // MARK: - Simple Recording Mode for Basic Use Cases

    /**
     * Start simple recording mode (accumulates audio for later transcription)
     */
    fun startRecording() {
        if (isRecording) {
            androidLogger.warn("Recording already in progress")
            return
        }

        val audioCapture =
            this.audioCapture ?: throw IllegalStateException("Audio capture not initialized")

        androidLogger.info("Starting audio recording...")
        recordingBuffer.reset()

        // Start capturing audio into the buffer
        recordingJob = sdkScope.launch {
            try {
                audioCapture.startContinuousCapture()
                    .collect { chunk ->
                        if (isRecording) {
                            // Convert float samples back to PCM bytes for the buffer
                            val pcmBytes = convertFloatSamplesToPCM(chunk.samples)
                            recordingBuffer.write(pcmBytes)
                        }
                    }
            } catch (e: Exception) {
                androidLogger.error("Error during recording", e)
            }
        }

        isRecording = true
        androidLogger.info("Recording started")
    }

    /**
     * Start recording and transcription in one go
     */
    fun startRecordingWithTranscription(): Flow<String> = flow {
        if (isRecording) {
            throw IllegalStateException("Recording already in progress")
        }

        val audioCapture = this@RunAnywhere.audioCapture
            ?: throw IllegalStateException("Audio capture not initialized")

        androidLogger.info("Starting audio recording with live transcription...")
        isRecording = true

        try {
            audioCapture.startContinuousCapture()
                .collect { chunk ->
                    if (isRecording) {
                        // Store audio for final transcription
                        val pcmBytes = convertFloatSamplesToPCM(chunk.samples)
                        recordingBuffer.write(pcmBytes)

                        // Emit partial transcription placeholder
                        emit("Recording... (${recordingBuffer.size()} bytes)")
                    }
                }
        } catch (e: Exception) {
            androidLogger.error("Error during recording with transcription", e)
            throw e
        }
    }

    /**
     * Stop recording and return transcribed text
     */
    suspend fun stopRecordingAndTranscribe(): String {
        if (!isRecording) {
            androidLogger.warn("No recording in progress")
            return ""
        }

        androidLogger.info("Stopping recording and transcribing...")
        isRecording = false

        // Stop the recording job
        recordingJob?.cancel()
        recordingJob = null
        audioCapture?.stopCapture()

        // Get the recorded audio
        val audioData = recordingBuffer.toByteArray()
        recordingBuffer.reset()

        if (audioData.isEmpty()) {
            androidLogger.warn("No audio data recorded")
            return ""
        }

        androidLogger.info("Recorded ${audioData.size} bytes, transcribing...")

        // Transcribe the recorded audio
        return transcribe(audioData)
    }

    /**
     * Convert float samples to PCM bytes (16-bit little-endian)
     */
    private fun convertFloatSamplesToPCM(samples: FloatArray): ByteArray {
        val pcmBytes = ByteArray(samples.size * 2)

        for (i in samples.indices) {
            // Convert float [-1.0, 1.0] to 16-bit signed integer
            val sample16 = (samples[i] * 32767.0f).toInt().coerceIn(-32768, 32767)

            // Store as little-endian bytes
            pcmBytes[i * 2] = (sample16 and 0xFF).toByte()
            pcmBytes[i * 2 + 1] = ((sample16 shr 8) and 0xFF).toByte()
        }

        return pcmBytes
    }

    override suspend fun cleanupPlatform() {
        // Stop any ongoing recording
        if (isRecording) {
            isRecording = false
            recordingJob?.cancel()
            audioCapture?.stopCapture()
        }

        // Cleanup audio resources
        audioCapture = null

        // Cancel SDK scope
        sdkScope.cancel()

        // Cleanup Android-specific resources
        ServiceContainer.shared.cleanup()
        androidContext = null
    }
}
