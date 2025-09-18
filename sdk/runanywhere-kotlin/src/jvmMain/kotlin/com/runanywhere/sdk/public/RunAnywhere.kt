package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTStreamEvent
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.JvmModelStorage
import com.runanywhere.sdk.models.JvmWhisperJNIModelMapper
import com.runanywhere.sdk.models.ModelDownloader
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.last
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import java.io.ByteArrayOutputStream

/**
 * JVM implementation of RunAnywhere SDK
 * Simplified version using platform abstractions
 */
actual object RunAnywhere : BaseRunAnywhereSDK() {

    private val jvmLogger = SDKLogger("RunAnywhere.JVM")
    private lateinit var modelDownloader: ModelDownloader
    private var sttComponent: STTComponent? = null
    private var vadComponent: VADComponent? = null
    private val modelStorage = JvmModelStorage()
    private val audioCapture = com.runanywhere.sdk.audio.JvmAudioCapture()

    // SDK's own coroutine scope for background operations
    private val sdkScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // For simple recording mode - accumulate audio while recording
    private val recordingBuffer = ByteArrayOutputStream()
    private var isRecording = false
    private var recordingJob: Job? = null

    // Default model for v0.1 release
    private val DEFAULT_MODEL = "whisper-base"

    override suspend fun storeCredentialsSecurely(params: SDKInitParams) {
        // JVM uses encrypted file-based storage with JvmSecureStorage
        jvmLogger.info("Storing credentials securely (JVM)")

        try {
            val secureStorage = com.runanywhere.sdk.storage.createSecureStorage()
            secureStorage.setSecureString("com.runanywhere.sdk.apiKey", params.apiKey)

            params.baseURL?.let { baseURL ->
                secureStorage.setSecureString("com.runanywhere.sdk.baseURL", baseURL)
            }

            secureStorage.setSecureString("com.runanywhere.sdk.environment", params.environment.name)

            jvmLogger.info("Credentials stored securely in encrypted storage")
        } catch (e: Exception) {
            jvmLogger.error("Failed to store credentials securely: ${e.message}")
            throw e
        }
    }

    override suspend fun initializeDatabase() {
        // JVM uses file-based database and secure storage
        jvmLogger.info("Initializing secure storage and database for JVM")

        try {
            // 1. Create secure storage
            val secureStorage = com.runanywhere.sdk.storage.createSecureStorage()
            jvmLogger.info("JvmSecureStorage created successfully")

            // 2. Create network service with OkHttpEngine
            val networkConfig = com.runanywhere.sdk.network.NetworkConfiguration.production()
            val httpClient = com.runanywhere.sdk.network.createHttpClient(networkConfig)
            jvmLogger.info("OkHttpEngine created with production configuration")

            // 3. Initialize ServiceContainer with platform context, environment, and API key
            val platformContext = com.runanywhere.sdk.foundation.PlatformContext()
            // Get the API key from stored params (set during initialize call)
            val apiKey = _initParams?.apiKey
            val baseURL = _initParams?.baseURL
            serviceContainer.initialize(platformContext, currentEnvironment, apiKey, baseURL)

            jvmLogger.info("ServiceContainer initialized with environment: $currentEnvironment")
        } catch (e: Exception) {
            jvmLogger.error("Failed to initialize database and storage: ${e.message}")
            throw e
        }
    }

    override suspend fun authenticateWithBackend(params: SDKInitParams) {
        // Skip authentication in development mode
        if (currentEnvironment == com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT) {
            jvmLogger.info("Skipping authentication in development mode")
            return
        }

        jvmLogger.info("Authenticating with backend API")

        try {
            // 1. Validate API key
            if (params.apiKey.isEmpty()) {
                throw IllegalArgumentException("API key cannot be empty")
            }

            // 2. Create secure storage and network service
            val secureStorage = com.runanywhere.sdk.storage.createSecureStorage()
            val networkConfig = com.runanywhere.sdk.network.NetworkConfiguration.production()
            val httpClient = com.runanywhere.sdk.network.createHttpClient(networkConfig)

            // 3. Create authentication service
            val authService = com.runanywhere.sdk.services.AuthenticationService(secureStorage, httpClient)

            // 4. Authenticate with API key
            val authResponse = authService.authenticate(params.apiKey)
            jvmLogger.info("Authentication successful - deviceId: ${authResponse.deviceId}")

            // 5. Load any existing tokens from storage
            authService.loadStoredTokens()

            // 6. Get/generate persistent device ID
            val deviceId = com.runanywhere.sdk.foundation.PersistentDeviceIdentity.getPersistentDeviceUUID()
            jvmLogger.info("Device ID: $deviceId")

            // 7. Create and use DeviceRegistrationService to register device if needed
            val networkService = com.runanywhere.sdk.data.network.NetworkServiceFactory.create(
                environment = currentEnvironment,
                baseURL = params.baseURL,
                apiKey = params.apiKey,
                authenticationService = authService  // Pass the auth service for token management
            )

            val deviceRegistrationService = com.runanywhere.sdk.services.DeviceRegistrationService(networkService)

            if (!deviceRegistrationService.isDeviceRegistered()) {
                jvmLogger.info("Device not registered, performing registration...")
                val registrationResult = deviceRegistrationService.registerDevice()

                registrationResult.fold(
                    onSuccess = { response ->
                        jvmLogger.info("Device registration successful: ${response.message}")
                    },
                    onFailure = { error ->
                        jvmLogger.warn("Device registration failed (optional): ${error.message}")
                        // Don't fail initialization if device registration fails
                    }
                )
            } else {
                jvmLogger.info("Device already registered")
            }

        } catch (e: Exception) {
            // Only throw if it's an authentication error, not device registration
            if (e.message?.contains("Authentication failed") == true ||
                e.message?.contains("Invalid API key") == true ||
                e.message?.contains("401") == true) {
                jvmLogger.error("Authentication failed: ${e.message}")
                throw e
            } else {
                // For other errors (like device registration), just log and continue
                jvmLogger.warn("Non-critical error during authentication phase: ${e.message}")
            }
        }
    }

    override suspend fun performHealthCheck() {
        jvmLogger.info("Performing health check")

        try {
            // Skip health check in development mode
            if (currentEnvironment == com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT) {
                jvmLogger.info("Skipping health check in development mode")
                return
            }

            // Skip health check for now - it's optional
            // The authentication service in the container hasn't been authenticated yet
            // This is a known issue that needs refactoring
            jvmLogger.info("Skipping health check (optional) - continuing initialization")
            return

        } catch (e: Exception) {
            jvmLogger.warn("Health check failed (optional): ${e.message}")
            // Don't throw - health check is optional
        }
    }

    override suspend fun cleanupPlatform() {
        // Cancel any ongoing recording
        isRecording = false
        recordingJob?.cancel()
        recordingJob = null

        // Cleanup components
        sttComponent?.cleanup()
        vadComponent?.cleanup()
        serviceContainer.cleanup()

        // Cancel the SDK scope
        sdkScope.cancel()
    }

    override suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return serviceContainer.modelInfoService.getAllModels()
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()

        val model = serviceContainer.modelInfoService.getModel(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        return modelDownloader.downloadModelWithProgress(model)
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()

        // For v0.1: Auto-load default model if STT is not ready
        var sttComponent =
            serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.STT) as? STTComponent

        jvmLogger.info("STT component from service container: ${sttComponent}, state: ${sttComponent?.state}")

        if (sttComponent == null || sttComponent.state != com.runanywhere.sdk.components.base.ComponentState.READY) {
            jvmLogger.info("STT not ready, attempting auto-load of default model...")

            // Auto-load the default model
            val modelLoaded = loadModel(DEFAULT_MODEL)
            if (!modelLoaded) {
                // For v0.1: Return mock transcription in development mode
                if (currentEnvironment == com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT) {
                    jvmLogger.warn("DEVELOPMENT MODE: Returning mock transcription")
                    return "Mock transcription: Audio received (${audioData.size} bytes)"
                }
                throw IllegalStateException("Failed to auto-load model for transcription")
            }

            // Try to get STT component again
            sttComponent =
                serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.STT) as? STTComponent
        }

        // For v0.1: If still not ready, return mock in dev mode
        if (sttComponent?.state != com.runanywhere.sdk.components.base.ComponentState.READY) {
            if (currentEnvironment == com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT) {
                jvmLogger.warn("DEVELOPMENT MODE: STT still not ready, returning mock transcription")
                return "Mock transcription: Audio processed (${audioData.size} bytes)"
            }
            throw IllegalStateException("STT component is not in READY state: ${sttComponent?.state}")
        }

        val result = sttComponent.transcribe(audioData)
        return result.text
    }

    /**
     * Streaming transcription API for real-time audio processing
     * Processes audio in chunks and emits transcription results as they become available
     */
    override fun transcribeStream(
        audioStream: Flow<ByteArray>,
        chunkSizeMs: Int
    ): Flow<STTStreamEvent> = flow {
        requireInitialized()

        jvmLogger.info("Starting streaming transcription with chunk size: ${chunkSizeMs}ms")

        // Ensure STT component is ready
        var sttComponent = serviceContainer.getComponent(SDKComponent.STT) as? STTComponent
        val vadComponent = serviceContainer.getComponent(SDKComponent.VAD) as? VADComponent

        // Auto-load model if needed
        if (sttComponent == null || sttComponent.state != ComponentState.READY) {
            jvmLogger.info("STT not ready for streaming, attempting auto-load...")
            if (!loadModel(DEFAULT_MODEL)) {
                emit(
                    STTStreamEvent.Error(
                        com.runanywhere.sdk.components.stt.STTError.serviceNotInitialized
                    )
                )
                return@flow
            }
            sttComponent = serviceContainer.getComponent(SDKComponent.STT) as? STTComponent
        }

        if (sttComponent == null) {
            emit(
                STTStreamEvent.Error(
                    com.runanywhere.sdk.components.stt.STTError.serviceNotInitialized
                )
            )
            return@flow
        }

        // Emit speech started event
        emit(STTStreamEvent.SpeechStarted)

        // Audio buffer for accumulating chunks
        val audioBuffer = ByteArrayOutputStream()
        var silenceCounter = 0
        val maxSilenceChunks = 6 // Increased to allow more silence (3 seconds at 500ms chunks)

        // WhisperJNI needs at least 1 second of audio
        val minBufferSizeBytes = 32000 // 1 second at 16kHz, 16-bit mono = 16000 * 2
        var lastTranscriptionText = ""
        var speechDetected = false

        try {
            audioStream.collect { audioChunk ->
                try {
                    // Add chunk to buffer
                    audioBuffer.write(audioChunk)

                    // Apply VAD if available
                    val isSpeech = if (vadComponent != null && audioChunk.isNotEmpty()) {
                        val audioFloats = convertBytesToFloats(audioChunk)
                        val vadResult = vadComponent.processAudioChunk(audioFloats)
                        val energy = vadResult.energyLevel
                        jvmLogger.debug("VAD result - Speech: ${vadResult.isSpeechDetected}, Energy: $energy")

                        // Use a more lenient threshold for streaming
                        energy > 0.005f // Lower threshold for better speech detection
                    } else {
                        true // Assume speech if no VAD
                    }

                    if (isSpeech) {
                        speechDetected = true
                        silenceCounter = 0
                    } else {
                        silenceCounter++
                    }

                    // Only process if we have enough audio (at least 1 second)
                    if (audioBuffer.size() >= minBufferSizeBytes) {
                        val audioData = audioBuffer.toByteArray()

                        // Only transcribe if we detected speech at some point
                        if (speechDetected) {
                            try {
                                val result = sttComponent.transcribe(audioData)

                                if (result.text.isNotEmpty() && result.text != lastTranscriptionText) {
                                    lastTranscriptionText = result.text

                                    // Emit partial transcription
                                    emit(
                                        STTStreamEvent.PartialTranscription(
                                            text = result.text,
                                            confidence = result.confidence,
                                            isFinal = false
                                        )
                                    )

                                    jvmLogger.debug("Partial transcription: ${result.text}")
                                }
                            } catch (e: Exception) {
                                jvmLogger.debug("Transcription error (continuing): ${e.message}")
                            }
                        }

                        // Keep last 20% for context continuity
                        val overlapSize = audioData.size / 5
                        audioBuffer.reset()
                        if (overlapSize > 0 && audioData.size > overlapSize) {
                            audioBuffer.write(audioData, audioData.size - overlapSize, overlapSize)
                        }
                    }

                    // Check for end of speech (extended silence)
                    if (silenceCounter >= maxSilenceChunks && speechDetected) {
                        // Process any remaining audio
                        if (audioBuffer.size() > 0) {
                            val finalAudioData = audioBuffer.toByteArray()

                            // Pad with silence if needed to reach minimum length
                            val paddedAudio = if (finalAudioData.size < minBufferSizeBytes) {
                                val padded = ByteArray(minBufferSizeBytes)
                                System.arraycopy(finalAudioData, 0, padded, 0, finalAudioData.size)
                                padded
                            } else {
                                finalAudioData
                            }

                            try {
                                val result = sttComponent.transcribe(paddedAudio)
                                if (result.text.isNotEmpty()) {
                                    val transcriptionResult = STTTranscriptionResult(
                                        transcript = result.text,
                                        confidence = result.confidence,
                                        language = result.detectedLanguage
                                    )
                                    emit(STTStreamEvent.FinalTranscription(transcriptionResult))
                                    jvmLogger.debug("Final transcription: ${result.text}")
                                }
                            } catch (e: Exception) {
                                jvmLogger.debug("Final transcription error: ${e.message}")
                            }
                        }

                        emit(STTStreamEvent.SpeechEnded)
                        audioBuffer.reset()
                        silenceCounter = 0
                        speechDetected = false
                        lastTranscriptionText = ""
                    }

                } catch (e: kotlinx.coroutines.CancellationException) {
                    // Cancellation is expected when stopping, don't treat as error
                    throw e
                } catch (e: Exception) {
                    jvmLogger.error("Error during streaming transcription chunk processing", e)
                    emit(
                        STTStreamEvent.Error(
                            com.runanywhere.sdk.components.stt.STTError.transcriptionFailed(e)
                        )
                    )
                }
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            // Normal cancellation when stopping recording
            jvmLogger.debug("Streaming transcription cancelled (normal stop)")
        }

        // Process any remaining audio in buffer (if not cancelled)
        if (audioBuffer.size() >= minBufferSizeBytes && speechDetected) {
            try {
                val finalAudioData = audioBuffer.toByteArray()
                val result = sttComponent.transcribe(finalAudioData)
                if (result.text.isNotEmpty()) {
                    val transcriptionResult = STTTranscriptionResult(
                        transcript = result.text,
                        confidence = result.confidence,
                        language = result.detectedLanguage
                    )
                    emit(STTStreamEvent.FinalTranscription(transcriptionResult))
                    jvmLogger.debug("Final transcription on completion: ${result.text}")
                }
            } catch (e: Exception) {
                jvmLogger.debug("Error processing final audio buffer: ${e.message}")
            }
        }

        // Emit speech ended event
        emit(STTStreamEvent.SpeechEnded)

        jvmLogger.info("Streaming transcription completed")
    }

    /**
     * Helper function to convert byte array to float array for VAD
     */
    private fun convertBytesToFloats(audioData: ByteArray): FloatArray {
        val samples = FloatArray(audioData.size / 2)
        var index = 0

        for (i in audioData.indices step 2) {
            if (i + 1 < audioData.size) {
                // Convert 16-bit PCM to float (-1.0 to 1.0)
                val sample =
                    ((audioData[i + 1].toInt() shl 8) or (audioData[i].toInt() and 0xFF)).toShort()
                samples[index] = sample / 32768.0f
                index++
            }
        }

        return samples.sliceArray(0 until index)
    }

    override suspend fun loadModel(modelId: String): Boolean {
        requireInitialized()

        jvmLogger.info("Loading model: $modelId")

        // For v0.1: Auto-download if model doesn't exist
        val actualModelId = if (modelId.isBlank()) DEFAULT_MODEL else modelId

        // Check if model exists locally and validate it
        val modelPath = modelStorage.getModelPath(actualModelId)
        val modelFile = java.io.File(modelPath)

        // Check if model is already available (cached)
        if (modelStorage.isModelAvailable(actualModelId)) {
            jvmLogger.info("Model $actualModelId already exists at: $modelPath")
            val fileSize = modelFile.length()
            jvmLogger.info("Existing model size: $fileSize bytes")

            // Model exists and is valid, no need to download
            jvmLogger.info("Using cached model for $actualModelId")
        } else {
            // Model doesn't exist or is invalid, download it
            jvmLogger.info("Model $actualModelId not found locally, downloading...")

            try {
                // Auto-download the model
                jvmLogger.info("Starting download of model $actualModelId...")
                val downloadFlow = modelStorage.downloadModel(actualModelId)

                // Collect the flow to wait for download completion
                var lastProgress = 0
                downloadFlow.onEach { progress ->
                    val currentProgress = (progress * 100).toInt()
                    if (currentProgress > lastProgress + 10 || currentProgress == 100) {
                        jvmLogger.info("Download progress for $actualModelId: $currentProgress%")
                        lastProgress = currentProgress
                    }
                }.last() // Wait for completion

                jvmLogger.info("Model $actualModelId downloaded successfully")

                // Verify the downloaded model
                if (!modelFile.exists()) {
                    throw Exception("Model file does not exist after download: $modelPath")
                }

                val fileSize = modelFile.length()
                jvmLogger.info("Downloaded model size: $fileSize bytes")

            } catch (e: Exception) {
                jvmLogger.error("Failed to download model $actualModelId: ${e.message}")

                // For v0.1: Return mock success in development mode
                if (currentEnvironment == com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT) {
                    jvmLogger.warn("DEVELOPMENT MODE: Using mock mode due to download failure")
                    // Create a mock model entry for development
                    val mockModel = ModelInfo(
                        id = actualModelId,
                        name = "Whisper Base (Mock)",
                        category = ModelCategory.SPEECH_RECOGNITION,
                        format = ModelFormat.GGML,
                        downloadURL = "mock://whisper-base",
                        downloadSize = 142_000_000,
                        memoryRequired = 200_000_000, // 200 MB for base model
                        localPath = null // No local path for mock
                    )
                    serviceContainer.modelInfoService.saveModel(mockModel)
                    return true
                }
                return false
            }
        }

        // Update model info with local path
        val model = serviceContainer.modelInfoService.getModel(actualModelId)
            ?: run {
                jvmLogger.info("Creating model entry for $actualModelId")
                // Get proper model size and memory requirements
                val modelSizeMB = JvmWhisperJNIModelMapper.getModelSize(actualModelId)
                val memoryRequired = when {
                    actualModelId.contains("tiny") -> 100_000_000L // 100 MB
                    actualModelId.contains("small") -> 500_000_000L // 500 MB
                    actualModelId.contains("medium") -> 1_500_000_000L // 1.5 GB
                    actualModelId.contains("large") -> 3_000_000_000L // 3 GB
                    else -> 200_000_000L // 200 MB for base (default)
                }

                val newModel = ModelInfo(
                    id = actualModelId,
                    name = "Whisper ${actualModelId.split("-").lastOrNull()?.capitalize() ?: "Base"}",
                    category = ModelCategory.SPEECH_RECOGNITION,
                    format = ModelFormat.GGML,
                    downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${JvmWhisperJNIModelMapper.mapModelIdToFileName(actualModelId)}",
                    downloadSize = modelSizeMB * 1024 * 1024, // Convert MB to bytes
                    memoryRequired = memoryRequired,
                    localPath = modelPath
                )
                serviceContainer.modelInfoService.saveModel(newModel)
                newModel
            }

        // Load model into memory using ModelManager
        return try {
            // Ensure the model has a local path
            val updatedModel = if (model.localPath == null) {
                model.copy(localPath = modelPath)
            } else {
                model
            }

            serviceContainer.modelManager.loadModel(updatedModel)
            jvmLogger.info("Model $actualModelId loaded successfully into ModelManager")

            // For v0.1: Force reinitialize the STT component with the new model
            try {
                jvmLogger.info("Reinitializing STT component with model...")

                // Create a new STT component with the loaded model
                val newSttComponent = STTComponent(
                    com.runanywhere.sdk.components.stt.STTConfiguration(modelId = actualModelId)
                )

                // Try to initialize it
                newSttComponent.initialize()

                // If successful, store it locally
                if (newSttComponent.state == com.runanywhere.sdk.components.base.ComponentState.READY) {
                    sttComponent = newSttComponent
                    jvmLogger.info("STT component reinitialized successfully with model $actualModelId")
                } else {
                    jvmLogger.warn("STT component initialized but not in READY state: ${newSttComponent.state}")
                }

            } catch (e: Exception) {
                jvmLogger.error("Could not reinitialize STT component: ${e.message}")
                // Continue anyway for v0.1
            }

            true
        } catch (e: Exception) {
            jvmLogger.error("Failed to load model $actualModelId: ${e.message}")

            // For v0.1: Return true in development mode
            if (currentEnvironment == com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT) {
                jvmLogger.warn("DEVELOPMENT MODE: Returning success despite load failure")
                return true
            }
            false
        }
    }

    /**
     * Start continuous streaming transcription with internal audio capture
     * This method handles all audio capture internally and provides continuous transcription
     * until stopStreamingTranscription is called
     *
     * @param chunkSizeMs Size of each audio chunk in milliseconds
     * @return Flow of transcription events
     */
    override fun startStreamingTranscription(
        chunkSizeMs: Int
    ): Flow<com.runanywhere.sdk.components.stt.STTStreamEvent> = flow {
        requireInitialized()

        jvmLogger.info("Starting continuous streaming transcription with internal audio capture")
        jvmLogger.info("Audio capture started, listening for speech...")

        // Get STT component
        val sttComponent =
            serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.STT)
                    as? com.runanywhere.sdk.components.stt.STTComponent

        if (sttComponent == null) {
            emit(
                com.runanywhere.sdk.components.stt.STTStreamEvent.Error(
                    com.runanywhere.sdk.components.stt.STTError.serviceNotInitialized
                )
            )
            return@flow
        }

        // Use SimpleEnergyVAD directly (hardcoded working solution)
        val vadService = try {
            jvmLogger.info("Using hardcoded SimpleEnergyVAD for speech detection")
            val vad = com.runanywhere.sdk.voice.vad.SimpleEnergyVAD()
            vad.initialize(
                com.runanywhere.sdk.components.vad.VADConfiguration(
                    sampleRate = 16000,
                    frameLength = 0.02f, // 20ms frames (320 samples at 16kHz)
                    energyThreshold = 0.003f // Much more sensitive threshold for normal speech
                )
            )
            vad.start()
            jvmLogger.info("SimpleEnergyVAD initialized successfully for Whisper hallucination prevention")
            vad
        } catch (e: Exception) {
            jvmLogger.error("Failed to initialize SimpleEnergyVAD: ${e.message}")
            null // Continue without VAD as fallback
        }

        try {
            // Start continuous audio capture
            val audioChunkFlow = audioCapture.startContinuousCapture()

            // Buffer for accumulating audio for transcription
            val audioBuffer = mutableListOf<Float>()
            var speechAudioBuffer = mutableListOf<Float>() // Buffer for speech segments only
            var lastTranscriptionText = ""
            val vadFrameSize = 320 // 20ms at 16kHz for WebRTC VAD
            val transcriptionThreshold = 24000 // 1.5 seconds of accumulated speech (Whisper needs >1 second)

            jvmLogger.info("Streaming started with WebRTC VAD - filtering silence to prevent hallucinations")

            audioChunkFlow
                .catch { e ->
                    // Only log actual errors, not cancellations
                    if (e !is kotlinx.coroutines.CancellationException) {
                        jvmLogger.error("Audio capture error: ${e.message}")
                        emit(
                            com.runanywhere.sdk.components.stt.STTStreamEvent.Error(
                                com.runanywhere.sdk.components.stt.STTError.transcriptionFailed(e)
                            )
                        )
                    }
                }
                .collect { chunk ->
                    // Accumulate audio chunks for VAD processing
                    audioBuffer.addAll(chunk.samples.toList())

                    // Process in 20ms frames (320 samples) with WebRTC VAD
                    while (audioBuffer.size >= vadFrameSize) {
                        val vadFrame = audioBuffer.take(vadFrameSize).toFloatArray()
                        val remainingBuffer = audioBuffer.drop(vadFrameSize).toMutableList()
                        audioBuffer.clear()
                        audioBuffer.addAll(remainingBuffer)

                        // Calculate audio energy for waveform visualization
                        val energy = vadFrame.map { it * it }.average().toFloat()
                        val normalizedEnergy = (energy * 1000).coerceIn(0.0f, 1.0f) // Normalize to 0-1 range

                        // Emit audio level for waveform visualization
                        emit(
                            com.runanywhere.sdk.components.stt.STTStreamEvent.AudioLevelChanged(
                                level = normalizedEnergy,
                                timestamp = System.currentTimeMillis() / 1000.0
                            )
                        )

                        // Run VAD on this frame
                        val vadResult = if (vadService != null && vadService.isReady) {
                            try {
                                vadService.processAudioChunk(vadFrame)
                            } catch (e: Exception) {
                                jvmLogger.warn("VAD processing failed: ${e.message}")
                                // Fallback: assume it's speech if VAD fails
                                com.runanywhere.sdk.components.vad.VADResult(isSpeechDetected = true, confidence = 0.5f)
                            }
                        } else {
                            // VAD not available, use simple energy detection
                            val isSpeech = energy > 0.001f // Simple energy threshold
                            com.runanywhere.sdk.components.vad.VADResult(isSpeechDetected = isSpeech, confidence = 0.5f)
                        }

                        // Only accumulate speech segments for transcription
                        if (vadResult.isSpeechDetected) {
                            speechAudioBuffer.addAll(vadFrame.toList())

                            // Don't transcribe during speech - let it accumulate
                            // We'll transcribe when speech ends (in the else block below)
                        } else {
                            // Silence detected - this prevents hallucinations!
                            jvmLogger.debug("VAD: Silence detected, skipping frame (prevents Whisper hallucinations)")

                            // If we have some accumulated speech, transcribe it
                            if (speechAudioBuffer.size > 16000) { // 1+ second minimum for Whisper
                                try {
                                    val pcmData = convertFloatToPCMBytes(speechAudioBuffer.toFloatArray())
                                    jvmLogger.debug("End of speech detected, transcribing ${speechAudioBuffer.size} samples")

                                    val result = sttComponent.transcribe(pcmData)
                                    if (result.text.isNotEmpty() && result.text != lastTranscriptionText) {
                                        emit(
                                            com.runanywhere.sdk.components.stt.STTStreamEvent.FinalTranscription(
                                                com.runanywhere.sdk.components.stt.STTTranscriptionResult(
                                                    transcript = result.text,
                                                    confidence = result.confidence
                                                )
                                            )
                                        )
                                        lastTranscriptionText = result.text
                                        jvmLogger.info("End-of-speech transcription: ${result.text}")
                                    }
                                } catch (e: Exception) {
                                    jvmLogger.error("End-of-speech transcription error: ${e.message}")
                                }

                                // Clear speech buffer
                                speechAudioBuffer.clear()
                            }
                        }
                    }

                    // Safety: prevent buffers from growing too large
                    if (speechAudioBuffer.size > 80000) { // 5 seconds max
                        val keepSamples = 16000 // Keep last 1 second
                        val newBuffer = speechAudioBuffer.takeLast(keepSamples).toMutableList()
                        speechAudioBuffer.clear()
                        speechAudioBuffer.addAll(newBuffer)
                    }

                    if (audioBuffer.size > 3200) { // 0.2 seconds max raw buffer
                        val newBuffer = audioBuffer.takeLast(1600).toMutableList() // Keep 0.1 seconds
                        audioBuffer.clear()
                        audioBuffer.addAll(newBuffer)
                    }
                }
        } catch (e: kotlinx.coroutines.CancellationException) {
            // Normal cancellation when stopping
            jvmLogger.info("Streaming transcription cancelled (user stopped recording)")
        } catch (e: Exception) {
            jvmLogger.error("Streaming transcription error: ${e.message}")
            emit(
                com.runanywhere.sdk.components.stt.STTStreamEvent.Error(
                    com.runanywhere.sdk.components.stt.STTError.transcriptionFailed(e)
                )
            )
        } finally {
            // Cleanup VAD service if it was initialized
            if (vadService != null) {
                try {
                    vadService.stop()
                    vadService.cleanup()
                    jvmLogger.info("VAD service cleaned up")
                } catch (e: Exception) {
                    jvmLogger.warn("Error cleaning up VAD service: ${e.message}")
                }
            }

            // Ensure audio capture is stopped
            audioCapture.stopCapture()
            jvmLogger.info("Audio capture stopped")
        }
    }

    /**
     * Stop the continuous streaming transcription
     */
    override fun stopStreamingTranscription() {
        jvmLogger.info("Stopping streaming transcription")
        audioCapture.stopCapture()
    }

    /**
     * Convert float audio samples to PCM byte array
     */
    private fun convertFloatToPCMBytes(samples: FloatArray): ByteArray {
        val pcmData = ByteArray(samples.size * 2) // 16-bit samples

        for (i in samples.indices) {
            // Convert float [-1.0, 1.0] to 16-bit signed integer
            val sample = (samples[i] * 32767).toInt().coerceIn(-32768, 32767).toShort()

            // Convert to little-endian bytes
            pcmData[i * 2] = (sample.toInt() and 0xFF).toByte()
            pcmData[i * 2 + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()
        }

        return pcmData
    }

    override suspend fun generate(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): String {
        requireInitialized()

        jvmLogger.info("Generating response for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions =
            options?.toGenerationOptions() ?: com.runanywhere.sdk.generation.GenerationOptions()

        // Use generation service from service container
        val result = serviceContainer.generationService.generate(prompt, generationOptions)

        jvmLogger.info("Generated response: ${result.text.take(50)}...")
        return result.text
    }

    override fun generateStream(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): Flow<String> {
        requireInitialized()

        jvmLogger.info("Starting streaming generation for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions =
            options?.toGenerationOptions() ?: com.runanywhere.sdk.generation.GenerationOptions(
            )

        // Use streaming service from service container
        return serviceContainer.streamingService.stream(prompt, generationOptions)
            .map { chunk -> chunk.text }
    }

    /**
     * Start recording audio for later transcription
     * Call this when user starts recording
     */
    fun startRecording() {
        if (isRecording) {
            jvmLogger.warn("Already recording")
            return
        }

        jvmLogger.info("Starting audio recording for later transcription")
        recordingBuffer.reset()
        isRecording = true

        // Start capturing audio into the buffer
        recordingJob = sdkScope.launch {
            try {
                audioCapture.startContinuousCapture()
                    .collect { chunk ->
                        if (isRecording) {
                            // Convert float samples back to PCM bytes for the buffer
                            val pcmData = convertFloatToPCMBytes(chunk.samples)
                            recordingBuffer.write(pcmData)
                        }
                    }
            } catch (e: kotlinx.coroutines.CancellationException) {
                jvmLogger.info("Recording cancelled")
            } catch (e: Exception) {
                jvmLogger.error("Recording error", e)
            }
        }
    }

    /**
     * Start recording with real-time waveform feedback
     * Emits audio energy events while recording for visualization
     * @return Flow of audio level events during recording
     */
    fun startRecordingWithWaveform(): Flow<com.runanywhere.sdk.components.stt.STTStreamEvent.AudioLevelChanged> = flow {
        if (isRecording) {
            jvmLogger.warn("Already recording")
            return@flow
        }

        jvmLogger.info("Starting audio recording with waveform feedback")
        recordingBuffer.reset()
        isRecording = true

        try {
            audioCapture.startContinuousCapture()
                .collect { chunk ->
                    if (isRecording) {
                        // Store audio for final transcription
                        val pcmData = convertFloatToPCMBytes(chunk.samples)
                        recordingBuffer.write(pcmData)

                        // Calculate and emit energy for waveform visualization
                        // Process in 20ms frames like streaming mode
                        val samples = chunk.samples
                        val frameSize = 320 // 20ms at 16kHz

                        var offset = 0
                        while (offset + frameSize <= samples.size) {
                            val frame = samples.sliceArray(offset until offset + frameSize)
                            val energy = frame.map { it * it }.average().toFloat()
                            val normalizedEnergy = (energy * 1000).coerceIn(0.0f, 1.0f)

                            emit(com.runanywhere.sdk.components.stt.STTStreamEvent.AudioLevelChanged(
                                level = normalizedEnergy,
                                timestamp = System.currentTimeMillis() / 1000.0
                            ))

                            offset += frameSize
                        }
                    }
                }
        } catch (e: kotlinx.coroutines.CancellationException) {
            jvmLogger.info("Recording with waveform cancelled")
            throw e
        } catch (e: Exception) {
            jvmLogger.error("Recording with waveform error", e)
            throw e
        } finally {
            // Don't reset recording state here, let stopRecordingAndTranscribe handle it
        }
    }

    /**
     * Stop recording and transcribe the captured audio
     * Call this when user stops recording
     * @return Transcribed text
     */
    suspend fun stopRecordingAndTranscribe(): String {
        if (!isRecording) {
            jvmLogger.warn("Not currently recording")
            return ""
        }

        jvmLogger.info("Stopping recording and transcribing")
        isRecording = false

        // Stop the recording job
        recordingJob?.cancel()
        recordingJob = null
        audioCapture.stopCapture()

        // Get the recorded audio
        val audioData = recordingBuffer.toByteArray()
        jvmLogger.info("Recorded ${audioData.size} bytes, transcribing...")

        // Transcribe if we have enough audio (at least 1 second)
        return if (audioData.size >= 32000) { // 1 second at 16kHz, 16-bit mono
            transcribe(audioData)
        } else {
            jvmLogger.warn("Audio too short for transcription: ${audioData.size} bytes")
            ""
        }
    }

    /**
     * Record audio for specified duration and transcribe it
     * This is a convenience method that handles audio recording internally
     *
     * @param durationSeconds Duration to record in seconds
     * @return Transcribed text
     */
    override suspend fun transcribeWithRecording(durationSeconds: Int): String {
        requireInitialized()

        jvmLogger.info("Recording audio for $durationSeconds seconds and transcribing...")

        // Record audio for the specified duration
        val audioData = audioCapture.recordAudio(durationSeconds * 1000L)

        jvmLogger.info("Recorded ${audioData.size} bytes of audio, transcribing...")

        // Transcribe the recorded audio
        return transcribe(audioData)
    }
}
