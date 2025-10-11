package com.runanywhere.sdk.public

import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.generation.StructuredOutputHandler
import com.runanywhere.sdk.models.ModelInfo
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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
     * Unload the currently loaded model from memory.
     * Matches Swift SDK's unloadModel() API.
     */
    suspend fun unloadModel()

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
    private val registrationLogger = SDKLogger("RunAnywhere.Registration")
    protected val serviceContainer: ServiceContainer = ServiceContainer.shared

    // MARK: - Lazy Device Registration State (matches Swift SDK)

    private var _cachedDeviceId: String? = null
    private var _isRegistering = false
    private val _isDeviceRegistered = MutableStateFlow(false)
    private val registrationMutex = Mutex()

    // MARK: - Current Model Tracking (matches Swift SDK)

    private var _currentModel: ModelInfo? = null

    companion object {
        private const val MAX_REGISTRATION_RETRIES = 3
        private const val RETRY_DELAY_MS = 2000L
        private const val REGISTRATION_TIMEOUT_MS = 5000L
        private const val POLLING_INTERVAL_MS = 100L

        /**
         * Check if device is registered (for testing/debugging)
         */
        fun isDeviceRegistered(): Boolean = false // Will be overridden by actual instance
    }

    override val isInitialized: Boolean
        get() = _isInitialized

    override val currentEnvironment: SDKEnvironment
        get() = _currentEnvironment

    override val events: EventBus
        get() = EventBus.shared

    /**
     * Current configuration data
     * Exposed for extension functions
     */
    val configurationData: ConfigurationData?
        get() = _configurationData

    /**
     * Initialize the RunAnywhere SDK
     *
     * This method performs LIGHTWEIGHT initialization (matches Swift SDK):
     *
     * 1. **Validation**: Validate API key and parameters (skip in development)
     * 2. **Logging**: Initialize logging system based on environment
     * 3. **Storage**: Store parameters locally (keychain for production, skip for dev)
     * 4. **Database**: Initialize local SQLite database (migrations, schema setup)
     * 5. **Local Services**: Setup local-only services (memory management, model registry)
     *
     * NO network calls during initialization!
     * Device registration and backend communication happen lazily on first API call.
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

        // EventBus.shared.publish(SDKInitializationEvent.Started)

        try {
            // Step 1: Validate API key (skip in development mode)
            if (environment != SDKEnvironment.DEVELOPMENT) {
                logger.info("Step 1/5: Validating API key")
                if (apiKey.isEmpty()) {
                    throw SDKError.InvalidAPIKey("API key cannot be empty")
                }
            } else {
                logger.info("Step 1/5: Skipping API key validation in development mode")
            }

            // Step 2: Initialize logging system
            logger.info("Step 2/5: Initializing logging system")
            initializeLogging(environment)

            // Step 3: Store parameters locally
            logger.info("Step 3/5: Storing parameters locally")
            _initParams = params
            _currentEnvironment = environment

            // Only store in secure storage for non-development environments
            if (environment != SDKEnvironment.DEVELOPMENT) {
                storeCredentialsSecurely(params)
            }

            // Step 4: Initialize local database
            logger.info("Step 4/5: Initializing local database")
            initializeDatabase()

            // Step 5: Setup local services only (NO network calls)
            logger.info("Step 5/5: Setting up local services")
            setupLocalServices()

            // Mark as initialized
            _isInitialized = true
            logger.info("✅ SDK initialization completed successfully (${environment.name} mode)")
            // EventBus.shared.publish(SDKInitializationEvent.Completed)

        } catch (error: Exception) {
            logger.error("❌ SDK initialization failed: ${error.message}")
            _configurationData = null
            _initParams = null
            _isInitialized = false
            // EventBus.shared.publish(SDKInitializationEvent.Failed(error))
            throw error
        }
    }

    /**
     * Setup local-only services (no network calls)
     * Matches Swift SDK's setupLocalServices()
     */
    protected open suspend fun setupLocalServices() {
        // Local services are initialized lazily by ServiceContainer
        // No explicit setup needed here (services initialize on first use)
        logger.debug("Local services ready for lazy initialization")
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
    protected abstract suspend fun cleanupPlatform()

    // MARK: - Device Registration Storage (Platform-Specific)

    /**
     * Get stored device ID from local persistence (platform-specific)
     * Matches Swift SDK's getStoredDeviceId()
     */
    protected abstract suspend fun getStoredDeviceId(): String?

    /**
     * Store device ID in local persistence (platform-specific)
     * Matches Swift SDK's storeDeviceId()
     */
    protected abstract suspend fun storeDeviceId(deviceId: String)

    /**
     * Generate a device identifier (platform-specific)
     * Matches Swift SDK's generateDeviceIdentifier()
     */
    protected abstract fun generateDeviceIdentifier(): String

    // MARK: - Lazy Device Registration Implementation

    /**
     * Ensure device is registered with backend (lazy registration)
     * Only registers if device ID doesn't exist locally
     * Matches Swift SDK's ensureDeviceRegistered() implementation exactly
     *
     * @throws SDKError if registration fails after retries
     */
    protected suspend fun ensureDeviceRegistered() {
        // First check: Quick check without lock
        if (_isDeviceRegistered.value && _cachedDeviceId?.isNotEmpty() == true) {
            return
        }

        // Acquire registration lock
        registrationMutex.withLock {
            // Check if we have a cached device ID
            if (_cachedDeviceId?.isNotEmpty() == true) {
                _isDeviceRegistered.value = true
                return
            }

            // Check if device is already registered in local storage
            val storedDeviceId = getStoredDeviceId()
            if (!storedDeviceId.isNullOrEmpty()) {
                _cachedDeviceId = storedDeviceId
                _isDeviceRegistered.value = true
                return
            }

            // Check if already registering
            if (_isRegistering) {
                // Another coroutine is handling registration, wait for it
                return
            }

            // Mark as registering
            _isRegistering = true
        }

        registrationLogger.info("Starting device registration...")

        try {
            // Skip registration in development mode
            if (_currentEnvironment == SDKEnvironment.DEVELOPMENT) {
                val mockDeviceId = "dev-${generateDeviceIdentifier()}"
                storeDeviceId(mockDeviceId)
                _cachedDeviceId = mockDeviceId
                _isDeviceRegistered.value = true
                registrationLogger.info("Using mock device ID for development: ${mockDeviceId.take(8)}...")
                return
            }

            // Ensure we have init params
            val params = _initParams ?: throw SDKError.NotInitialized

            // Registration with retry logic (matches Swift SDK)
            var lastError: Exception? = null

            for (attempt in 0 until MAX_REGISTRATION_RETRIES) {
                try {
                    registrationLogger.info("Device registration attempt ${attempt + 1} of $MAX_REGISTRATION_RETRIES")

                    // Initialize network services if needed (lazy)
                    serviceContainer.initializeNetworkServices(params)

                    val authService = serviceContainer.authenticationService

                    // Register device with backend
                    val deviceRegistration = authService.registerDevice()

                    // Store device ID locally
                    storeDeviceId(deviceRegistration.deviceId)
                    _cachedDeviceId = deviceRegistration.deviceId
                    _isDeviceRegistered.value = true

                    registrationLogger.info("Device registered successfully: ${deviceRegistration.deviceId.take(8)}...")
                    registrationLogger.debug("Device registration completed")

                    // Success! Exit retry loop
                    return

                } catch (e: Exception) {
                    lastError = e
                    registrationLogger.error("Device registration attempt ${attempt + 1} failed: ${e.message}")

                    // Check if error is retryable
                    if (!isRetryableError(e)) {
                        registrationLogger.error("Non-retryable error, stopping registration attempts")
                        throw e
                    }

                    // Wait before retrying (except on last attempt)
                    if (attempt < MAX_REGISTRATION_RETRIES - 1) {
                        registrationLogger.info("Waiting ${RETRY_DELAY_MS / 1000} seconds before retry...")
                        delay(RETRY_DELAY_MS)
                    }
                }
            }

            // All retries exhausted
            val finalError = lastError ?: SDKError.NetworkError(
                "Device registration failed after $MAX_REGISTRATION_RETRIES attempts"
            )
            registrationLogger.error("Device registration failed after all retries: ${finalError.message}")
            throw finalError

        } finally {
            // Always reset _isRegistering flag
            _isRegistering = false
        }
    }

    /**
     * Determine if an error is retryable (matches Swift SDK logic)
     */
    private fun isRetryableError(error: Exception): Boolean {
        return when (error) {
            is SDKError.NetworkError,
            is SDKError.Timeout,
            is SDKError.ServerError -> true
            is SDKError.InvalidAPIKey,
            is SDKError.NotInitialized,
            is SDKError.InvalidState,
            is SDKError.ValidationFailed,
            is SDKError.StorageError -> false
            else -> {
                // Check error message for common network errors
                val message = error.message?.lowercase() ?: ""
                message.contains("timeout") ||
                        message.contains("connection") ||
                        message.contains("network") ||
                        message.contains("dns")
            }
        }
    }

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

        // ✨ Lazy device registration on first API call (matches Swift SDK)
        ensureDeviceRegistered()

        // Try to use GenerationService first (preferred approach)
        if (serviceContainer.generationService.isReady()) {
            val genOptions = com.runanywhere.sdk.generation.GenerationOptions(
                temperature = options?.temperature ?: 0.7f,
                maxTokens = options?.maxTokens ?: 2048,
                streaming = false
            )

            val result = serviceContainer.generationService.generate(prompt, genOptions)
            return result.text
        }

        // Fallback: Get or create LLM component directly
        var llmComponent = serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.LLM)
            as? com.runanywhere.sdk.components.llm.LLMComponent

        if (llmComponent == null || !llmComponent.isReady) {
            // Try to find an available model from the registry
            val availableModels = serviceContainer.modelRegistry.discoverModels()
            val llmModels = availableModels.filter {
                it.category == com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE
            }

            if (llmModels.isEmpty()) {
                throw SDKError.ComponentNotAvailable("No LLM models available. Please add a model using addModelFromURL() first.")
            }

            // Use the first available LLM model
            val modelToUse = llmModels.first()

            // Initialize LLM component with discovered model
            val llmConfig = com.runanywhere.sdk.components.llm.LLMConfiguration(
                modelId = modelToUse.id,
                temperature = options?.temperature?.toDouble() ?: 0.7,
                maxTokens = options?.maxTokens ?: 2048,
                contextLength = modelToUse.contextLength ?: 4096
            )
            llmComponent = com.runanywhere.sdk.components.llm.LLMComponent(llmConfig)
            llmComponent.initialize()
            serviceContainer.setComponent(com.runanywhere.sdk.components.base.SDKComponent.LLM, llmComponent)

            // Initialize GenerationService with this component
            serviceContainer.generationService.initializeWithLLMComponent(llmComponent)
        }

        // Use provided options or create defaults
        val genOptions = options ?: com.runanywhere.sdk.models.RunAnywhereGenerationOptions.DEFAULT

        // Generate using LLM component directly
        val result = llmComponent.generate(prompt, genOptions.systemPrompt)
        return result.text
    }

    /**
     * Enhanced streaming generation
     */
    override fun generateStream(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): Flow<String> = flow {
        requireInitialized()

        // Try to use GenerationService for streaming (preferred approach)
        if (serviceContainer.generationService.isReady()) {
            val genOptions = com.runanywhere.sdk.generation.GenerationOptions(
                temperature = options?.temperature ?: 0.7f,
                maxTokens = options?.maxTokens ?: 2048,
                streaming = true
            )

            serviceContainer.generationService.streamGenerate(prompt, genOptions).collect { chunk ->
                emit(chunk.text)
            }
            return@flow
        }

        // Fallback: Get or initialize LLM component directly
        var llmComponent = serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.LLM)
            as? com.runanywhere.sdk.components.llm.LLMComponent

        if (llmComponent == null || !llmComponent.isReady) {
            // Try to find an available model from the registry
            val availableModels = serviceContainer.modelRegistry.discoverModels()
            val llmModels = availableModels.filter {
                it.category == com.runanywhere.sdk.models.enums.ModelCategory.LANGUAGE
            }

            if (llmModels.isEmpty()) {
                throw SDKError.ComponentNotAvailable("No LLM models available. Please add a model using addModelFromURL() first.")
            }

            // Use the first available LLM model
            val modelToUse = llmModels.first()

            // Initialize LLM component with discovered model
            val llmConfig = com.runanywhere.sdk.components.llm.LLMConfiguration(
                modelId = modelToUse.id,
                temperature = options?.temperature?.toDouble() ?: 0.7,
                maxTokens = options?.maxTokens ?: 2048,
                contextLength = modelToUse.contextLength ?: 4096
            )
            llmComponent = com.runanywhere.sdk.components.llm.LLMComponent(llmConfig)
            llmComponent.initialize()
            serviceContainer.setComponent(com.runanywhere.sdk.components.base.SDKComponent.LLM, llmComponent)

            // Initialize GenerationService with this component
            serviceContainer.generationService.initializeWithLLMComponent(llmComponent)
        }

        // Use provided options or create defaults
        val genOptions = options ?: com.runanywhere.sdk.models.RunAnywhereGenerationOptions.DEFAULT

        // Stream using LLM component directly
        llmComponent.streamGenerate(prompt, genOptions.systemPrompt).collect { token ->
            emit(token)
        }
    }

    /**
     * Structured output generation - matches iOS simple pattern
     */
    override suspend fun <T : com.runanywhere.sdk.models.Generatable> generateStructured(
        type: kotlin.reflect.KClass<T>,
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): T {
        requireInitialized()

        // Simple iOS pattern:
        // 1. Create StructuredOutputHandler
        val handler = StructuredOutputHandler()

        // 2. Get system prompt for type
        val systemPrompt = handler.getSystemPrompt(type)

        // 3. Enhance options with structured output config
        val effectiveOptions = com.runanywhere.sdk.models.RunAnywhereGenerationOptions(
            maxTokens = options?.maxTokens ?: 1500,
            temperature = options?.temperature ?: 0.7f,
            topP = options?.topP ?: 1.0f,
            enableRealTimeTracking = options?.enableRealTimeTracking ?: true,
            stopSequences = options?.stopSequences ?: emptyList(),
            streamingEnabled = false,
            preferredExecutionTarget = options?.preferredExecutionTarget,
            systemPrompt = systemPrompt
        )

        // 4. Build user prompt
        val userPrompt = handler.buildUserPrompt(type, prompt)

        // 5. Call regular generate() method
        val generatedText = generate(userPrompt, effectiveOptions)

        // 6. Parse result as T
        return handler.parseStructuredOutput(generatedText, type)
    }

    /**
     * Generate text with conversation history.
     * Kotlin SDK extension - not in Swift SDK.
     *
     * @param messages Conversation history
     * @param systemPrompt Optional system prompt
     * @param options Generation options
     * @return Generated text
     */
    suspend fun generateWithHistory(
        messages: List<com.runanywhere.sdk.models.Message>,
        systemPrompt: String? = null,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions? = null
    ): String {
        requireInitialized()
        ensureDeviceRegistered()

        val llmComponent = serviceContainer.llmComponent
            ?: throw SDKError.ComponentNotAvailable("LLM component not available")

        val result = llmComponent.generateWithHistory(messages, systemPrompt)
        return result.text
    }

    /**
     * Clear conversation context.
     * Kotlin SDK extension - not in Swift SDK.
     */
    suspend fun clearConversationContext() {
        requireInitialized()

        val llmComponent = serviceContainer.llmComponent
        llmComponent?.clearConversationContext()
    }

    /**
     * Estimate token count for text.
     * Kotlin SDK extension - not in Swift SDK.
     *
     * @param text Text to estimate
     * @return Estimated token count
     */
    suspend fun estimateTokens(text: String): Int {
        requireInitialized()

        val llmComponent = serviceContainer.llmComponent
            ?: throw SDKError.ComponentNotAvailable("LLM component not available")

        return llmComponent.getTokenCount(text)
    }

    /**
     * Check if prompt fits in context window.
     * Kotlin SDK extension - not in Swift SDK.
     *
     * @param prompt Prompt text
     * @param maxTokens Max tokens to generate
     * @return true if fits in context
     */
    suspend fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        requireInitialized()

        val llmComponent = serviceContainer.llmComponent
            ?: throw SDKError.ComponentNotAvailable("LLM component not available")

        return llmComponent.fitsInContext(prompt, maxTokens)
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

        // ✨ Lazy device registration on first API call (matches Swift SDK)
        ensureDeviceRegistered()

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

        // ✨ Lazy device registration on first API call (matches Swift SDK)
        ensureDeviceRegistered()

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
     * Get current model (matches Swift SDK)
     */
    override val currentModel: ModelInfo?
        get() = _currentModel

    /**
     * Unload the currently loaded model from memory.
     * Matches Swift SDK's unloadModel() API.
     */
    override suspend fun unloadModel() {
        requireInitialized()
        ensureDeviceRegistered()

        if (_currentModel == null) {
            logger.warn("No model loaded to unload")
            return
        }

        val modelId = _currentModel?.id ?: "unknown"
        logger.info("Unloading model: $modelId")

        try {
            // Get LLM component and unload model
            val llmComponent = serviceContainer.llmComponent
            llmComponent?.unloadModel()

            // Clear current model reference
            _currentModel = null

            logger.info("✅ Model unloaded successfully: $modelId")
        } catch (e: Exception) {
            logger.error("Failed to unload model: $modelId", e)
            throw SDKError.ComponentNotReady("Failed to unload model: ${e.message}")
        }
    }

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
