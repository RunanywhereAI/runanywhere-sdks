package com.runanywhere.sdk.public

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.flow

/**
 * Enhanced main public API interface for RunAnywhere SDK
 * Matches iOS RunAnywhere.swift functionality with rich typed methods
 */
interface RunAnywhereSDK {
    val isInitialized: Boolean
    val currentEnvironment: SDKEnvironment
    val events: EventBus

    // MARK: - Core Initialization

    suspend fun initialize(
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    )

    // MARK: - Text Generation - Enhanced to match iOS

    /**
     * Simple chat method matching iOS chat() method
     */
    suspend fun chat(prompt: String): String

    /**
     * Enhanced generate method with rich options
     */
    suspend fun generate(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions? = null
    ): String

    /**
     * Streaming generation with rich options
     */
    fun generateStream(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions? = null
    ): Flow<String>

    /**
     * Structured output generation - matches iOS generateStructured
     */
    suspend fun <T : com.runanywhere.sdk.models.Generatable> generateStructured(
        type: kotlin.reflect.KClass<T>,
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions? = null
    ): T

    // MARK: - Voice Operations - Enhanced

    /**
     * Enhanced transcription with options
     */
    suspend fun transcribe(audioData: ByteArray): String

    /**
     * Rich transcription with detailed options
     */
    suspend fun transcribe(
        audio: ByteArray,
        modelId: String,
        options: com.runanywhere.sdk.public.extensions.STTOptions
    ): com.runanywhere.sdk.public.extensions.STTResult

    /**
     * Streaming transcription API for real-time audio processing
     * Processes audio in chunks and emits transcription results as they become available
     *
     * @param audioStream Flow of audio chunks (ByteArray)
     * @param chunkSizeMs Size of each audio chunk in milliseconds (default: 1000ms)
     * @return Flow of transcription results as they are processed
     */
    fun transcribeStream(
        audioStream: Flow<ByteArray>,
        chunkSizeMs: Int = 1000
    ): Flow<com.runanywhere.sdk.components.stt.STTStreamEvent>

    /**
     * Start continuous streaming transcription with internal audio capture
     * This method handles all audio capture internally and provides continuous transcription
     * until stopStreamingTranscription is called
     *
     * @param chunkSizeMs Size of each audio chunk in milliseconds (default: 100ms for real-time)
     * @return Flow of transcription events
     */
    fun startStreamingTranscription(
        chunkSizeMs: Int = 100
    ): Flow<com.runanywhere.sdk.components.stt.STTStreamEvent>

    /**
     * Stop the continuous streaming transcription
     */
    fun stopStreamingTranscription()

    /**
     * Record audio for specified duration and transcribe it
     * This is a convenience method that handles audio recording internally
     *
     * @param durationSeconds Duration to record in seconds
     * @return Transcribed text
     */
    suspend fun transcribeWithRecording(durationSeconds: Int): String

    // MARK: - Model Management - Enhanced

    /**
     * Get available models
     */
    suspend fun availableModels(): List<ModelInfo>

    /**
     * Download model with progress
     */
    suspend fun downloadModel(modelId: String): Flow<Float>

    /**
     * Load model and return info
     */
    suspend fun loadModel(modelId: String): Boolean

    /**
     * Get currently loaded model
     */
    val currentModel: ModelInfo?

    // MARK: - Component Management

    /**
     * Initialize components with configuration
     */
    suspend fun initializeComponents(
        configs: List<com.runanywhere.sdk.public.extensions.ComponentInitializationConfig>
    ): Map<com.runanywhere.sdk.components.base.SDKComponent, com.runanywhere.sdk.public.extensions.ComponentInitializationResult>

    // MARK: - Conversation Management

    /**
     * Create conversation session
     */
    suspend fun createConversation(
        configuration: com.runanywhere.sdk.public.extensions.ConversationConfiguration
    ): com.runanywhere.sdk.public.extensions.ConversationSession

    // MARK: - Cost and Analytics

    /**
     * Enable cost tracking
     */
    suspend fun enableCostTracking(
        config: com.runanywhere.sdk.public.extensions.CostTrackingConfig = com.runanywhere.sdk.public.extensions.CostTrackingConfig()
    )

    /**
     * Get cost statistics
     */
    suspend fun getCostStatistics(
        period: com.runanywhere.sdk.public.extensions.CostStatistics.TimePeriod
    ): com.runanywhere.sdk.public.extensions.CostStatistics

    // MARK: - Pipeline Management

    /**
     * Execute pipeline
     */
    suspend fun executePipeline(
        pipelineId: String,
        inputs: Map<String, Any>
    ): com.runanywhere.sdk.public.extensions.PipelineResult

    // MARK: - Configuration

    /**
     * Get current routing policy
     */
    suspend fun getCurrentRoutingPolicy(): com.runanywhere.sdk.public.extensions.RoutingPolicy

    /**
     * Update routing policy
     */
    suspend fun updateRoutingPolicy(policy: com.runanywhere.sdk.public.extensions.RoutingPolicy)

    // MARK: - Lifecycle

    suspend fun cleanup()
}

/**
 * Common SDK implementation with shared logic
 * Follows iOS 8-step initialization pattern
 */
abstract class BaseRunAnywhereSDK : RunAnywhereSDK {
    protected var _isInitialized = false
    protected var _currentEnvironment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    protected var _configurationData: ConfigurationData? = null
    protected var _initParams: SDKInitParams? = null

    private val logger = SDKLogger("RunAnywhere.Init")
    protected val serviceContainer: ServiceContainer = ServiceContainer.shared

    override val isInitialized: Boolean
        get() = _isInitialized

    override val currentEnvironment: SDKEnvironment
        get() = _currentEnvironment

    override val events: EventBus
        get() = EventBus.shared

    /**
     * Initialize the RunAnywhere SDK
     *
     * This method performs a comprehensive initialization sequence:
     *
     * 1. **Validation**: Validate API key and parameters
     * 2. **Logging**: Initialize logging system based on environment
     * 3. **Storage**: Store credentials securely in keychain/keystore
     * 4. **Database**: Set up local database for caching
     * 5. **Authentication**: Exchange API key for access token with backend
     * 6. **Health Check**: Verify backend connectivity and service health
     * 7. **Bootstrap**: Initialize all services and sync with backend
     * 8. **Configuration**: Load and apply configuration
     *
     * The initialization is atomic - if any step fails, the entire process
     * is rolled back and the SDK remains uninitialized.
     */
    override suspend fun initialize(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        if (_isInitialized) {
            logger.info("SDK already initialized")
            return
        }

        val params = SDKInitParams(
            apiKey = apiKey,
            baseURL = baseURL,
            environment = environment
        )

        EventBus.shared.publish(SDKInitializationEvent.Started)

        try {
            // Step 1: Validate API key (skip in development mode)
            if (environment != SDKEnvironment.DEVELOPMENT) {
                logger.info("Step 1/8: Validating API key")
                if (apiKey.isEmpty()) {
                    throw SDKError.InvalidAPIKey("API key cannot be empty")
                }
            } else {
                logger.info("Step 1/8: Skipping API key validation in development mode")
            }

            // Step 2: Initialize logging system
            logger.info("Step 2/8: Initializing logging system")
            initializeLogging(environment)

            // Step 3: Store parameters securely
            logger.info("Step 3/8: Storing credentials securely")
            _initParams = params
            _currentEnvironment = environment

            // Only store in secure storage for non-development environments
            if (environment != SDKEnvironment.DEVELOPMENT) {
                storeCredentialsSecurely(params)
            }

            // Step 4: Initialize database
            logger.info("Step 4/8: Initializing local database")
            initializeDatabase()

            // Development mode: Skip API authentication and use local/mock services
            if (environment == SDKEnvironment.DEVELOPMENT) {
                logger.info("🚀 Running in DEVELOPMENT mode - using local/mock services")
                logger.info("Step 5/8: Skipping API authentication in development mode")
                logger.info("Step 6/8: Skipping health check in development mode")
                logger.info("Step 7/8: Bootstrapping SDK services with local data")

                // Bootstrap without API client for development mode
                val loadedConfig = serviceContainer.bootstrapDevelopmentMode(params)

                // Step 8: Store the configuration
                logger.info("Step 8/8: Loading configuration")
                _configurationData = loadedConfig

                // Mark as initialized
                _isInitialized = true
                logger.info("✅ SDK initialization completed successfully (Development Mode)")
                EventBus.shared.publish(SDKInitializationEvent.Completed)

            } else {
                // Production/Staging mode: Full API authentication flow

                // Step 5: Initialize API client and authentication service
                logger.info("Step 5/8: Authenticating with backend")
                authenticateWithBackend(params)

                // Step 6: Perform health check
                logger.info("Step 6/8: Performing health check")
                performHealthCheck()

                // Step 7: Bootstrap SDK services and sync with backend
                logger.info("Step 7/8: Bootstrapping SDK services and syncing with backend")
                val loadedConfig = serviceContainer.bootstrap(params)

                // Step 8: Store the configuration
                logger.info("Step 8/8: Loading configuration")
                _configurationData = loadedConfig

                // Mark as initialized
                _isInitialized = true
                logger.info("✅ SDK initialization completed successfully")
                EventBus.shared.publish(SDKInitializationEvent.Completed)
            }

        } catch (error: Exception) {
            logger.error("❌ SDK initialization failed: ${error.message}")
            _configurationData = null
            _initParams = null
            _isInitialized = false
            EventBus.shared.publish(SDKInitializationEvent.Failed(error))
            throw error
        }
    }

    /**
     * Initialize logging system based on environment
     */
    protected open fun initializeLogging(environment: SDKEnvironment) {
        // Set log level based on environment
        val logLevel = when (environment) {
            SDKEnvironment.DEVELOPMENT -> SDKLogger.Companion.LogLevel.DEBUG
            SDKEnvironment.STAGING -> SDKLogger.Companion.LogLevel.INFO
            SDKEnvironment.PRODUCTION -> SDKLogger.Companion.LogLevel.WARNING
        }
        SDKLogger.setLogLevel(logLevel)
    }

    /**
     * Store credentials securely (platform-specific)
     */
    protected abstract suspend fun storeCredentialsSecurely(params: SDKInitParams)

    /**
     * Initialize local database (platform-specific)
     */
    protected abstract suspend fun initializeDatabase()

    /**
     * Authenticate with backend API
     */
    protected abstract suspend fun authenticateWithBackend(params: SDKInitParams)

    /**
     * Perform health check on backend services
     */
    protected abstract suspend fun performHealthCheck()

    override suspend fun cleanup() {
        shutdown()
    }

    /**
     * Enhanced shutdown method matching iOS implementation
     */
    suspend fun shutdown() {
        if (!_isInitialized) {
            logger.info("SDK not initialized, nothing to shutdown")
            return
        }

        logger.info("Shutting down RunAnywhere SDK...")

        try {
            // Cleanup service container
            serviceContainer.cleanup()

            // Platform-specific cleanup
            cleanupPlatform()

            // Reset state
            _isInitialized = false
            _configurationData = null
            _initParams = null

            logger.info("✅ SDK shutdown completed successfully")

        } catch (error: Exception) {
            logger.error("❌ SDK shutdown failed: ${error.message}")
            throw error
        }
    }

    /**
     * Platform-specific cleanup to be implemented
     */
    // MARK: - Enhanced Interface Implementation

    /**
     * Simple chat method - calls generate with default options
     */
    override suspend fun chat(prompt: String): String {
        return generate(prompt, com.runanywhere.sdk.models.RunAnywhereGenerationOptions.DEFAULT)
    }

    /**
     * Enhanced generate method with RunAnywhereGenerationOptions
     */
    override suspend fun generate(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): String {
        requireInitialized()
        val result = serviceContainer.generationService?.generate(
            prompt,
            options?.toGenerationOptions()
        ) ?: throw SDKError.ComponentNotAvailable("Generation service not available")
        return result.text
    }

    /**
     * Enhanced streaming generation
     */
    override fun generateStream(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): Flow<String> {
        requireInitialized()
        val chunkFlow = serviceContainer.generationService?.streamGenerate(
            prompt,
            options?.toGenerationOptions()
        ) ?: throw SDKError.ComponentNotAvailable("Generation service not available")

        return chunkFlow.map { chunk -> chunk.text }
    }

    /**
     * Structured output generation
     */
    override suspend fun <T : com.runanywhere.sdk.models.Generatable> generateStructured(
        type: kotlin.reflect.KClass<T>,
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): T {
        requireInitialized()
        // Structured output not implemented yet
        throw SDKError.ComponentNotAvailable("Structured output service not available")
    }

    /**
     * Enhanced transcription with rich options
     */
    override suspend fun transcribe(
        audio: ByteArray,
        modelId: String,
        options: com.runanywhere.sdk.public.extensions.STTOptions
    ): com.runanywhere.sdk.public.extensions.STTResult {
        requireInitialized()
        // Use STT component for transcription
        val sttComponent = serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.STT)
            as? com.runanywhere.sdk.components.stt.STTComponent
            ?: throw SDKError.ComponentNotAvailable("STT component not available")

        val startTime = System.currentTimeMillis()
        val result = sttComponent.transcribe(
            audioData = audio,
            format = com.runanywhere.sdk.components.stt.AudioFormat.WAV,
            language = options.language
        )
        val processingTime = (System.currentTimeMillis() - startTime) / 1000.0

        return com.runanywhere.sdk.public.extensions.STTResult(
            text = result.text,
            language = result.detectedLanguage ?: options.language,
            confidence = result.confidence,
            duration = audio.size / (options.sampleRate * 2.0), // Assuming 16-bit audio
            wordTimestamps = null, // Not implemented yet
            speakerSegments = null, // Not implemented yet
            processingTime = processingTime,
            modelUsed = modelId
        )
    }

    /**
     * Streaming transcription API for real-time audio processing
     * Processes audio in chunks and emits transcription results as they become available
     *
     * @param audioStream Flow of audio chunks (ByteArray)
     * @param chunkSizeMs Size of each audio chunk in milliseconds (default: 1000ms)
     * @return Flow of transcription results as they are processed
     */
    override fun transcribeStream(
        audioStream: Flow<ByteArray>,
        chunkSizeMs: Int
    ): Flow<com.runanywhere.sdk.components.stt.STTStreamEvent> = flow {
        requireInitialized()

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

        // For now, collect chunks and transcribe them as complete audio
        // Platform-specific implementations can override for better streaming
        val audioBuffer = mutableListOf<Byte>()

        audioStream.collect { chunk ->
            audioBuffer.addAll(chunk.toList())

            // Process when we have enough data (simplified approach)
            if (audioBuffer.size >= 16000 * 2 * chunkSizeMs / 1000) { // 16kHz, 16-bit
                val audioData = audioBuffer.toByteArray()
                audioBuffer.clear()

                try {
                    val result = sttComponent.transcribe(audioData)
                    if (result.text.isNotEmpty()) {
                        emit(
                            com.runanywhere.sdk.components.stt.STTStreamEvent.PartialTranscription(
                                text = result.text,
                                confidence = result.confidence,
                                isFinal = false
                            )
                        )
                    }
                } catch (e: Exception) {
                    emit(
                        com.runanywhere.sdk.components.stt.STTStreamEvent.Error(
                            com.runanywhere.sdk.components.stt.STTError.transcriptionFailed(e)
                        )
                    )
                }
            }
        }

        // Process any remaining audio
        if (audioBuffer.isNotEmpty()) {
            try {
                val result = sttComponent.transcribe(audioBuffer.toByteArray())
                if (result.text.isNotEmpty()) {
                    val transcriptionResult =
                        com.runanywhere.sdk.components.stt.STTTranscriptionResult(
                            transcript = result.text,
                            confidence = result.confidence
                        )
                    emit(
                        com.runanywhere.sdk.components.stt.STTStreamEvent.FinalTranscription(
                            transcriptionResult
                        )
                    )
                }
            } catch (e: Exception) {
                // Ignore errors on final chunk
            }
        }
    }

    /**
     * Enhanced transcription with options
     */
    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()
        // Use STT component for transcription
        val sttComponent =
            serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.STT)
                    as? com.runanywhere.sdk.components.stt.STTComponent
                ?: throw SDKError.ComponentNotAvailable("STT component not available")

        val result = sttComponent.transcribe(
            audioData = audioData,
            format = com.runanywhere.sdk.components.stt.AudioFormat.WAV,
            language = "en-US"
        )

        return result.text
    }

    /**
     * Start continuous streaming transcription with internal audio capture
     * This method handles all audio capture internally and provides continuous transcription
     * until stopStreamingTranscription is called
     *
     * @param chunkSizeMs Size of each audio chunk in milliseconds (default: 100ms for real-time)
     * @return Flow of transcription events
     */
    override fun startStreamingTranscription(
        chunkSizeMs: Int
    ): Flow<com.runanywhere.sdk.components.stt.STTStreamEvent> {
        requireInitialized()
        // Platform-specific implementations should override this
        // For now, just return an empty flow
        return flow {
            emit(
                com.runanywhere.sdk.components.stt.STTStreamEvent.Error(
                    com.runanywhere.sdk.components.stt.STTError.streamingNotSupported
                )
            )
        }
    }

    /**
     * Stop the continuous streaming transcription
     */
    override fun stopStreamingTranscription() {
        requireInitialized()
        // Platform-specific implementations should override this
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
        // Platform-specific implementation should override this
        throw SDKError.ComponentNotAvailable("Transcribe with recording not available")
    }

    /**
     * Get current model
     */
    override val currentModel: ModelInfo?
        get() = null // Model manager not implemented yet

    /**
     * Initialize components
     */
    override suspend fun initializeComponents(
        configs: List<com.runanywhere.sdk.public.extensions.ComponentInitializationConfig>
    ): Map<com.runanywhere.sdk.components.base.SDKComponent, com.runanywhere.sdk.public.extensions.ComponentInitializationResult> {
        requireInitialized()
        // Extension functions not implemented yet
        return emptyMap<com.runanywhere.sdk.components.base.SDKComponent, com.runanywhere.sdk.public.extensions.ComponentInitializationResult>()
    }

    /**
     * Create conversation
     */
    override suspend fun createConversation(
        configuration: com.runanywhere.sdk.public.extensions.ConversationConfiguration
    ): com.runanywhere.sdk.public.extensions.ConversationSession {
        requireInitialized()
        // Extension functions not implemented yet
        throw SDKError.ComponentNotAvailable("Conversation management not available")
    }

    /**
     * Enable cost tracking
     */
    override suspend fun enableCostTracking(
        config: com.runanywhere.sdk.public.extensions.CostTrackingConfig
    ) {
        requireInitialized()
        // Extension functions not implemented yet
    }

    /**
     * Get cost statistics
     */
    override suspend fun getCostStatistics(
        period: com.runanywhere.sdk.public.extensions.CostStatistics.TimePeriod
    ): com.runanywhere.sdk.public.extensions.CostStatistics {
        requireInitialized()
        // Extension functions not implemented yet
        throw SDKError.ComponentNotAvailable("Cost tracking not available")
    }

    /**
     * Execute pipeline
     */
    override suspend fun executePipeline(
        pipelineId: String,
        inputs: Map<String, Any>
    ): com.runanywhere.sdk.public.extensions.PipelineResult {
        requireInitialized()
        // Extension functions not implemented yet
        throw SDKError.ComponentNotAvailable("Pipeline execution not available")
    }

    /**
     * Get current routing policy
     */
    override suspend fun getCurrentRoutingPolicy(): com.runanywhere.sdk.public.extensions.RoutingPolicy {
        requireInitialized()
        // Extension functions not implemented yet
        throw SDKError.ComponentNotAvailable("Routing policy not available")
    }

    /**
     * Update routing policy
     */
    override suspend fun updateRoutingPolicy(policy: com.runanywhere.sdk.public.extensions.RoutingPolicy) {
        requireInitialized()
        // Extension functions not implemented yet
    }

    protected abstract suspend fun cleanupPlatform()

    protected fun requireInitialized() {
        if (!_isInitialized) {
            throw IllegalStateException("SDK not initialized. Call initialize() first")
        }
    }
}

/**
 * Platform-specific singleton instance
 */
expect object RunAnywhere : BaseRunAnywhereSDK
