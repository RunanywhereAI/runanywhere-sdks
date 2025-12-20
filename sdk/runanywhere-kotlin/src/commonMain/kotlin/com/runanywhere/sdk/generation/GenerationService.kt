package com.runanywhere.sdk.generation

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.events.SDKGenerationEvent
import com.runanywhere.sdk.models.LoadedModelWithService
import com.runanywhere.sdk.features.llm.LLMComponent
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.models.LLMGenerationOptions
import com.runanywhere.sdk.services.analytics.AnalyticsService
import com.runanywhere.sdk.services.analytics.PerformanceMetrics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

/**
 * Service for text generation with LLM models
 * Handles both streaming and non-streaming generation
 * Automatically submits analytics (matching iOS GenerationService)
 *
 * Reference: iOS GenerationService.swift
 */
class GenerationService(
    private val streamingService: StreamingService = StreamingService()
) {

    private val logger = SDKLogger("GenerationService")
    private val optionsResolver = GenerationOptionsResolver()
    private val mutex = Mutex()
    private val analyticsScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // Track active generation sessions
    private val activeSessions = mutableMapOf<String, GenerationSession>()
    private var currentSessionId: String? = null

    // Track currently loaded model
    private var currentModel: LoadedModelWithService? = null

    // LLM component for actual generation
    private var llmComponent: LLMComponent? = null

    /**
     * Generate text with LLMGenerationOptions
     */
    suspend fun generate(
        prompt: String,
        options: LLMGenerationOptions
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

            // Submit analytics (non-blocking, matching iOS pattern)
            submitGenerationAnalytics(
                generationId = sessionId,
                modelId = currentModel?.model?.id ?: "unknown",
                prompt = prompt,
                response = response,
                latencyMs = result.latencyMs,
                success = true
            )

            return result

        } catch (e: Exception) {
            logger.error("Generation failed for session $sessionId: ${e.message}")
            publishGenerationFailed(sessionId, e)

            // Submit analytics for failure
            submitGenerationAnalytics(
                generationId = sessionId,
                modelId = currentModel?.model?.id ?: "unknown",
                prompt = prompt,
                response = "",
                latencyMs = System.currentTimeMillis() - session.startTime,
                success = false
            )

            throw e
        } finally {
            mutex.withLock {
                activeSessions.remove(sessionId)
            }
        }
    }

    /**
     * Stream text generation with LLMGenerationOptions
     */
    fun streamGenerate(
        prompt: String,
        options: LLMGenerationOptions
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

            // Submit analytics (non-blocking, matching iOS pattern and non-streaming generate())
            submitGenerationAnalytics(
                generationId = sessionId,
                modelId = currentModel?.model?.id ?: "unknown",
                prompt = prompt,
                response = session.partialResponse,
                latencyMs = result.latencyMs,
                success = true
            )

        } catch (e: Exception) {
            logger.error("Streaming generation failed for session $sessionId: ${e.message}")
            publishGenerationFailed(sessionId, e)

            // Submit analytics for failure (matching non-streaming generate())
            submitGenerationAnalytics(
                generationId = sessionId,
                modelId = currentModel?.model?.id ?: "unknown",
                prompt = prompt,
                response = "",
                latencyMs = System.currentTimeMillis() - session.startTime,
                success = false
            )

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

        // Convert GenerationOptions to LLMGenerationOptions
        val llmOptions = LLMGenerationOptions(
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
        EventPublisher.track(SDKGenerationEvent.Started(prompt, sessionId))
        logger.debug("Generation started: $sessionId")
    }

    private fun publishGenerationCompleted(sessionId: String, result: GenerationResult) {
        EventPublisher.track(SDKGenerationEvent.Completed(result.text, result.tokensUsed, result.latencyMs.toDouble()))
        logger.debug("Generation completed: $sessionId")
    }

    private fun publishGenerationFailed(sessionId: String, error: Exception) {
        EventPublisher.track(SDKGenerationEvent.Failed(error))
        logger.debug("Generation failed: $sessionId - ${error.message}")
    }

    private fun publishGenerationCancelled(sessionId: String) {
        EventPublisher.track(SDKGenerationEvent.Cancelled(sessionId))
        logger.debug("Generation cancelled: $sessionId")
    }

    /**
     * Submit generation analytics (non-blocking)
     * Matches iOS GenerationService analytics submission pattern
     *
     * Reference: iOS GenerationService.swift
     */
    private fun submitGenerationAnalytics(
        generationId: String,
        modelId: String,
        prompt: String,
        response: String,
        latencyMs: Long,
        success: Boolean
    ) {
        // Get analytics service from ServiceContainer
        val analytics = com.runanywhere.sdk.foundation.ServiceContainer.shared.analyticsService
        if (analytics == null) {
            logger.warning("⚠️ Analytics service not available, skipping analytics submission")
            return
        }

        logger.debug("📊 Submitting generation analytics: generationId=$generationId, modelId=$modelId, success=$success")

        // Non-blocking background submission
        analyticsScope.launch {
            try {
                val inputTokens = estimateTokenCount(prompt)
                val outputTokens = if (success) estimateTokenCount(response) else 0
                val tokensPerSecond = if (latencyMs > 0 && outputTokens > 0) {
                    (outputTokens / (latencyMs / 1000.0))
                } else {
                    0.0
                }

                val performanceMetrics = PerformanceMetrics(
                    inferenceTimeMs = latencyMs.toDouble(),
                    tokensPerSecond = tokensPerSecond,
                    timeToFirstTokenMs = null // TODO: Track in streaming
                )

                analytics.submitGenerationAnalytics(
                    generationId = generationId,
                    modelId = modelId,
                    performanceMetrics = performanceMetrics,
                    inputTokens = inputTokens,
                    outputTokens = outputTokens,
                    success = success,
                    executionTarget = "onDevice" // Always on-device for now
                )
            } catch (e: Exception) {
                // Fail silently - analytics should never break generation
                logger.debug("Analytics submission failed (non-critical): ${e.message}")
            }
        }
    }

    /**
     * Estimate token count for text (simple word-based approximation)
     * Matches iOS estimateTokenCount()
     */
    private fun estimateTokenCount(text: String): Int {
        return text.split(Regex("\\s+")).size.coerceAtLeast(1)
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
        // CRITICAL: Also set the model in StreamingService
        streamingService.setLoadedModel(model)

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
