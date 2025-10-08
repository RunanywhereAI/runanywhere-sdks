package com.runanywhere.sdk.generation

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKGenerationEvent
import com.runanywhere.sdk.models.LoadedModelWithService
import com.runanywhere.sdk.components.llm.LLMComponent
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Service for text generation with LLM models
 * Handles both streaming and non-streaming generation
 */
class GenerationService {

    private val logger = SDKLogger("GenerationService")
    private val optionsResolver = GenerationOptionsResolver()
    private val streamingService = StreamingService()
    private val mutex = Mutex()

    // Track active generation sessions
    private val activeSessions = mutableMapOf<String, GenerationSession>()
    private var currentSessionId: String? = null
    
    // Track currently loaded model
    private var currentModel: LoadedModelWithService? = null
    
    // LLM component for actual generation
    private var llmComponent: LLMComponent? = null

    /**
     * Generate text with RunAnywhereGenerationOptions
     */
    suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): GenerationResult {
        val convertedOptions = GenerationOptions(
            temperature = options.temperature,
            maxTokens = options.maxTokens,
            streaming = options.streamingEnabled
        )
        return generate(prompt, convertedOptions)
    }
    
    /**
     * Generate text with the specified prompt and options
     */
    suspend fun generate(
        prompt: String,
        options: GenerationOptions? = null
    ): GenerationResult {
        val resolvedOptions = optionsResolver.resolve(options)
        val sessionId = createSessionId()

        logger.info("Starting generation session: $sessionId")

        val session = GenerationSession(
            id = sessionId,
            prompt = prompt,
            options = resolvedOptions,
            startTime = System.currentTimeMillis()
        )

        mutex.withLock {
            activeSessions[sessionId] = session
        }

        try {
            // Publish generation started event
            publishGenerationStarted(sessionId, prompt)

            // Perform generation (mock implementation for now)
            val response = performGeneration(prompt, resolvedOptions)

            val result = GenerationResult(
                text = response,
                tokensUsed = calculateTokens(prompt, response),
                latencyMs = System.currentTimeMillis() - session.startTime,
                sessionId = sessionId,
                model = resolvedOptions.model
            )

            // Publish generation completed event
            publishGenerationCompleted(sessionId, result)

            return result

        } catch (e: Exception) {
            logger.error("Generation failed for session $sessionId: ${e.message}")
            publishGenerationFailed(sessionId, e)
            throw e
        } finally {
            mutex.withLock {
                activeSessions.remove(sessionId)
            }
        }
    }

    /**
     * Stream text generation with RunAnywhereGenerationOptions
     */
    fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): Flow<GenerationChunk> {
        val convertedOptions = GenerationOptions(
            temperature = options.temperature,
            maxTokens = options.maxTokens,
            streaming = true
        )
        return streamGenerate(prompt, convertedOptions)
    }
    
    /**
     * Stream text generation
     */
    fun streamGenerate(
        prompt: String,
        options: GenerationOptions? = null
    ): Flow<GenerationChunk> = flow {
        val resolvedOptions = optionsResolver.resolve(options)
        val sessionId = createSessionId()

        logger.info("Starting streaming generation session: $sessionId")

        val session = GenerationSession(
            id = sessionId,
            prompt = prompt,
            options = resolvedOptions,
            startTime = System.currentTimeMillis(),
            isStreaming = true
        )

        mutex.withLock {
            activeSessions[sessionId] = session
        }

        try {
            // Publish generation started event
            publishGenerationStarted(sessionId, prompt)

            // Stream generation
            streamingService.stream(prompt, resolvedOptions).collect { chunk ->
                emit(chunk)

                // Update session with partial response
                session.partialResponse += chunk.text
            }

            // Publish generation completed event
            val result = GenerationResult(
                text = session.partialResponse,
                tokensUsed = calculateTokens(prompt, session.partialResponse),
                latencyMs = System.currentTimeMillis() - session.startTime,
                sessionId = sessionId,
                model = resolvedOptions.model
            )
            publishGenerationCompleted(sessionId, result)

        } catch (e: Exception) {
            logger.error("Streaming generation failed for session $sessionId: ${e.message}")
            publishGenerationFailed(sessionId, e)
            throw e
        } finally {
            mutex.withLock {
                activeSessions.remove(sessionId)
            }
        }
    }

    /**
     * Cancel an active generation session
     */
    suspend fun cancelGeneration(sessionId: String): Boolean {
        return mutex.withLock {
            activeSessions.remove(sessionId)?.let { session ->
                logger.info("Cancelled generation session: $sessionId")
                publishGenerationCancelled(sessionId)
                true
            } ?: false
        }
    }

    /**
     * Get active generation sessions
     */
    fun getActiveSessions(): List<GenerationSession> {
        return activeSessions.values.toList()
    }

    // Private helpers

    private suspend fun performGeneration(
        prompt: String,
        options: GenerationOptions
    ): String {
        // Use LLM component for actual generation
        val component = llmComponent ?: throw IllegalStateException("LLM component not initialized")
        
        // Convert GenerationOptions to RunAnywhereGenerationOptions
        val llmOptions = RunAnywhereGenerationOptions(
            maxTokens = options.maxTokens,
            temperature = options.temperature,
            streamingEnabled = options.streaming
        )
        
        // Generate using LLM component
        val result = component.generate(prompt)
        return result.text
    }

    private fun calculateTokens(prompt: String, response: String): Int {
        // Simple token estimation (4 chars per token on average)
        return (prompt.length + response.length) / 4
    }

    private fun createSessionId(): String {
        return "gen_${System.currentTimeMillis()}_${(0..9999).random()}"
    }

    private fun publishGenerationStarted(sessionId: String, prompt: String) {
        EventBus.publish(SDKGenerationEvent.Started(prompt, sessionId))
        logger.debug("Generation started: $sessionId")
    }

    private fun publishGenerationCompleted(sessionId: String, result: GenerationResult) {
        EventBus.publish(SDKGenerationEvent.Completed(result.text, result.tokensUsed, result.latencyMs.toDouble()))
        logger.debug("Generation completed: $sessionId")
    }

    private fun publishGenerationFailed(sessionId: String, error: Exception) {
        EventBus.publish(SDKGenerationEvent.Failed(error))
        logger.debug("Generation failed: $sessionId - ${error.message}")
    }

    private fun publishGenerationCancelled(sessionId: String) {
        EventBus.publish(SDKGenerationEvent.Cancelled(sessionId))
        logger.debug("Generation cancelled: $sessionId")
    }

    /**
     * Cancel the current generation session
     */
    fun cancelCurrent() {
        currentSessionId?.let { sessionId ->
            activeSessions.remove(sessionId)
            currentSessionId = null
            publishGenerationCancelled(sessionId)
        }
    }
    
    /**
     * Set the currently loaded model - matches iOS API
     */
    fun setCurrentModel(model: LoadedModelWithService?) {
        currentModel = model
        if (model != null) {
            logger.info("Current model set to: ${model.model.id}")
        } else {
            logger.info("Current model cleared")
        }
    }
    
    /**
     * Get the currently loaded model - matches iOS API
     */
    fun getCurrentModel(): LoadedModelWithService? {
        return currentModel
    }
    
    /**
     * Initialize the generation service with an LLM component
     */
    fun initializeWithLLMComponent(component: LLMComponent) {
        llmComponent = component
        logger.info("GenerationService initialized with LLM component")
    }
    
    /**
     * Check if the service is ready for generation
     */
    fun isReady(): Boolean {
        return llmComponent?.isReady == true
    }
}

/**
 * Generation session tracking
 */
data class GenerationSession(
    val id: String,
    val prompt: String,
    val options: GenerationOptions,
    val startTime: Long,
    val isStreaming: Boolean = false,
    var partialResponse: String = ""
)

/**
 * Generation result
 */
data class GenerationResult(
    val text: String,
    val tokensUsed: Int,
    val latencyMs: Long,
    val sessionId: String,
    val model: String?,
    val savedAmount: Double = 0.0
)

/**
 * Generation chunk for streaming
 */
data class GenerationChunk(
    val text: String,
    val isComplete: Boolean = false,
    val tokenCount: Int = 0
)

/**
 * Generation options
 */
data class GenerationOptions(
    val model: String? = null,
    val temperature: Float = 0.7f,
    val maxTokens: Int = 1000,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val stopSequences: List<String> = emptyList(),
    val streaming: Boolean = false,
    val seed: Int? = null
)
