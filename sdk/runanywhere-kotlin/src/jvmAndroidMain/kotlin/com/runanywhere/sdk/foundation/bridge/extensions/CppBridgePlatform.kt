/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform extension for CppBridge.
 * Provides platform services callbacks for C++ core.
 * Android equivalent of iOS Foundation Models integration.
 *
 * Follows iOS CppBridge+Platform.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKError

/**
 * Platform bridge that provides platform services callbacks for C++ core.
 *
 * This is the Android equivalent of iOS Foundation Models integration.
 * It provides callbacks for:
 * - Platform AI model availability checking
 * - Platform LLM inference (e.g., Google AI, on-device models)
 * - Platform TTS services (system TTS)
 * - Platform STT services (system speech recognition)
 * - Platform capabilities detection
 *
 * The C++ core uses these callbacks to:
 * - Query available platform AI capabilities
 * - Delegate inference to platform services when appropriate
 * - Check model availability before fallback to local models
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgeModelAssignment] is registered
 *
 * Thread Safety:
 * - This object is thread-safe via synchronized blocks
 * - All callbacks are thread-safe
 */
object CppBridgePlatform {

    /**
     * Platform service type constants matching C++ RAC_PLATFORM_SERVICE_* values.
     */
    object ServiceType {
        /** No platform service */
        const val NONE = 0

        /** Platform LLM service (e.g., Google AI, Samsung AI) */
        const val LLM = 1

        /** Platform TTS service (system text-to-speech) */
        const val TTS = 2

        /** Platform STT service (system speech recognition) */
        const val STT = 3

        /** Platform embedding service */
        const val EMBEDDING = 4

        /** Platform image generation service */
        const val IMAGE_GENERATION = 5

        /** Platform vision/image understanding service */
        const val VISION = 6

        /**
         * Get a human-readable name for the service type.
         */
        fun getName(type: Int): String = when (type) {
            NONE -> "NONE"
            LLM -> "LLM"
            TTS -> "TTS"
            STT -> "STT"
            EMBEDDING -> "EMBEDDING"
            IMAGE_GENERATION -> "IMAGE_GENERATION"
            VISION -> "VISION"
            else -> "UNKNOWN($type)"
        }
    }

    /**
     * Platform service availability status constants.
     */
    object AvailabilityStatus {
        /** Service availability unknown */
        const val UNKNOWN = 0

        /** Service is available and ready */
        const val AVAILABLE = 1

        /** Service is not available on this device */
        const val NOT_AVAILABLE = 2

        /** Service requires download/installation */
        const val REQUIRES_DOWNLOAD = 3

        /** Service is downloading */
        const val DOWNLOADING = 4

        /** Service is available but requires authentication */
        const val REQUIRES_AUTH = 5

        /** Service is temporarily unavailable */
        const val TEMPORARILY_UNAVAILABLE = 6

        /**
         * Get a human-readable name for the availability status.
         */
        fun getName(status: Int): String = when (status) {
            UNKNOWN -> "UNKNOWN"
            AVAILABLE -> "AVAILABLE"
            NOT_AVAILABLE -> "NOT_AVAILABLE"
            REQUIRES_DOWNLOAD -> "REQUIRES_DOWNLOAD"
            DOWNLOADING -> "DOWNLOADING"
            REQUIRES_AUTH -> "REQUIRES_AUTH"
            TEMPORARILY_UNAVAILABLE -> "TEMPORARILY_UNAVAILABLE"
            else -> "UNKNOWN($status)"
        }

        /**
         * Check if the status indicates the service is usable.
         */
        fun isUsable(status: Int): Boolean = status == AVAILABLE
    }

    /**
     * Platform inference error codes.
     */
    object ErrorCode {
        /** Success */
        const val SUCCESS = 0

        /** Service not available */
        const val SERVICE_NOT_AVAILABLE = 1

        /** Service not initialized */
        const val NOT_INITIALIZED = 2

        /** Invalid request */
        const val INVALID_REQUEST = 3

        /** Request timeout */
        const val TIMEOUT = 4

        /** Request cancelled */
        const val CANCELLED = 5

        /** Rate limited */
        const val RATE_LIMITED = 6

        /** Authentication required */
        const val AUTH_REQUIRED = 7

        /** Model not available */
        const val MODEL_NOT_AVAILABLE = 8

        /** Content filtered */
        const val CONTENT_FILTERED = 9

        /** Internal error */
        const val INTERNAL_ERROR = 10

        /**
         * Get a human-readable name for the error code.
         */
        fun getName(code: Int): String = when (code) {
            SUCCESS -> "SUCCESS"
            SERVICE_NOT_AVAILABLE -> "SERVICE_NOT_AVAILABLE"
            NOT_INITIALIZED -> "NOT_INITIALIZED"
            INVALID_REQUEST -> "INVALID_REQUEST"
            TIMEOUT -> "TIMEOUT"
            CANCELLED -> "CANCELLED"
            RATE_LIMITED -> "RATE_LIMITED"
            AUTH_REQUIRED -> "AUTH_REQUIRED"
            MODEL_NOT_AVAILABLE -> "MODEL_NOT_AVAILABLE"
            CONTENT_FILTERED -> "CONTENT_FILTERED"
            INTERNAL_ERROR -> "INTERNAL_ERROR"
            else -> "UNKNOWN($code)"
        }
    }

    /**
     * Platform model type constants.
     */
    object ModelType {
        /** Default/auto-select model */
        const val DEFAULT = 0

        /** Small/fast model */
        const val SMALL = 1

        /** Medium/balanced model */
        const val MEDIUM = 2

        /** Large/high-quality model */
        const val LARGE = 3

        /**
         * Get a human-readable name for the model type.
         */
        fun getName(type: Int): String = when (type) {
            DEFAULT -> "DEFAULT"
            SMALL -> "SMALL"
            MEDIUM -> "MEDIUM"
            LARGE -> "LARGE"
            else -> "UNKNOWN($type)"
        }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var isInitialized: Boolean = false

    private val lock = Any()

    /**
     * Cached service availability states.
     */
    private val serviceAvailability = mutableMapOf<Int, Int>()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgePlatform"

    /**
     * Optional listener for platform service events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var platformListener: PlatformListener? = null

    /**
     * Optional provider for platform service implementations.
     * Set this to provide custom platform service implementations.
     */
    @Volatile
    var platformProvider: PlatformProvider? = null

    /**
     * Platform LLM request configuration.
     *
     * @param prompt The input prompt
     * @param systemPrompt Optional system prompt
     * @param maxTokens Maximum tokens to generate
     * @param temperature Sampling temperature
     * @param modelType Preferred model type
     * @param streaming Whether to use streaming output
     */
    data class LLMRequest(
        val prompt: String,
        val systemPrompt: String? = null,
        val maxTokens: Int = 512,
        val temperature: Float = 0.7f,
        val modelType: Int = ModelType.DEFAULT,
        val streaming: Boolean = false
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"prompt\":\"${escapeJsonString(prompt)}\",")
                systemPrompt?.let { append("\"system_prompt\":\"${escapeJsonString(it)}\",") }
                append("\"max_tokens\":$maxTokens,")
                append("\"temperature\":$temperature,")
                append("\"model_type\":$modelType,")
                append("\"streaming\":$streaming")
                append("}")
            }
        }
    }

    /**
     * Platform LLM response.
     *
     * @param text Generated text
     * @param tokensGenerated Number of tokens generated
     * @param finishReason Reason for finishing
     * @param modelUsed Model identifier used
     * @param latencyMs Latency in milliseconds
     */
    data class LLMResponse(
        val text: String,
        val tokensGenerated: Int,
        val finishReason: String,
        val modelUsed: String?,
        val latencyMs: Long
    )

    /**
     * Platform TTS request configuration.
     *
     * @param text Text to synthesize
     * @param language Language code
     * @param voiceId Optional voice identifier
     * @param speakingRate Speaking rate multiplier
     * @param pitch Voice pitch multiplier
     */
    data class TTSRequest(
        val text: String,
        val language: String = "en-US",
        val voiceId: String? = null,
        val speakingRate: Float = 1.0f,
        val pitch: Float = 1.0f
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"text\":\"${escapeJsonString(text)}\",")
                append("\"language\":\"$language\",")
                voiceId?.let { append("\"voice_id\":\"${escapeJsonString(it)}\",") }
                append("\"speaking_rate\":$speakingRate,")
                append("\"pitch\":$pitch")
                append("}")
            }
        }
    }

    /**
     * Platform TTS response.
     *
     * @param audioData Synthesized audio bytes
     * @param durationMs Audio duration in milliseconds
     * @param sampleRate Audio sample rate
     * @param format Audio format (e.g., "PCM_16", "MP3")
     */
    data class TTSResponse(
        val audioData: ByteArray,
        val durationMs: Long,
        val sampleRate: Int,
        val format: String
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is TTSResponse) return false

            if (!audioData.contentEquals(other.audioData)) return false
            if (durationMs != other.durationMs) return false
            if (sampleRate != other.sampleRate) return false
            if (format != other.format) return false

            return true
        }

        override fun hashCode(): Int {
            var result = audioData.contentHashCode()
            result = 31 * result + durationMs.hashCode()
            result = 31 * result + sampleRate
            result = 31 * result + format.hashCode()
            return result
        }
    }

    /**
     * Platform STT request configuration.
     *
     * @param audioData Audio data bytes
     * @param language Language code
     * @param sampleRate Audio sample rate
     * @param format Audio format
     * @param enablePunctuation Enable automatic punctuation
     */
    data class STTRequest(
        val audioData: ByteArray,
        val language: String = "en-US",
        val sampleRate: Int = 16000,
        val format: String = "PCM_16",
        val enablePunctuation: Boolean = true
    ) {
        /**
         * Convert to JSON string for C++ interop (excluding audio data).
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"language\":\"$language\",")
                append("\"sample_rate\":$sampleRate,")
                append("\"format\":\"$format\",")
                append("\"enable_punctuation\":$enablePunctuation")
                append("}")
            }
        }

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is STTRequest) return false

            if (!audioData.contentEquals(other.audioData)) return false
            if (language != other.language) return false
            if (sampleRate != other.sampleRate) return false
            if (format != other.format) return false
            if (enablePunctuation != other.enablePunctuation) return false

            return true
        }

        override fun hashCode(): Int {
            var result = audioData.contentHashCode()
            result = 31 * result + language.hashCode()
            result = 31 * result + sampleRate
            result = 31 * result + format.hashCode()
            result = 31 * result + enablePunctuation.hashCode()
            return result
        }
    }

    /**
     * Platform STT response.
     *
     * @param text Transcribed text
     * @param confidence Confidence score (0.0 to 1.0)
     * @param language Detected language
     * @param isFinal Whether this is a final result
     */
    data class STTResponse(
        val text: String,
        val confidence: Float,
        val language: String,
        val isFinal: Boolean
    )

    /**
     * Platform service capabilities.
     *
     * @param serviceType The service type
     * @param isAvailable Whether the service is available
     * @param supportedLanguages List of supported language codes
     * @param supportedModels List of supported model identifiers
     * @param maxInputLength Maximum input length (characters or tokens)
     * @param supportsStreaming Whether streaming is supported
     * @param requiresNetwork Whether network is required
     */
    data class ServiceCapabilities(
        val serviceType: Int,
        val isAvailable: Boolean,
        val supportedLanguages: List<String>,
        val supportedModels: List<String>,
        val maxInputLength: Int,
        val supportsStreaming: Boolean,
        val requiresNetwork: Boolean
    )

    /**
     * Listener interface for platform service events.
     */
    interface PlatformListener {
        /**
         * Called when a service availability changes.
         *
         * @param serviceType The service type
         * @param status The new availability status
         */
        fun onServiceAvailabilityChanged(serviceType: Int, status: Int)

        /**
         * Called when a platform LLM request completes.
         *
         * @param response The LLM response
         * @param error Error code (0 for success)
         */
        fun onLLMComplete(response: LLMResponse?, error: Int)

        /**
         * Called when a platform TTS request completes.
         *
         * @param response The TTS response
         * @param error Error code (0 for success)
         */
        fun onTTSComplete(response: TTSResponse?, error: Int)

        /**
         * Called when a platform STT request completes.
         *
         * @param response The STT response
         * @param error Error code (0 for success)
         */
        fun onSTTComplete(response: STTResponse?, error: Int)

        /**
         * Called when a streaming token is received.
         *
         * @param token The token text
         * @param isFinal Whether this is the final token
         */
        fun onStreamingToken(token: String, isFinal: Boolean)

        /**
         * Called when an error occurs.
         *
         * @param serviceType The service type
         * @param errorCode The error code
         * @param errorMessage The error message
         */
        fun onError(serviceType: Int, errorCode: Int, errorMessage: String)
    }

    /**
     * Provider interface for platform service implementations.
     */
    interface PlatformProvider {
        /**
         * Check if a service is available.
         *
         * @param serviceType The service type to check
         * @return The availability status
         */
        fun checkServiceAvailability(serviceType: Int): Int

        /**
         * Get capabilities for a service.
         *
         * @param serviceType The service type
         * @return The service capabilities, or null if not available
         */
        fun getServiceCapabilities(serviceType: Int): ServiceCapabilities?

        /**
         * Execute a platform LLM request.
         *
         * @param request The LLM request
         * @param callback Callback for streaming tokens (optional)
         * @return The LLM response
         */
        fun executeLLMRequest(request: LLMRequest, callback: StreamCallback?): LLMResponse?

        /**
         * Execute a platform TTS request.
         *
         * @param request The TTS request
         * @return The TTS response
         */
        fun executeTTSRequest(request: TTSRequest): TTSResponse?

        /**
         * Execute a platform STT request.
         *
         * @param request The STT request
         * @return The STT response
         */
        fun executeSTTRequest(request: STTRequest): STTResponse?

        /**
         * Cancel an ongoing request.
         *
         * @param serviceType The service type
         */
        fun cancelRequest(serviceType: Int)
    }

    /**
     * Callback interface for streaming output.
     */
    fun interface StreamCallback {
        /**
         * Called for each token during streaming.
         *
         * @param token The token text
         * @param isFinal Whether this is the final token
         * @return true to continue streaming, false to stop
         */
        fun onToken(token: String, isFinal: Boolean): Boolean
    }

    /**
     * Register the platform callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgeModelAssignment.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Initialize service availability cache
            initializeServiceAvailability()

            // Register the platform callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetPlatformCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Platform callbacks registered"
            )
        }
    }

    /**
     * Check if the platform callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Initialize the platform services.
     *
     * This should be called after registration to initialize platform service connections.
     *
     * @return 0 on success, error code on failure
     */
    fun initialize(): Int {
        synchronized(lock) {
            if (!isRegistered) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Cannot initialize: not registered"
                )
                return ErrorCode.NOT_INITIALIZED
            }

            if (isInitialized) {
                return ErrorCode.SUCCESS
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Initializing platform services"
            )

            // Check availability of all services
            refreshServiceAvailability()

            isInitialized = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Platform services initialized"
            )

            return ErrorCode.SUCCESS
        }
    }

    // ========================================================================
    // AVAILABILITY CALLBACKS
    // ========================================================================

    /**
     * Check service availability callback.
     *
     * Called from C++ to check if a platform service is available.
     *
     * @param serviceType The service type to check
     * @return The availability status
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isServiceAvailableCallback(serviceType: Int): Int {
        return synchronized(lock) {
            serviceAvailability[serviceType] ?: run {
                // Query provider if available
                val status = platformProvider?.checkServiceAvailability(serviceType)
                    ?: AvailabilityStatus.NOT_AVAILABLE
                serviceAvailability[serviceType] = status
                status
            }
        }
    }

    /**
     * Get service capabilities callback.
     *
     * Called from C++ to get capabilities for a platform service.
     *
     * @param serviceType The service type
     * @return JSON-encoded capabilities, or null if not available
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getServiceCapabilitiesCallback(serviceType: Int): String? {
        val provider = platformProvider ?: return null
        val capabilities = provider.getServiceCapabilities(serviceType) ?: return null

        return buildString {
            append("{")
            append("\"service_type\":$serviceType,")
            append("\"is_available\":${capabilities.isAvailable},")
            append("\"supported_languages\":[")
            capabilities.supportedLanguages.forEachIndexed { index, lang ->
                if (index > 0) append(",")
                append("\"$lang\"")
            }
            append("],")
            append("\"supported_models\":[")
            capabilities.supportedModels.forEachIndexed { index, model ->
                if (index > 0) append(",")
                append("\"$model\"")
            }
            append("],")
            append("\"max_input_length\":${capabilities.maxInputLength},")
            append("\"supports_streaming\":${capabilities.supportsStreaming},")
            append("\"requires_network\":${capabilities.requiresNetwork}")
            append("}")
        }
    }

    /**
     * Set service availability callback.
     *
     * Called from C++ when a service availability changes.
     *
     * @param serviceType The service type
     * @param status The new availability status
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setServiceAvailabilityCallback(serviceType: Int, status: Int) {
        val previousStatus: Int
        synchronized(lock) {
            previousStatus = serviceAvailability[serviceType] ?: AvailabilityStatus.UNKNOWN
            serviceAvailability[serviceType] = status
        }

        if (status != previousStatus) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Service ${ServiceType.getName(serviceType)} availability changed: " +
                    "${AvailabilityStatus.getName(previousStatus)} -> ${AvailabilityStatus.getName(status)}"
            )

            try {
                platformListener?.onServiceAvailabilityChanged(serviceType, status)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in platform listener onServiceAvailabilityChanged: ${e.message}"
                )
            }
        }
    }

    // ========================================================================
    // LLM SERVICE CALLBACKS
    // ========================================================================

    /**
     * Platform LLM generate callback.
     *
     * Called from C++ to generate text using platform LLM service.
     *
     * @param requestJson JSON-encoded LLM request
     * @return JSON-encoded LLM response, or null on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun platformLLMGenerateCallback(requestJson: String): String? {
        val provider = platformProvider
        if (provider == null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Platform LLM generate: no provider set"
            )
            return null
        }

        val request = parseLLMRequest(requestJson) ?: return null

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Platform LLM generate: ${request.prompt.take(50)}..."
        )

        try {
            val response = provider.executeLLMRequest(request, null)
                ?: return null

            try {
                platformListener?.onLLMComplete(response, ErrorCode.SUCCESS)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            return buildString {
                append("{")
                append("\"text\":\"${escapeJsonString(response.text)}\",")
                append("\"tokens_generated\":${response.tokensGenerated},")
                append("\"finish_reason\":\"${response.finishReason}\",")
                response.modelUsed?.let { append("\"model_used\":\"$it\",") }
                append("\"latency_ms\":${response.latencyMs}")
                append("}")
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Platform LLM generate failed: ${e.message}"
            )

            try {
                platformListener?.onError(ServiceType.LLM, ErrorCode.INTERNAL_ERROR, e.message ?: "Unknown error")
            } catch (e2: Exception) {
                // Ignore listener errors
            }

            return null
        }
    }

    /**
     * Platform LLM streaming generate callback.
     *
     * Called from C++ to generate text with streaming using platform LLM service.
     *
     * @param requestJson JSON-encoded LLM request
     * @return JSON-encoded final LLM response, or null on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun platformLLMGenerateStreamCallback(requestJson: String): String? {
        val provider = platformProvider
        if (provider == null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Platform LLM stream generate: no provider set"
            )
            return null
        }

        val request = parseLLMRequest(requestJson) ?: return null

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Platform LLM stream generate: ${request.prompt.take(50)}..."
        )

        try {
            val streamCallback = StreamCallback { token, isFinal ->
                try {
                    platformListener?.onStreamingToken(token, isFinal)
                } catch (e: Exception) {
                    // Ignore listener errors
                }
                streamingTokenCallback(token, isFinal)
            }

            val response = provider.executeLLMRequest(request.copy(streaming = true), streamCallback)
                ?: return null

            try {
                platformListener?.onLLMComplete(response, ErrorCode.SUCCESS)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            return buildString {
                append("{")
                append("\"text\":\"${escapeJsonString(response.text)}\",")
                append("\"tokens_generated\":${response.tokensGenerated},")
                append("\"finish_reason\":\"${response.finishReason}\",")
                response.modelUsed?.let { append("\"model_used\":\"$it\",") }
                append("\"latency_ms\":${response.latencyMs}")
                append("}")
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Platform LLM stream generate failed: ${e.message}"
            )

            try {
                platformListener?.onError(ServiceType.LLM, ErrorCode.INTERNAL_ERROR, e.message ?: "Unknown error")
            } catch (e2: Exception) {
                // Ignore listener errors
            }

            return null
        }
    }

    // ========================================================================
    // TTS SERVICE CALLBACKS
    // ========================================================================

    /**
     * Platform TTS synthesize callback.
     *
     * Called from C++ to synthesize speech using platform TTS service.
     *
     * @param requestJson JSON-encoded TTS request
     * @return Synthesized audio bytes, or null on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun platformTTSSynthesizeCallback(requestJson: String): ByteArray? {
        val provider = platformProvider
        if (provider == null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Platform TTS synthesize: no provider set"
            )
            return null
        }

        val request = parseTTSRequest(requestJson) ?: return null

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Platform TTS synthesize: ${request.text.take(50)}..."
        )

        try {
            val response = provider.executeTTSRequest(request)
                ?: return null

            try {
                platformListener?.onTTSComplete(response, ErrorCode.SUCCESS)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            return response.audioData
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Platform TTS synthesize failed: ${e.message}"
            )

            try {
                platformListener?.onError(ServiceType.TTS, ErrorCode.INTERNAL_ERROR, e.message ?: "Unknown error")
            } catch (e2: Exception) {
                // Ignore listener errors
            }

            return null
        }
    }

    // ========================================================================
    // STT SERVICE CALLBACKS
    // ========================================================================

    /**
     * Platform STT transcribe callback.
     *
     * Called from C++ to transcribe audio using platform STT service.
     *
     * @param audioData Audio data bytes
     * @param configJson JSON-encoded STT configuration
     * @return JSON-encoded STT response, or null on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun platformSTTTranscribeCallback(audioData: ByteArray, configJson: String): String? {
        val provider = platformProvider
        if (provider == null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Platform STT transcribe: no provider set"
            )
            return null
        }

        val request = parseSTTRequest(audioData, configJson) ?: return null

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Platform STT transcribe: ${audioData.size} bytes"
        )

        try {
            val response = provider.executeSTTRequest(request)
                ?: return null

            try {
                platformListener?.onSTTComplete(response, ErrorCode.SUCCESS)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            return buildString {
                append("{")
                append("\"text\":\"${escapeJsonString(response.text)}\",")
                append("\"confidence\":${response.confidence},")
                append("\"language\":\"${response.language}\",")
                append("\"is_final\":${response.isFinal}")
                append("}")
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Platform STT transcribe failed: ${e.message}"
            )

            try {
                platformListener?.onError(ServiceType.STT, ErrorCode.INTERNAL_ERROR, e.message ?: "Unknown error")
            } catch (e2: Exception) {
                // Ignore listener errors
            }

            return null
        }
    }

    // ========================================================================
    // CANCEL CALLBACK
    // ========================================================================

    /**
     * Cancel platform request callback.
     *
     * Called from C++ to cancel an ongoing platform request.
     *
     * @param serviceType The service type to cancel
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun cancelPlatformRequestCallback(serviceType: Int) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Cancelling platform request: ${ServiceType.getName(serviceType)}"
        )

        try {
            platformProvider?.cancelRequest(serviceType)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error cancelling platform request: ${e.message}"
            )
        }
    }

    // ========================================================================
    // STREAMING CALLBACK
    // ========================================================================

    /**
     * Streaming token callback.
     *
     * Called to send a streaming token back to C++.
     *
     * @param token The token text
     * @param isFinal Whether this is the final token
     * @return true to continue streaming, false to stop
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun streamingTokenCallback(token: String, isFinal: Boolean): Boolean {
        return try {
            nativeOnStreamingToken(token, isFinal)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in streaming token callback: ${e.message}"
            )
            true // Continue on error
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the platform callbacks with C++ core.
     *
     * C API: rac_platform_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetPlatformCallbacks()

    /**
     * Native method to unset the platform callbacks.
     *
     * C API: rac_platform_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetPlatformCallbacks()

    /**
     * Native method to send a streaming token to C++.
     *
     * @param token The token text
     * @param isFinal Whether this is the final token
     * @return true to continue streaming, false to stop
     *
     * C API: rac_platform_on_streaming_token(token, is_final)
     */
    @JvmStatic
    external fun nativeOnStreamingToken(token: String, isFinal: Boolean): Boolean

    /**
     * Native method to check if platform LLM is available.
     *
     * @return The availability status
     *
     * C API: rac_platform_is_llm_available()
     */
    @JvmStatic
    external fun nativeIsLLMAvailable(): Int

    /**
     * Native method to check if platform TTS is available.
     *
     * @return The availability status
     *
     * C API: rac_platform_is_tts_available()
     */
    @JvmStatic
    external fun nativeIsTTSAvailable(): Int

    /**
     * Native method to check if platform STT is available.
     *
     * @return The availability status
     *
     * C API: rac_platform_is_stt_available()
     */
    @JvmStatic
    external fun nativeIsSTTAvailable(): Int

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the platform callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetPlatformCallbacks()

            platformListener = null
            platformProvider = null
            serviceAvailability.clear()
            isInitialized = false
            isRegistered = false
        }
    }

    // ========================================================================
    // PUBLIC UTILITY METHODS
    // ========================================================================

    /**
     * Check if a platform service is available.
     *
     * @param serviceType The service type to check
     * @return true if available, false otherwise
     */
    fun isServiceAvailable(serviceType: Int): Boolean {
        return AvailabilityStatus.isUsable(isServiceAvailableCallback(serviceType))
    }

    /**
     * Get the availability status for a service.
     *
     * @param serviceType The service type
     * @return The availability status
     */
    fun getServiceAvailability(serviceType: Int): Int {
        return synchronized(lock) {
            serviceAvailability[serviceType] ?: AvailabilityStatus.UNKNOWN
        }
    }

    /**
     * Refresh service availability for all services.
     */
    fun refreshServiceAvailability() {
        val provider = platformProvider ?: return

        for (serviceType in listOf(ServiceType.LLM, ServiceType.TTS, ServiceType.STT, ServiceType.EMBEDDING)) {
            val status = provider.checkServiceAvailability(serviceType)
            setServiceAvailabilityCallback(serviceType, status)
        }
    }

    /**
     * Get capabilities for a service.
     *
     * @param serviceType The service type
     * @return The service capabilities, or null if not available
     */
    fun getCapabilities(serviceType: Int): ServiceCapabilities? {
        return platformProvider?.getServiceCapabilities(serviceType)
    }

    /**
     * Execute a platform LLM request.
     *
     * @param request The LLM request
     * @param callback Optional streaming callback
     * @return The LLM response
     * @throws SDKError if the request fails
     */
    @Throws(SDKError::class)
    fun executeLLM(request: LLMRequest, callback: StreamCallback? = null): LLMResponse {
        val provider = platformProvider
            ?: throw SDKError.platform("Platform provider not set")

        if (!isServiceAvailable(ServiceType.LLM)) {
            throw SDKError.platform("Platform LLM service not available")
        }

        return provider.executeLLMRequest(request, callback)
            ?: throw SDKError.platform("Platform LLM request failed")
    }

    /**
     * Execute a platform TTS request.
     *
     * @param request The TTS request
     * @return The TTS response
     * @throws SDKError if the request fails
     */
    @Throws(SDKError::class)
    fun executeTTS(request: TTSRequest): TTSResponse {
        val provider = platformProvider
            ?: throw SDKError.platform("Platform provider not set")

        if (!isServiceAvailable(ServiceType.TTS)) {
            throw SDKError.platform("Platform TTS service not available")
        }

        return provider.executeTTSRequest(request)
            ?: throw SDKError.platform("Platform TTS request failed")
    }

    /**
     * Execute a platform STT request.
     *
     * @param request The STT request
     * @return The STT response
     * @throws SDKError if the request fails
     */
    @Throws(SDKError::class)
    fun executeSTT(request: STTRequest): STTResponse {
        val provider = platformProvider
            ?: throw SDKError.platform("Platform provider not set")

        if (!isServiceAvailable(ServiceType.STT)) {
            throw SDKError.platform("Platform STT service not available")
        }

        return provider.executeSTTRequest(request)
            ?: throw SDKError.platform("Platform STT request failed")
    }

    /**
     * Get a state summary for diagnostics.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        return buildString {
            append("Platform Services: registered=$isRegistered, initialized=$isInitialized")
            append(", LLM=${AvailabilityStatus.getName(getServiceAvailability(ServiceType.LLM))}")
            append(", TTS=${AvailabilityStatus.getName(getServiceAvailability(ServiceType.TTS))}")
            append(", STT=${AvailabilityStatus.getName(getServiceAvailability(ServiceType.STT))}")
        }
    }

    // ========================================================================
    // PRIVATE UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Initialize service availability cache.
     */
    private fun initializeServiceAvailability() {
        serviceAvailability[ServiceType.LLM] = AvailabilityStatus.UNKNOWN
        serviceAvailability[ServiceType.TTS] = AvailabilityStatus.UNKNOWN
        serviceAvailability[ServiceType.STT] = AvailabilityStatus.UNKNOWN
        serviceAvailability[ServiceType.EMBEDDING] = AvailabilityStatus.UNKNOWN
        serviceAvailability[ServiceType.IMAGE_GENERATION] = AvailabilityStatus.UNKNOWN
        serviceAvailability[ServiceType.VISION] = AvailabilityStatus.UNKNOWN
    }

    /**
     * Escape a string for JSON encoding.
     */
    private fun escapeJsonString(str: String): String {
        return str
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }

    /**
     * Parse LLM request from JSON.
     */
    private fun parseLLMRequest(json: String): LLMRequest? {
        return try {
            fun extractString(key: String): String? {
                val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)
            }

            fun extractInt(key: String): Int? {
                val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)?.toIntOrNull()
            }

            fun extractFloat(key: String): Float? {
                val pattern = "\"$key\"\\s*:\\s*(-?[\\d.]+)"
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)?.toFloatOrNull()
            }

            fun extractBoolean(key: String): Boolean? {
                val pattern = "\"$key\"\\s*:\\s*(true|false)"
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)?.toBooleanStrictOrNull()
            }

            val prompt = extractString("prompt") ?: return null

            LLMRequest(
                prompt = prompt,
                systemPrompt = extractString("system_prompt"),
                maxTokens = extractInt("max_tokens") ?: 512,
                temperature = extractFloat("temperature") ?: 0.7f,
                modelType = extractInt("model_type") ?: ModelType.DEFAULT,
                streaming = extractBoolean("streaming") ?: false
            )
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to parse LLM request: ${e.message}"
            )
            null
        }
    }

    /**
     * Parse TTS request from JSON.
     */
    private fun parseTTSRequest(json: String): TTSRequest? {
        return try {
            fun extractString(key: String): String? {
                val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)
            }

            fun extractFloat(key: String): Float? {
                val pattern = "\"$key\"\\s*:\\s*(-?[\\d.]+)"
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)?.toFloatOrNull()
            }

            val text = extractString("text") ?: return null

            TTSRequest(
                text = text,
                language = extractString("language") ?: "en-US",
                voiceId = extractString("voice_id"),
                speakingRate = extractFloat("speaking_rate") ?: 1.0f,
                pitch = extractFloat("pitch") ?: 1.0f
            )
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to parse TTS request: ${e.message}"
            )
            null
        }
    }

    /**
     * Parse STT request from audio data and config JSON.
     */
    private fun parseSTTRequest(audioData: ByteArray, json: String): STTRequest? {
        return try {
            fun extractString(key: String): String? {
                val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)
            }

            fun extractInt(key: String): Int? {
                val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)?.toIntOrNull()
            }

            fun extractBoolean(key: String): Boolean? {
                val pattern = "\"$key\"\\s*:\\s*(true|false)"
                val regex = Regex(pattern)
                return regex.find(json)?.groupValues?.get(1)?.toBooleanStrictOrNull()
            }

            STTRequest(
                audioData = audioData,
                language = extractString("language") ?: "en-US",
                sampleRate = extractInt("sample_rate") ?: 16000,
                format = extractString("format") ?: "PCM_16",
                enablePunctuation = extractBoolean("enable_punctuation") ?: true
            )
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to parse STT request: ${e.message}"
            )
            null
        }
    }
}
