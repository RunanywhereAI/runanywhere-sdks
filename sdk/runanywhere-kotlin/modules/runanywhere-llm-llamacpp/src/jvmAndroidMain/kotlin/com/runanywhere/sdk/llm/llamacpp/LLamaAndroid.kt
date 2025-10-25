package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors
import kotlin.concurrent.thread

/**
 * Configuration for llama.cpp model loading
 */
data class LlamaModelConfig(
    val contextSize: Int = 2048,
    val threads: Int = 0, // 0 = auto-detect
    val temperature: Float = 0.7f,
    val minP: Float = 0.05f,
    val topK: Int = 40
)

/**
 * Low-level llama.cpp Android wrapper
 * Based on the guide's implementation pattern
 */
class LLamaAndroid {
    private val logger = SDKLogger("LLamaAndroid")

    internal val threadLocalState: ThreadLocal<State> = ThreadLocal.withInitial { State.Idle }

    private val runLoop: CoroutineDispatcher = Executors.newSingleThreadExecutor {
        thread(start = false, name = "Llama-RunLoop") {
            logger.info("Dedicated thread for native code: ${Thread.currentThread().name}")

            // Load native library with CPU feature detection
            try {
                loadOptimalLibrary()
                logger.info("Successfully loaded llama-android native library")
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load llama-android native library", e)
                throw e
            }

            // Initialize backend
            log_to_android()
            backend_init(false)

            logger.info(system_info())

            it.run()
        }.apply {
            uncaughtExceptionHandler = Thread.UncaughtExceptionHandler { _, exception: Throwable ->
                logger.error("Unhandled exception in llama thread", exception)
            }
        }
    }.asCoroutineDispatcher()

    private val nlen: Int = 256

    // Native method declarations
    private external fun log_to_android()
    private external fun load_model(filename: String): Long
    private external fun free_model(model: Long)
    private external fun new_context(model: Long, nCtx: Int, nThreads: Int): Long
    private external fun free_context(context: Long)
    private external fun backend_init(numa: Boolean)
    private external fun backend_free()
    private external fun new_batch(nTokens: Int, embd: Int, nSeqMax: Int): Long
    private external fun free_batch(batch: Long)
    private external fun new_sampler(temperature: Float, minP: Float, topK: Int): Long
    private external fun new_sampler_with_grammar(temperature: Float, minP: Float, topK: Int, grammar: Long): Long
    private external fun free_sampler(sampler: Long)
    private external fun system_info(): String

    private external fun completion_init(
        context: Long,
        batch: Long,
        text: String,
        parseSpecialTokens: Boolean,  // Renamed for clarity
        nLen: Int
    ): Int

    private external fun completion_loop(
        context: Long,
        batch: Long,
        sampler: Long,
        nLen: Int,
        ncur: IntVar
    ): String?

    private external fun kv_cache_clear(context: Long)

    private external fun apply_chat_template(
        model: Long,
        templateName: String?,
        messages: Array<com.runanywhere.sdk.models.Message>,
        addAssistantToken: Boolean
    ): String

    /**
     * Apply chat template to messages using the model's built-in template
     * This automatically handles all special tokens and formatting for any model
     *
     * @param messages List of conversation messages
     * @param templateName Optional template name (null = use model's default)
     * @param addAssistantToken Whether to add the assistant generation start token
     * @return Formatted prompt with proper chat template applied
     */
    suspend fun applyChatTemplate(
        messages: List<com.runanywhere.sdk.models.Message>,
        templateName: String? = null,
        addAssistantToken: Boolean = true
    ): String = withContext(runLoop) {
        val state = threadLocalState.get()
        if (state !is State.Loaded) {
            throw IllegalStateException("Model not loaded - cannot apply chat template")
        }

        logger.info("Applying chat template for ${messages.size} messages")
        val result = apply_chat_template(
            state.model,
            templateName,
            messages.toTypedArray(),
            addAssistantToken
        )
        logger.info("Chat template applied, prompt length: ${result.length}")
        result
    }

    /**
     * Load model from file path with configuration
     */
    suspend fun load(pathToModel: String, config: LlamaModelConfig = LlamaModelConfig()) {
        withContext(runLoop) {
            when (threadLocalState.get()) {
                is State.Idle -> {
                    logger.info("Loading model from: $pathToModel")
                    logger.info("Config: contextSize=${config.contextSize}, threads=${config.threads}, " +
                            "temp=${config.temperature}, minP=${config.minP}, topK=${config.topK}")

                    val model = load_model(pathToModel)
                    if (model == 0L) throw IllegalStateException("load_model() failed")

                    val context = new_context(model, config.contextSize, config.threads)
                    if (context == 0L) throw IllegalStateException("new_context() failed")

                    // Fix: Use dynamic batch size matching context size (like SmolChat)
                    val batch = new_batch(config.contextSize, 0, 1)
                    if (batch == 0L) throw IllegalStateException("new_batch() failed")

                    val sampler = new_sampler(config.temperature, config.minP, config.topK)
                    if (sampler == 0L) throw IllegalStateException("new_sampler() failed")

                    logger.info("Model loaded successfully: $pathToModel")
                    threadLocalState.set(State.Loaded(model, context, batch, sampler))
                }
                else -> throw IllegalStateException("Model already loaded")
            }
        }
    }

    /**
     * Generate text from prompt (streaming)
     * @param parseSpecialTokens Whether to parse special tokens (default true for chat templates)
     */
    fun send(message: String, parseSpecialTokens: Boolean = true): Flow<String> = flow {
        when (val state = threadLocalState.get()) {
            is State.Loaded -> {
                val ncur = IntVar(completion_init(state.context, state.batch, message, parseSpecialTokens, nlen))
                while (ncur.value <= nlen) {
                    val str = completion_loop(state.context, state.batch, state.sampler, nlen, ncur)
                    if (str == null) {
                        break
                    }
                    if (str.isNotEmpty()) {
                        emit(str)
                    }
                }
                kv_cache_clear(state.context)
            }
            else -> {
                logger.error("Cannot generate: model not loaded")
                throw IllegalStateException("Model not loaded")
            }
        }
    }.flowOn(runLoop)

    /**
     * Generate text with grammar constraints
     *
     * @param message Prompt to generate from
     * @param grammar Grammar handle for constrained generation
     * @param config Optional model config for temperature/sampling
     * @param parseSpecialTokens Whether to parse special tokens in prompt
     * @return Flow of generated tokens
     */
    fun sendWithGrammar(
        message: String,
        grammar: Long,
        config: LlamaModelConfig? = null,
        parseSpecialTokens: Boolean = true
    ): Flow<String> = flow {
        when (val state = threadLocalState.get()) {
            is State.Loaded -> {
                // Create new sampler with grammar
                val temperature = config?.temperature ?: 0.7f
                val minP = config?.minP ?: 0.05f
                val topK = config?.topK ?: 40

                logger.info("Creating grammar-constrained sampler: temp=$temperature, minP=$minP, topK=$topK, grammar=$grammar")
                val grammarSampler = new_sampler_with_grammar(temperature, minP, topK, grammar)

                try {
                    val ncur = IntVar(completion_init(state.context, state.batch, message, parseSpecialTokens, nlen))
                    while (ncur.value <= nlen) {
                        // Use grammar sampler instead of default sampler
                        val str = completion_loop(state.context, state.batch, grammarSampler, nlen, ncur)
                        if (str == null) {
                            break
                        }
                        if (str.isNotEmpty()) {
                            emit(str)
                        }
                    }
                    kv_cache_clear(state.context)
                } finally {
                    // Free the temporary grammar sampler
                    free_sampler(grammarSampler)
                    logger.debug("Grammar sampler freed")
                }
            }
            else -> {
                logger.error("Cannot generate: model not loaded")
                throw IllegalStateException("Model not loaded")
            }
        }
    }.flowOn(runLoop)

    /**
     * Unload model and free resources
     */
    suspend fun unload() {
        withContext(runLoop) {
            when (val state = threadLocalState.get()) {
                is State.Loaded -> {
                    logger.info("Unloading model")
                    free_context(state.context)
                    free_model(state.model)
                    free_batch(state.batch)
                    free_sampler(state.sampler)

                    threadLocalState.set(State.Idle)
                    logger.info("Model unloaded successfully")
                }
                else -> {
                    logger.debug("No model to unload")
                }
            }
        }
    }

    /**
     * Check if model is loaded
     */
    val isLoaded: Boolean
        get() = threadLocalState.get() is State.Loaded

    /**
     * Load the optimal native library based on CPU features
     * Implements fallback chain: i8mm-sve > sve > i8mm > v8_4 > dotprod > fp16 > baseline
     */
    private fun loadOptimalLibrary() {
        val logger = SDKLogger("LLamaAndroid.LibraryLoader")

        // First load the baseline library to get CPU detection functions
        try {
            System.loadLibrary("llama-android")
            logger.info("Loaded baseline library for CPU detection")

            // Try to detect CPU features and load optimal variant
            try {
                val variant = detectCPUFeatures()
                if (variant.isNotEmpty()) {
                    // Try to load the optimal variant
                    val libraryName = "llama-android$variant"
                    try {
                        System.loadLibrary(libraryName)
                        logger.info("Loaded optimized library: $libraryName")

                        // Log CPU info for debugging
                        val cpuInfo = getCPUInfo()
                        logger.debug("CPU Info:\n$cpuInfo")
                        return
                    } catch (e: UnsatisfiedLinkError) {
                        logger.warn("Optimized library $libraryName not found, using baseline: ${e.message}")
                    }
                } else {
                    logger.info("Using baseline library (no advanced CPU features detected)")
                }
            } catch (e: Exception) {
                logger.warn("CPU feature detection failed, using baseline library: ${e.message}")
            }

            // If we're here, we're using the baseline library (already loaded)
            logger.info("Using baseline llama-android library")

        } catch (e: UnsatisfiedLinkError) {
            logger.error("Failed to load llama-android baseline library", e)
            throw e
        }
    }

    companion object {
        // Helper class for token counting
        class IntVar(initialValue: Int) {
            @Volatile
            var value: Int = initialValue
                private set

            fun inc() {
                synchronized(this) {
                    value += 1
                }
            }

            @JvmName("getValueMethod")
            fun getValue(): Int = value
        }

        // State management
        internal sealed interface State {
            data object Idle : State
            data class Loaded(val model: Long, val context: Long, val batch: Long, val sampler: Long) : State
        }

        // Native CPU detection methods (called via JNI from baseline library)
        // Note: These are external functions on the companion object, not @JvmStatic
        external fun detectCPUFeatures(): String

        external fun getCPUInfo(): String

        // Singleton instance
        private val _instance: LLamaAndroid = LLamaAndroid()

        fun instance(): LLamaAndroid = _instance
    }
}
