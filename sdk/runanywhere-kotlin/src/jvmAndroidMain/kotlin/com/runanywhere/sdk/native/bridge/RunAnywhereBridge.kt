/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JNI Bridge for runanywhere-commons C API.
 * Contains external function declarations for all rac_* C API functions.
 *
 * This object provides the low-level JNI bindings that are consumed by
 * the higher-level CppBridge extensions.
 *
 * IMPORTANT: This is a low-level API. For application-level usage, use
 * [CppBridge] which provides a higher-level, type-safe interface with
 * proper initialization ordering and lifecycle management.
 */

package com.runanywhere.sdk.native.bridge

/**
 * RunAnywhereBridge provides low-level JNI bindings for the runanywhere-commons C API.
 *
 * This object contains external function declarations that map to the C API
 * exported by librunanywhere_commons. The native library must be loaded
 * before calling any of these functions.
 *
 * ## Recommended Usage
 *
 * **DO NOT** use this class directly in application code. Instead, use
 * [CppBridge][com.runanywhere.sdk.foundation.bridge.CppBridge] which provides:
 * - Automatic initialization ordering (platform adapter first)
 * - Two-phase initialization (core, then services)
 * - Type-safe component wrappers (CppBridge.LLM, CppBridge.STT, etc.)
 * - Proper lifecycle management and cleanup
 *
 * ## Internal Usage
 *
 * This class is intended for use by CppBridge extensions only:
 * - CppBridge extensions use these JNI functions internally
 * - The native library is loaded via [NativeLoader]
 * - Platform adapter must be registered before calling rac_init()
 *
 * ## Thread Safety
 *
 * These JNI functions are thread-safe as they wrap thread-safe C++ code.
 *
 * @see com.runanywhere.sdk.foundation.bridge.CppBridge
 */
object RunAnywhereBridge {

    // ========================================================================
    // NATIVE LIBRARY LOADING
    // ========================================================================

    /**
     * Whether the native library has been loaded.
     */
    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    /**
     * Load the native library if not already loaded.
     *
     * @return true if the library is loaded, false otherwise
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            try {
                System.loadLibrary("runanywhere_jni")
                nativeLibraryLoaded = true
                return true
            } catch (e: UnsatisfiedLinkError) {
                System.err.println("RunAnywhereBridge: Failed to load native library: ${e.message}")
                return false
            }
        }
    }

    /**
     * Check if the unified JNI library is loaded.
     * @deprecated Use [ensureNativeLibraryLoaded] instead
     */
    @Deprecated("Use ensureNativeLibraryLoaded()", ReplaceWith("ensureNativeLibraryLoaded()"))
    fun isLoaded(): Boolean = nativeLibraryLoaded

    /**
     * Load the unified JNI bridge library.
     * @deprecated Use [ensureNativeLibraryLoaded] instead
     */
    @Deprecated("Use ensureNativeLibraryLoaded()", ReplaceWith("ensureNativeLibraryLoaded()"))
    @Synchronized
    fun loadLibrary() {
        ensureNativeLibraryLoaded()
    }

    // ========================================================================
    // CORE INITIALIZATION FUNCTIONS
    // ========================================================================

    /**
     * Initialize the runanywhere-commons C++ library.
     *
     * This must be called before any other rac_* functions (except rac_set_platform_adapter
     * which must be called BEFORE this).
     *
     * CRITICAL: Platform adapter must be registered via [racSetPlatformAdapter] before
     * calling this function.
     *
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_init()
     */
    @JvmStatic
    external fun racInit(): Int

    /**
     * Shutdown the runanywhere-commons C++ library and release all resources.
     *
     * After calling this, no other rac_* functions should be called until
     * [racInit] is called again.
     *
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_shutdown()
     */
    @JvmStatic
    external fun racShutdown(): Int

    /**
     * Check if the runanywhere-commons C++ library is initialized.
     *
     * @return true if initialized, false otherwise
     *
     * C API: rac_is_initialized()
     */
    @JvmStatic
    external fun racIsInitialized(): Boolean

    // ========================================================================
    // PLATFORM ADAPTER FUNCTIONS
    // ========================================================================

    /**
     * Set the platform adapter for the C++ library.
     *
     * CRITICAL: This MUST be called BEFORE [racInit].
     *
     * The platform adapter provides callbacks for platform-specific operations:
     * - Logging: Route C++ logs to Kotlin logging system
     * - File Operations: fileExists, fileRead, fileWrite, fileDelete
     * - Secure Storage: secureGet, secureSet, secureDelete
     * - Clock: nowMs (current timestamp)
     *
     * @param adapter The platform adapter object reference (JNI global ref)
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_set_platform_adapter(rac_platform_adapter_t* adapter)
     */
    @JvmStatic
    external fun racSetPlatformAdapter(adapter: Any): Int

    /**
     * Get the currently registered platform adapter.
     *
     * @return The platform adapter object, or null if not set
     *
     * C API: rac_get_platform_adapter()
     */
    @JvmStatic
    external fun racGetPlatformAdapter(): Any?

    // ========================================================================
    // LOGGING CONFIGURATION
    // ========================================================================

    /**
     * Log level constants matching C++ RAC_LOG_LEVEL_* values.
     */
    object LogLevel {
        /** Most verbose logging - typically disabled in production */
        const val TRACE = 0

        /** Debug information for development */
        const val DEBUG = 1

        /** General information messages */
        const val INFO = 2

        /** Warning messages for potentially problematic situations */
        const val WARN = 3

        /** Error messages for failures that may be recoverable */
        const val ERROR = 4

        /** Fatal errors that require immediate attention */
        const val FATAL = 5
    }

    /**
     * Configure logging for the C++ library.
     *
     * Sets the minimum log level and optional log file path.
     *
     * @param level The minimum log level to output (see [LogLevel] constants)
     * @param logFilePath Optional path to a log file (null for no file logging)
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_configure_logging(int level, const char* log_file_path)
     */
    @JvmStatic
    external fun racConfigureLogging(level: Int, logFilePath: String?): Int

    /**
     * Log a message to the C++ logging system.
     *
     * @param level The log level (see [LogLevel] constants)
     * @param tag The log tag/category
     * @param message The log message
     *
     * C API: rac_log(int level, const char* tag, const char* message)
     */
    @JvmStatic
    external fun racLog(level: Int, tag: String, message: String)

    // ========================================================================
    // ERROR CODE CONSTANTS
    // ========================================================================

    /**
     * Error code constants matching C++ RAC_* return values.
     */
    object ErrorCode {
        /** Operation completed successfully */
        const val SUCCESS = 0

        /** Generic error */
        const val ERROR = -1

        /** Invalid argument provided */
        const val ERROR_INVALID_ARGUMENT = -2

        /** Library not initialized */
        const val ERROR_NOT_INITIALIZED = -3

        /** Already initialized */
        const val ERROR_ALREADY_INITIALIZED = -4

        /** Out of memory */
        const val ERROR_OUT_OF_MEMORY = -5

        /** File not found */
        const val ERROR_FILE_NOT_FOUND = -6

        /** Operation timed out */
        const val ERROR_TIMEOUT = -7

        /** Operation was cancelled */
        const val ERROR_CANCELLED = -8

        /** Network error */
        const val ERROR_NETWORK = -9

        /** Model not loaded */
        const val ERROR_MODEL_NOT_LOADED = -10

        /** Model load failed */
        const val ERROR_MODEL_LOAD_FAILED = -11

        /** Platform adapter not set */
        const val ERROR_PLATFORM_ADAPTER_NOT_SET = -12

        /** Invalid handle */
        const val ERROR_INVALID_HANDLE = -13

        /**
         * Check if an error code indicates success.
         */
        fun isSuccess(code: Int): Boolean = code == SUCCESS

        /**
         * Check if an error code indicates failure.
         */
        fun isError(code: Int): Boolean = code < SUCCESS
    }

    // ========================================================================
    // LLM COMPONENT JNI BINDINGS
    // ========================================================================

    /**
     * Create a new LLM component instance.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_llm_component_create()
     */
    @JvmStatic
    external fun racLlmComponentCreate(): Long

    /**
     * Destroy an LLM component instance and release resources.
     *
     * @param handle The component handle
     *
     * C API: rac_llm_component_destroy(handle)
     */
    @JvmStatic
    external fun racLlmComponentDestroy(handle: Long)

    /**
     * Load a model into the LLM component.
     *
     * @param handle The component handle
     * @param modelPath Path to the model file
     * @param configJson JSON configuration string
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_llm_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun racLlmComponentLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Unload the model from the LLM component.
     *
     * @param handle The component handle
     *
     * C API: rac_llm_component_unload(handle)
     */
    @JvmStatic
    external fun racLlmComponentUnload(handle: Long)

    /**
     * Generate text from a prompt.
     *
     * @param handle The component handle
     * @param prompt The input prompt
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_llm_component_generate(handle, prompt, config)
     */
    @JvmStatic
    external fun racLlmComponentGenerate(handle: Long, prompt: String, configJson: String): String?

    /**
     * Generate text with streaming output.
     *
     * @param handle The component handle
     * @param prompt The input prompt
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_llm_component_generate_stream(handle, prompt, config)
     */
    @JvmStatic
    external fun racLlmComponentGenerateStream(handle: Long, prompt: String, configJson: String): String?

    /**
     * Cancel an ongoing LLM generation.
     *
     * @param handle The component handle
     *
     * C API: rac_llm_component_cancel(handle)
     */
    @JvmStatic
    external fun racLlmComponentCancel(handle: Long)

    /**
     * Get the context size of the loaded LLM model.
     *
     * @param handle The component handle
     * @return The context size in tokens, or 0 if no model loaded
     *
     * C API: rac_llm_component_get_context_size(handle)
     */
    @JvmStatic
    external fun racLlmComponentGetContextSize(handle: Long): Int

    /**
     * Tokenize text using the loaded LLM model.
     *
     * @param handle The component handle
     * @param text The text to tokenize
     * @return The number of tokens
     *
     * C API: rac_llm_component_tokenize(handle, text)
     */
    @JvmStatic
    external fun racLlmComponentTokenize(handle: Long, text: String): Int

    /**
     * Get the LLM component state.
     *
     * @param handle The component handle
     * @return The component state (see LLMState constants)
     *
     * C API: rac_llm_component_get_state(handle)
     */
    @JvmStatic
    external fun racLlmComponentGetState(handle: Long): Int

    /**
     * Check if the LLM component has a model loaded.
     *
     * @param handle The component handle
     * @return true if a model is loaded
     *
     * C API: rac_llm_component_is_loaded(handle)
     */
    @JvmStatic
    external fun racLlmComponentIsLoaded(handle: Long): Boolean

    /**
     * Set LLM component callbacks.
     *
     * @param streamCallback The streaming token callback object
     * @param progressCallback The progress callback object
     *
     * C API: rac_llm_set_callbacks(...)
     */
    @JvmStatic
    external fun racLlmSetCallbacks(streamCallback: Any?, progressCallback: Any?)

    // ========================================================================
    // STT COMPONENT JNI BINDINGS
    // ========================================================================

    /**
     * Create a new STT component instance.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_stt_component_create()
     */
    @JvmStatic
    external fun racSttComponentCreate(): Long

    /**
     * Destroy an STT component instance and release resources.
     *
     * @param handle The component handle
     *
     * C API: rac_stt_component_destroy(handle)
     */
    @JvmStatic
    external fun racSttComponentDestroy(handle: Long)

    /**
     * Load a model into the STT component.
     *
     * @param handle The component handle
     * @param modelPath Path to the model file
     * @param configJson JSON configuration string
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_stt_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun racSttComponentLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Unload the model from the STT component.
     *
     * @param handle The component handle
     *
     * C API: rac_stt_component_unload(handle)
     */
    @JvmStatic
    external fun racSttComponentUnload(handle: Long)

    /**
     * Transcribe audio data.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_stt_component_transcribe(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun racSttComponentTranscribe(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Transcribe audio file.
     *
     * @param handle The component handle
     * @param audioPath Path to the audio file
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_stt_component_transcribe_file(handle, audio_path, config)
     */
    @JvmStatic
    external fun racSttComponentTranscribeFile(handle: Long, audioPath: String, configJson: String): String?

    /**
     * Transcribe audio with streaming output.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_stt_component_transcribe_stream(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun racSttComponentTranscribeStream(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Cancel an ongoing STT transcription.
     *
     * @param handle The component handle
     *
     * C API: rac_stt_component_cancel(handle)
     */
    @JvmStatic
    external fun racSttComponentCancel(handle: Long)

    /**
     * Get the STT component state.
     *
     * @param handle The component handle
     * @return The component state (see STTState constants)
     *
     * C API: rac_stt_component_get_state(handle)
     */
    @JvmStatic
    external fun racSttComponentGetState(handle: Long): Int

    /**
     * Check if the STT component has a model loaded.
     *
     * @param handle The component handle
     * @return true if a model is loaded
     *
     * C API: rac_stt_component_is_loaded(handle)
     */
    @JvmStatic
    external fun racSttComponentIsLoaded(handle: Long): Boolean

    /**
     * Get supported languages for the STT component.
     *
     * @param handle The component handle
     * @return JSON array of supported language codes
     *
     * C API: rac_stt_component_get_languages(handle)
     */
    @JvmStatic
    external fun racSttComponentGetLanguages(handle: Long): String?

    /**
     * Detect language from audio sample.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @return Detected language code
     *
     * C API: rac_stt_component_detect_language(handle, audio_data, audio_size)
     */
    @JvmStatic
    external fun racSttComponentDetectLanguage(handle: Long, audioData: ByteArray): String?

    /**
     * Set STT component callbacks.
     *
     * @param partialCallback The partial result callback object
     * @param progressCallback The progress callback object
     *
     * C API: rac_stt_set_callbacks(...)
     */
    @JvmStatic
    external fun racSttSetCallbacks(partialCallback: Any?, progressCallback: Any?)

    // ========================================================================
    // TTS COMPONENT JNI BINDINGS
    // ========================================================================

    /**
     * Create a new TTS component instance.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_tts_component_create()
     */
    @JvmStatic
    external fun racTtsComponentCreate(): Long

    /**
     * Destroy a TTS component instance and release resources.
     *
     * @param handle The component handle
     *
     * C API: rac_tts_component_destroy(handle)
     */
    @JvmStatic
    external fun racTtsComponentDestroy(handle: Long)

    /**
     * Load a model into the TTS component.
     *
     * @param handle The component handle
     * @param modelPath Path to the model file
     * @param configJson JSON configuration string
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_tts_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun racTtsComponentLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Unload the model from the TTS component.
     *
     * @param handle The component handle
     *
     * C API: rac_tts_component_unload(handle)
     */
    @JvmStatic
    external fun racTtsComponentUnload(handle: Long)

    /**
     * Synthesize audio from text.
     *
     * @param handle The component handle
     * @param text The input text
     * @param configJson JSON configuration string
     * @return Audio data bytes, or null on failure
     *
     * C API: rac_tts_component_synthesize(handle, text, config)
     */
    @JvmStatic
    external fun racTtsComponentSynthesize(handle: Long, text: String, configJson: String): ByteArray?

    /**
     * Synthesize audio with streaming output.
     *
     * @param handle The component handle
     * @param text The input text
     * @param configJson JSON configuration string
     * @return Final audio data bytes, or null on failure
     *
     * C API: rac_tts_component_synthesize_stream(handle, text, config)
     */
    @JvmStatic
    external fun racTtsComponentSynthesizeStream(handle: Long, text: String, configJson: String): ByteArray?

    /**
     * Synthesize audio to file.
     *
     * @param handle The component handle
     * @param text The input text
     * @param outputPath Path to save the audio file
     * @param configJson JSON configuration string
     * @return Audio duration in milliseconds, or negative error code on failure
     *
     * C API: rac_tts_component_synthesize_to_file(handle, text, output_path, config)
     */
    @JvmStatic
    external fun racTtsComponentSynthesizeToFile(handle: Long, text: String, outputPath: String, configJson: String): Long

    /**
     * Cancel an ongoing TTS synthesis.
     *
     * @param handle The component handle
     *
     * C API: rac_tts_component_cancel(handle)
     */
    @JvmStatic
    external fun racTtsComponentCancel(handle: Long)

    /**
     * Get the TTS component state.
     *
     * @param handle The component handle
     * @return The component state (see TTSState constants)
     *
     * C API: rac_tts_component_get_state(handle)
     */
    @JvmStatic
    external fun racTtsComponentGetState(handle: Long): Int

    /**
     * Check if the TTS component has a model loaded.
     *
     * @param handle The component handle
     * @return true if a model is loaded
     *
     * C API: rac_tts_component_is_loaded(handle)
     */
    @JvmStatic
    external fun racTtsComponentIsLoaded(handle: Long): Boolean

    /**
     * Get available voices for the TTS component.
     *
     * @param handle The component handle
     * @return JSON array of voice information
     *
     * C API: rac_tts_component_get_voices(handle)
     */
    @JvmStatic
    external fun racTtsComponentGetVoices(handle: Long): String?

    /**
     * Set the active voice for the TTS component.
     *
     * @param handle The component handle
     * @param voiceId The voice ID to use
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_tts_component_set_voice(handle, voice_id)
     */
    @JvmStatic
    external fun racTtsComponentSetVoice(handle: Long, voiceId: String): Int

    /**
     * Get supported languages for the TTS component.
     *
     * @param handle The component handle
     * @return JSON array of supported language codes
     *
     * C API: rac_tts_component_get_languages(handle)
     */
    @JvmStatic
    external fun racTtsComponentGetLanguages(handle: Long): String?

    /**
     * Set TTS component callbacks.
     *
     * @param audioCallback The audio chunk callback object
     * @param progressCallback The progress callback object
     *
     * C API: rac_tts_set_callbacks(...)
     */
    @JvmStatic
    external fun racTtsSetCallbacks(audioCallback: Any?, progressCallback: Any?)

    // ========================================================================
    // VAD COMPONENT JNI BINDINGS
    // ========================================================================

    /**
     * Create a new VAD component instance.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_vad_component_create()
     */
    @JvmStatic
    external fun racVadComponentCreate(): Long

    /**
     * Destroy a VAD component instance and release resources.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_destroy(handle)
     */
    @JvmStatic
    external fun racVadComponentDestroy(handle: Long)

    /**
     * Load a model into the VAD component.
     *
     * @param handle The component handle
     * @param modelPath Path to the model file
     * @param configJson JSON configuration string
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_vad_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun racVadComponentLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Unload the model from the VAD component.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_unload(handle)
     */
    @JvmStatic
    external fun racVadComponentUnload(handle: Long)

    /**
     * Process audio data for voice activity detection.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_vad_component_process(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun racVadComponentProcess(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Process audio with streaming output.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_vad_component_process_stream(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun racVadComponentProcessStream(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Process a single audio frame for real-time detection.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes for the frame
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_vad_component_process_frame(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun racVadComponentProcessFrame(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Cancel an ongoing VAD detection.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_cancel(handle)
     */
    @JvmStatic
    external fun racVadComponentCancel(handle: Long)

    /**
     * Reset the VAD state for a new stream.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_reset(handle)
     */
    @JvmStatic
    external fun racVadComponentReset(handle: Long)

    /**
     * Get the VAD component state.
     *
     * @param handle The component handle
     * @return The component state (see VADState constants)
     *
     * C API: rac_vad_component_get_state(handle)
     */
    @JvmStatic
    external fun racVadComponentGetState(handle: Long): Int

    /**
     * Check if the VAD component has a model loaded.
     *
     * @param handle The component handle
     * @return true if a model is loaded
     *
     * C API: rac_vad_component_is_loaded(handle)
     */
    @JvmStatic
    external fun racVadComponentIsLoaded(handle: Long): Boolean

    /**
     * Get the minimum frame size for VAD processing.
     *
     * @param handle The component handle
     * @return The minimum frame size in samples
     *
     * C API: rac_vad_component_get_min_frame_size(handle)
     */
    @JvmStatic
    external fun racVadComponentGetMinFrameSize(handle: Long): Int

    /**
     * Get supported sample rates for the VAD component.
     *
     * @param handle The component handle
     * @return JSON array of supported sample rates
     *
     * C API: rac_vad_component_get_sample_rates(handle)
     */
    @JvmStatic
    external fun racVadComponentGetSampleRates(handle: Long): String?

    /**
     * Set VAD component callbacks.
     *
     * @param frameCallback The frame result callback object
     * @param speechStartCallback The speech start callback object
     * @param speechEndCallback The speech end callback object
     * @param progressCallback The progress callback object
     *
     * C API: rac_vad_set_callbacks(...)
     */
    @JvmStatic
    external fun racVadSetCallbacks(
        frameCallback: Any?,
        speechStartCallback: Any?,
        speechEndCallback: Any?,
        progressCallback: Any?
    )

    // ========================================================================
    // AI COMPONENT STATE CONSTANTS
    // ========================================================================

    // ========================================================================
    // BACKEND REGISTRATION JNI BINDINGS
    // ========================================================================

    /**
     * Register the LlamaCPP backend with the C++ service registry.
     *
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_backend_llamacpp_register()
     */
    @JvmStatic
    external fun racBackendLlamacppRegister(): Int

    /**
     * Unregister the LlamaCPP backend from the C++ service registry.
     *
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_backend_llamacpp_unregister()
     */
    @JvmStatic
    external fun racBackendLlamacppUnregister(): Int

    /**
     * Register the ONNX backend with the C++ service registry.
     *
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_backend_onnx_register()
     */
    @JvmStatic
    external fun racBackendOnnxRegister(): Int

    /**
     * Unregister the ONNX backend from the C++ service registry.
     *
     * @return RAC_SUCCESS (0) on success, error code otherwise
     *
     * C API: rac_backend_onnx_unregister()
     */
    @JvmStatic
    external fun racBackendOnnxUnregister(): Int

    // ========================================================================
    // AI COMPONENT STATE CONSTANTS
    // ========================================================================

    /**
     * AI component state constants matching C++ RAC_COMPONENT_STATE_* values.
     * Used for LLM, STT, TTS, and VAD components.
     */
    object ComponentState {
        /** Component not created */
        const val NOT_CREATED = 0

        /** Component created but no model loaded */
        const val CREATED = 1

        /** Model is loading */
        const val LOADING = 2

        /** Model loaded and ready for processing */
        const val READY = 3

        /** Processing in progress (generating/transcribing/synthesizing/detecting) */
        const val PROCESSING = 4

        /** Model is unloading */
        const val UNLOADING = 5

        /** Component in error state */
        const val ERROR = 6

        /**
         * Get a human-readable name for the component state.
         */
        fun getName(state: Int): String = when (state) {
            NOT_CREATED -> "NOT_CREATED"
            CREATED -> "CREATED"
            LOADING -> "LOADING"
            READY -> "READY"
            PROCESSING -> "PROCESSING"
            UNLOADING -> "UNLOADING"
            ERROR -> "ERROR"
            else -> "UNKNOWN($state)"
        }

        /**
         * Check if the state indicates the component is usable.
         */
        fun isReady(state: Int): Boolean = state == READY
    }
}
