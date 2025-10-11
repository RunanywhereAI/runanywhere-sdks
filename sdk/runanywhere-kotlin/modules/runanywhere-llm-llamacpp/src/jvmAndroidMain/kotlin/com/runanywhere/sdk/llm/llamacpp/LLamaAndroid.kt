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
 * Low-level llama.cpp Android wrapper
 * Based on the guide's implementation pattern
 */
class LLamaAndroid {
    private val logger = SDKLogger("LLamaAndroid")

    private val threadLocalState: ThreadLocal<State> = ThreadLocal.withInitial { State.Idle }

    private val runLoop: CoroutineDispatcher = Executors.newSingleThreadExecutor {
        thread(start = false, name = "Llama-RunLoop") {
            logger.info("Dedicated thread for native code: ${Thread.currentThread().name}")

            // Load native library
            try {
                System.loadLibrary("llama-android")
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
    private external fun new_context(model: Long): Long
    private external fun free_context(context: Long)
    private external fun backend_init(numa: Boolean)
    private external fun backend_free()
    private external fun new_batch(nTokens: Int, embd: Int, nSeqMax: Int): Long
    private external fun free_batch(batch: Long)
    private external fun new_sampler(): Long
    private external fun free_sampler(sampler: Long)
    private external fun system_info(): String

    private external fun completion_init(
        context: Long,
        batch: Long,
        text: String,
        formatChat: Boolean,
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

    /**
     * Load model from file path
     */
    suspend fun load(pathToModel: String) {
        withContext(runLoop) {
            when (threadLocalState.get()) {
                is State.Idle -> {
                    logger.info("Loading model from: $pathToModel")

                    val model = load_model(pathToModel)
                    if (model == 0L) throw IllegalStateException("load_model() failed")

                    val context = new_context(model)
                    if (context == 0L) throw IllegalStateException("new_context() failed")

                    val batch = new_batch(512, 0, 1)
                    if (batch == 0L) throw IllegalStateException("new_batch() failed")

                    val sampler = new_sampler()
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
     */
    fun send(message: String, formatChat: Boolean = false): Flow<String> = flow {
        when (val state = threadLocalState.get()) {
            is State.Loaded -> {
                val ncur = IntVar(completion_init(state.context, state.batch, message, formatChat, nlen))
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
        private sealed interface State {
            data object Idle : State
            data class Loaded(val model: Long, val context: Long, val batch: Long, val sampler: Long) : State
        }

        // Singleton instance
        private val _instance: LLamaAndroid = LLamaAndroid()

        fun instance(): LLamaAndroid = _instance
    }
}
