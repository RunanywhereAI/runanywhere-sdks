package com.runanywhere.sdk.generation

import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.LLMGenerationOptions
import com.runanywhere.sdk.models.LoadedModelWithService
import com.runanywhere.sdk.services.analytics.PerformanceMetrics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch

/**
 * Service for handling streaming text generation
 */
class StreamingService {
    private val logger = SDKLogger("StreamingService")
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Reference to the currently loaded model and service
    private var currentModel: LoadedModelWithService? = null

    /**
     * Set the current loaded model for streaming
     */
    fun setLoadedModel(model: LoadedModelWithService?) {
        currentModel = model
        if (model != null) {
            logger.info("StreamingService: Model set to ${model.model.id}")
        } else {
            logger.info("StreamingService: Model cleared")
        }
    }

    /**
     * Stream text generation with the specified prompt and options
     * Now uses proper chat template formatting via EnhancedLLMService
     */
    fun stream(
        prompt: String,
        options: GenerationOptions,
    ): Flow<GenerationChunk> =
        flow {
            val model =
                currentModel
                    ?: throw IllegalStateException("No model loaded for streaming. Call loadModel() first.")

            logger.info("🚀 Starting streaming with model: ${model.model.id}")
            logger.info("📝 User prompt: $prompt")

            // Track analytics
            val generationId = "gen_${currentTimeMillis()}_${(0..9999).random()}"
            val startTime = currentTimeMillis()
            var timeToFirstTokenMs: Double? = null

            // Convert to LLMGenerationOptions
            val llmOptions =
                LLMGenerationOptions(
                    temperature = options.temperature,
                    maxTokens = options.maxTokens,
                    streamingEnabled = true,
                )

            // Get LLM service - all services now support chat templates automatically
            val llmService =
                model.service as? LLMService
                    ?: throw IllegalStateException("Loaded service is not an LLM service")

            logger.info("✅ Streaming with automatic chat template support")

            try {
                // Use streamGenerate - it now automatically applies chat templates internally
                // The user just passes a simple prompt, and the SDK handles everything
                val fullText = StringBuilder()
                var firstTokenReceived = false

                llmService.streamGenerate(prompt, llmOptions) { token ->
                    // Track time to first token (matches iOS analytics)
                    if (!firstTokenReceived) {
                        timeToFirstTokenMs = (currentTimeMillis() - startTime).toDouble()
                        firstTokenReceived = true
                    }
                    fullText.append(token)
                }

                val generatedText = fullText.toString()
                val latencyMs = currentTimeMillis() - startTime

                emit(
                    GenerationChunk(
                        text = generatedText,
                        tokenCount = generatedText.length / 4,
                        isComplete = true,
                    ),
                )

                // Submit analytics after successful generation (non-blocking)
                submitAnalytics(
                    generationId = generationId,
                    modelName = model.model.name, // Use human-readable name instead of hash ID
                    prompt = prompt,
                    response = generatedText,
                    latencyMs = latencyMs,
                    timeToFirstTokenMs = timeToFirstTokenMs,
                    success = true,
                )
            } catch (e: Exception) {
                val latencyMs = currentTimeMillis() - startTime

                // Submit analytics for failure (non-blocking)
                submitAnalytics(
                    generationId = generationId,
                    modelName = model.model.name, // Use human-readable name instead of hash ID
                    prompt = prompt,
                    response = "",
                    latencyMs = latencyMs,
                    timeToFirstTokenMs = timeToFirstTokenMs,
                    success = false,
                )

                throw e
            }
        }

    /**
     * Submit analytics for generation (non-blocking)
     * Matches iOS and GenerationService patterns
     */
    private fun submitAnalytics(
        generationId: String,
        modelName: String,
        prompt: String,
        response: String,
        latencyMs: Long,
        timeToFirstTokenMs: Double?,
        success: Boolean,
    ) {
        val analytics = ServiceContainer.shared.analyticsService
        if (analytics == null) {
            logger.debug("⚠️ Analytics service not available, skipping analytics submission")
            return
        }

        logger.debug(
            "📊 Submitting stream analytics: generationId=$generationId, modelName=$modelName, success=$success, timeToFirstToken=${timeToFirstTokenMs}ms",
        )

        // Non-blocking background submission
        serviceScope.launch {
            try {
                val inputTokens = prompt.split(Regex("\\s+")).size.coerceAtLeast(1)
                val outputTokens = if (success) response.split(Regex("\\s+")).size.coerceAtLeast(1) else 0
                val tokensPerSecond =
                    if (latencyMs > 0 && outputTokens > 0) {
                        (outputTokens / (latencyMs / 1000.0))
                    } else {
                        0.0
                    }

                val performanceMetrics =
                    PerformanceMetrics(
                        inferenceTimeMs = latencyMs.toDouble(),
                        tokensPerSecond = tokensPerSecond,
                        timeToFirstTokenMs = timeToFirstTokenMs, // Now passing actual value
                    )

                analytics.submitGenerationAnalytics(
                    generationId = generationId,
                    modelId = modelName, // Using human-readable model name
                    performanceMetrics = performanceMetrics,
                    inputTokens = inputTokens,
                    outputTokens = outputTokens,
                    success = success,
                    executionTarget = "onDevice",
                )

                logger.debug("✅ Analytics submitted successfully for generation: $generationId")
            } catch (e: Exception) {
                logger.debug("Analytics submission failed (non-critical): ${e.message}")
            }
        }
    }

    /**
     * Cancel current streaming operation
     */
    fun cancelCurrent() {
        // Cancel current streaming operation
        logger.info("Streaming operation cancelled")
    }
}
