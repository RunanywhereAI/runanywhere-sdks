package com.runanywhere.sdk.llm.mlc

import ai.mlc.mlcllm.MLCEngine as NativeMLCEngine
import ai.mlc.mlcllm.OpenAIProtocol
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.channels.ReceiveChannel

/**
 * Wrapper around native MLC-LLM Engine
 *
 * Provides a simplified, thread-safe interface to the native MLC engine
 * for model loading, generation, and resource management.
 *
 * ## Thread Safety
 * All methods are synchronized to ensure thread-safe access to the native engine.
 * The native engine runs background threads for inference and streaming.
 *
 * ## Lifecycle
 * 1. Create engine (constructor)
 * 2. `reload()` to load model
 * 3. `chatCompletion()` for generation
 * 4. `unload()` to free resources
 *
 * ## Native Dependencies
 * Requires:
 * - libtvm4j_runtime_packed.so (TVM runtime)
 * - tvm4j_core.jar (TVM Java bindings)
 * - Model files (params, tokenizer, config)
 * - Model library (.so file compiled for specific model)
 *
 * ## Usage
 * ```kotlin
 * val engine = MLCEngine()
 * try {
 *     engine.reload("/path/to/model", "model_lib_name")
 *
 *     val messages = listOf(
 *         OpenAIProtocol.ChatCompletionMessage(
 *             role = OpenAIProtocol.ChatCompletionRole.user,
 *             content = "Hello!"
 *         )
 *     )
 *
 *     val responses = engine.chatCompletion(messages)
 *     for (response in responses) {
 *         // Process streaming response
 *     }
 * } finally {
 *     engine.unload()
 * }
 * ```
 */
class MLCEngine {

    private val logger = SDKLogger("MLCEngine")
    private val nativeEngine: NativeMLCEngine

    init {
        logger.info("Initializing MLCEngine")
        try {
            nativeEngine = NativeMLCEngine()
            logger.info("MLCEngine initialized successfully")
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Failed to load native MLC library", e)
            throw IllegalStateException(
                "Native MLC library not available. Ensure libtvm4j_runtime_packed.so is in jniLibs.",
                e
            )
        } catch (e: Exception) {
            logger.error("Failed to initialize MLCEngine", e)
            throw IllegalStateException("Failed to initialize MLCEngine: ${e.message}", e)
        }
    }

    /**
     * Load a model into the engine
     *
     * This operation may take several seconds depending on model size.
     * The model must be MLC-compiled and include all necessary files.
     *
     * @param modelPath Absolute path to model directory containing:
     *   - mlc-chat-config.json
     *   - params/ (model weights)
     *   - tokenizer.json and tokenizer_config.json
     * @param modelLib Name of the model library (without lib prefix or .so suffix)
     *   Example: "phi_msft_q4f16_1" for libphi_msft_q4f16_1.so
     *
     * @throws IllegalStateException if model loading fails
     */
    @Synchronized
    fun reload(modelPath: String, modelLib: String) {
        logger.info("Loading model: path=$modelPath, lib=$modelLib")
        try {
            nativeEngine.reload(modelPath, modelLib)
            logger.info("Model loaded successfully")
        } catch (e: Exception) {
            logger.error("Failed to load model", e)
            throw IllegalStateException(
                "Failed to load model at $modelPath with lib $modelLib: ${e.message}",
                e
            )
        }
    }

    /**
     * Reset the engine state (clear KV cache)
     *
     * Clears the conversation history and KV cache without unloading the model.
     * Faster than unload/reload for starting a new conversation.
     */
    @Synchronized
    fun reset() {
        logger.info("Resetting engine state")
        try {
            nativeEngine.reset()
            logger.info("Engine reset successfully")
        } catch (e: Exception) {
            logger.error("Failed to reset engine", e)
            throw IllegalStateException("Failed to reset engine: ${e.message}", e)
        }
    }

    /**
     * Unload the current model and free resources
     *
     * Should be called when done with the model to free GPU/CPU memory.
     * After unloading, `reload()` must be called before generation.
     */
    @Synchronized
    fun unload() {
        logger.info("Unloading model")
        try {
            nativeEngine.unload()
            logger.info("Model unloaded successfully")
        } catch (e: Exception) {
            logger.error("Failed to unload model", e)
            // Don't throw - cleanup should be best-effort
        }
    }

    /**
     * Perform chat completion with streaming responses
     *
     * Generates text using the OpenAI-compatible chat completion API.
     * Returns a channel that streams response chunks as they are generated.
     *
     * @param messages Conversation history including system prompt and user messages
     * @param maxTokens Maximum tokens to generate (null = model default)
     * @param temperature Sampling temperature 0.0-2.0 (null = model default)
     * @param topP Nucleus sampling probability (null = model default)
     * @param stopSequences List of stop sequences (null = model default)
     * @param streamOptions Streaming options (e.g., include usage stats)
     *
     * @return ReceiveChannel streaming ChatCompletionStreamResponse chunks
     * @throws IllegalStateException if no model is loaded
     */
    @Synchronized
    suspend fun chatCompletion(
        messages: List<OpenAIProtocol.ChatCompletionMessage>,
        maxTokens: Int? = null,
        temperature: Float? = null,
        topP: Float? = null,
        stopSequences: List<String>? = null,
        streamOptions: OpenAIProtocol.StreamOptions? = null
    ): ReceiveChannel<OpenAIProtocol.ChatCompletionStreamResponse> {
        logger.info("Starting chat completion: messages=${messages.size}, maxTokens=$maxTokens")
        try {
            val responses = nativeEngine.chat.completions.create(
                messages = messages,
                max_tokens = maxTokens,
                temperature = temperature,
                top_p = topP,
                stop = stopSequences,
                stream = true,  // Always stream in MLC
                stream_options = streamOptions
            )
            logger.info("Chat completion started successfully")
            return responses
        } catch (e: Exception) {
            logger.error("Failed to start chat completion", e)
            throw IllegalStateException("Failed to start chat completion: ${e.message}", e)
        }
    }

    /**
     * Access to native chat.completions API
     *
     * Provides direct access to the underlying MLC engine's chat completions API
     * for advanced use cases.
     */
    val chat: NativeMLCEngine.Chat
        get() = nativeEngine.chat
}
