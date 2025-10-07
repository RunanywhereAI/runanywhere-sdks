package com.runanywhere.sdk.components

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.base.ComponentConfiguration
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.generation.GenerationOptions
import com.runanywhere.sdk.generation.GenerationService
import com.runanywhere.sdk.generation.StreamingService
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.LLMServiceProvider
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable

/**
 * Legacy LLM Component - DEPRECATED
 * Use com.runanywhere.sdk.components.llm.LLMComponent instead
 * This is kept for backward compatibility during transition
 */
@Deprecated("Use com.runanywhere.sdk.components.llm.LLMComponent instead", ReplaceWith("com.runanywhere.sdk.components.llm.LLMComponent"))
class LegacyLLMComponent(
    private val llmConfiguration: LLMConfiguration
) : BaseComponent<LLMService>(llmConfiguration) {

    override val componentType: SDKComponent = SDKComponent.LLM

    private var generationService: GenerationService? = null
    private var streamingService: StreamingService? = null
    private var currentModel: ModelInfo? = null
    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    override suspend fun createService(): LLMService {
        // Create service from registry or default implementation
        val provider = ModuleRegistry.llmProvider(llmConfiguration.modelId)
        return if (provider != null) {
            LLMServiceAdapter(provider)
        } else {
            DefaultLLMService()
        }
    }

    override suspend fun initializeService() {
        // Initialize generation services

        // Initialize generation services
        generationService = GenerationService()
        streamingService = StreamingService()


        // Initialize service
        service = createService()

        // Load model if specified
        llmConfiguration.modelId?.let { modelId ->
            // Model loading will be handled by the service provider
        }
    }

    /**
     * Generate text from a prompt
     */
    suspend fun generate(
        prompt: String,
        options: GenerationOptions = GenerationOptions()
    ): String {
        ensureReady()

        _isGenerating.value = true
        return try {
            service?.generate(prompt, options)
                ?: throw IllegalStateException("LLM service not initialized")
        } finally {
            _isGenerating.value = false
        }
    }

    /**
     * Generate text stream from a prompt
     */
    fun generateStream(
        prompt: String,
        options: GenerationOptions = GenerationOptions()
    ): Flow<String> {
        ensureReady()

        return flow {
            _isGenerating.value = true
            try {
                service?.generateStream(prompt, options)?.collect { token ->
                    emit(token)
                } ?: throw IllegalStateException("LLM service not initialized")
            } finally {
                _isGenerating.value = false
            }
        }
    }

    /**
     * Generate with conversation context
     */
    suspend fun generateWithContext(
        messages: List<LLMMessage>,
        options: GenerationOptions = GenerationOptions()
    ): String {
        ensureReady()

        // Convert messages to prompt
        val prompt = messages.joinToString("\n") { message ->
            "${message.role}: ${message.content}"
        }

        return generate(prompt, options)
    }

    /**
     * Load a specific model
     */
    suspend fun loadModel(modelInfo: ModelInfo) {
        transitionTo(ComponentState.INITIALIZING)

        try {
            // Load model (implementation would depend on the model format)
            currentModel = modelInfo
            service?.loadModel(modelInfo)
            transitionTo(ComponentState.READY)
        } catch (e: Exception) {
            transitionTo(ComponentState.FAILED)
            throw e
        }
    }

    /**
     * Get current model info
     */
    fun getCurrentModel(): ModelInfo? = currentModel

    /**
     * Cancel current generation
     */
    fun cancelGeneration() {
        _isGenerating.value = false
        service?.cancelCurrent()
    }

    /**
     * Get token count for text
     */
    fun getTokenCount(text: String): Int {
        // Simple approximation - actual implementation would use tokenizer
        return text.split(" ").size
    }

    /**
     * Check if prompt fits within context window
     */
    fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        return getTokenCount(prompt) <= maxTokens
    }
}

/**
 * LLM Message for conversation
 */
@Serializable
data class LLMMessage(
    val role: LLMRole,
    val content: String,
    val metadata: Map<String, String> = emptyMap()
)

/**
 * LLM Role types
 */
@Serializable
enum class LLMRole {
    SYSTEM,
    USER,
    ASSISTANT;

    val displayName: String
        get() = when (this) {
            SYSTEM -> "System"
            USER -> "User"
            ASSISTANT -> "Assistant"
        }
}

/**
 * LLM Configuration
 */
data class LLMConfiguration(
    val modelId: String? = null,
    val maxTokens: Int = 2048,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,
    val enableStreaming: Boolean = true
) : ComponentConfiguration {
    override fun validate() {
        require(maxTokens > 0) { "Max tokens must be positive" }
        require(temperature >= 0f && temperature <= 2f) { "Temperature must be between 0 and 2" }
        require(topP >= 0f && topP <= 1f) { "Top-p must be between 0 and 1" }
    }
}

/**
 * LLM Service interface
 */
interface LLMService {
    suspend fun generate(prompt: String, options: GenerationOptions): String
    fun generateStream(prompt: String, options: GenerationOptions): Flow<String>
    suspend fun loadModel(modelInfo: ModelInfo)
    fun cancelCurrent()
}

/**
 * Adapter for ModuleRegistry providers
 */
class LLMServiceAdapter(
    private val provider: LLMServiceProvider
) : LLMService {
    override suspend fun generate(prompt: String, options: GenerationOptions): String {
        return provider.generate(prompt, options)
    }

    override fun generateStream(prompt: String, options: GenerationOptions): Flow<String> {
        return provider.generateStream(prompt, options)
    }

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Provider handles model loading
    }

    override fun cancelCurrent() {
        // Provider handles cancellation
    }
}

/**
 * Default LLM service implementation
 */
class DefaultLLMService : LLMService {
    private val generationService by lazy { GenerationService() }
    private val streamingService by lazy { StreamingService() }

    override suspend fun generate(prompt: String, options: GenerationOptions): String {
        val result = generationService.generate(prompt, options)
        return result.text
    }

    override fun generateStream(prompt: String, options: GenerationOptions): Flow<String> {
        return flow {
            emit("Generated stream: $prompt")
        }
    }

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Load model implementation
    }

    override fun cancelCurrent() {
        // Cancel generation
    }
}
