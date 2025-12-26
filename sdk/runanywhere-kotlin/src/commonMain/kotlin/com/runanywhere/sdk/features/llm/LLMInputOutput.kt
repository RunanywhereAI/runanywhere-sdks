package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.core.capabilities.ComponentInput
import com.runanywhere.sdk.core.capabilities.ComponentOutput
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable

/**
 * Input for Language Model generation - exact match with iOS LLMInput
 * Conforms to ComponentInput protocol
 */
@Serializable
data class LLMInput(
    /** Messages in the conversation */
    val messages: List<Message>,
    /** Optional system prompt override */
    val systemPrompt: String? = null,
    /** Optional context for conversation */
    val context: Context? = null,
    /** Optional generation options override */
    val options: LLMGenerationOptions? = null,
) : ComponentInput {
    /**
     * Convenience constructor for single prompt
     */
    constructor(
        prompt: String,
        systemPrompt: String? = null,
    ) : this(
        messages = listOf(Message(role = MessageRole.USER, content = prompt)),
        systemPrompt = systemPrompt,
        context = null,
        options = null,
    )

    /**
     * Validate the input
     */
    override fun validate() {
        if (messages.isEmpty()) {
            throw SDKError.ValidationFailed("LLMInput must contain at least one message")
        }

        // Validate each message has non-empty content
        messages.forEach { message ->
            if (message.content.isBlank()) {
                throw SDKError.ValidationFailed("Message content cannot be blank")
            }
        }

        // Validate options if provided
        options?.validate()

        // Validate context if provided
        context?.let { ctx ->
            ctx.messages.forEach { message ->
                if (message.content.isBlank()) {
                    throw SDKError.ValidationFailed("Context message content cannot be blank")
                }
            }
        }
    }

    /**
     * Get all messages including context
     */
    fun getAllMessages(): List<Message> {
        val allMessages = mutableListOf<Message>()

        // Add context messages first
        context?.messages?.let { allMessages.addAll(it) }

        // Add current messages
        allMessages.addAll(messages)

        return allMessages
    }

    /**
     * Get effective system prompt (input override or context system prompt)
     */
    fun getEffectiveSystemPrompt(): String? = systemPrompt ?: context?.systemPrompt

    /**
     * Get estimated token count for the entire input
     */
    fun getEstimatedTokenCount(): Int {
        var tokenCount = 0

        // System prompt tokens
        getEffectiveSystemPrompt()?.let { tokenCount += it.length / 4 }

        // Message tokens
        getAllMessages().forEach { message ->
            tokenCount += message.content.length / 4
        }

        return tokenCount
    }
}

/**
 * Output from Language Model generation - exact match with iOS LLMOutput
 * Conforms to ComponentOutput protocol
 */
@Serializable
data class LLMOutput(
    /** Generated text */
    val text: String,
    /** Token usage statistics */
    val tokenUsage: TokenUsage,
    /** Generation metadata */
    val metadata: GenerationMetadata,
    /** Finish reason */
    val finishReason: FinishReason,
    /** Timestamp (required by ComponentOutput) */
    override val timestamp: Long = getCurrentTimeMillis(),
    /** Session ID for tracking */
    val sessionId: String? = null,
    /** Cost savings compared to cloud execution */
    val savedAmount: Double = 0.0,
    /** Execution target that was actually used */
    val actualExecutionTarget: ExecutionTarget? = null,
) : ComponentOutput {
    /**
     * Validate the output
     */
    fun validate() {
        if (text.isEmpty() && finishReason != FinishReason.ERROR) {
            throw SDKError.ValidationFailed("Output text cannot be empty unless generation failed")
        }

        tokenUsage.validate()
        metadata.validate()

        if (timestamp <= 0) {
            throw SDKError.ValidationFailed("Timestamp must be positive")
        }

        if (savedAmount < 0.0) {
            throw SDKError.ValidationFailed("Saved amount must be non-negative")
        }
    }

    /**
     * Check if generation was successful
     */
    val isSuccessful: Boolean
        get() =
            finishReason == FinishReason.COMPLETED ||
                finishReason == FinishReason.MAX_TOKENS ||
                finishReason == FinishReason.STOP_SEQUENCE

    /**
     * Get effective tokens per second
     */
    val effectiveTokensPerSecond: Double?
        get() =
            metadata.tokensPerSecond ?: if (metadata.generationTime > 0) {
                tokenUsage.completionTokens.toDouble() / (metadata.generationTime / 1000.0)
            } else {
                null
            }

    /**
     * Create a Message from this output (for adding to conversation context)
     */
    fun toMessage(): Message =
        Message(
            role = MessageRole.ASSISTANT,
            content = text,
            metadata =
                mapOf(
                    "sessionId" to (sessionId ?: "unknown"),
                    "finishReason" to finishReason.value,
                    "modelId" to metadata.modelId,
                    "tokensUsed" to tokenUsage.totalTokens.toString(),
                ),
            timestamp = timestamp,
        )
}
