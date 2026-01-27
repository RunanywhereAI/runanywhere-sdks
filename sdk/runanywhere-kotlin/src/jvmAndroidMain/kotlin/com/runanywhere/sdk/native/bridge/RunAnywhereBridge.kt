/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JNI Bridge for runanywhere-commons C API (rac_* functions).
 *
 * This matches the Swift SDK's CppBridge pattern where:
 * - Swift uses CRACommons (C headers) → RACommons.xcframework
 * - Kotlin uses RunAnywhereBridge (JNI) → librunanywhere_jni.so
 *
 * The JNI library is built from runanywhere-commons/src/jni/runanywhere_commons_jni.cpp
 * and provides the rac_* API surface that wraps the C++ commons layer.
 */

package com.runanywhere.sdk.native.bridge

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * RunAnywhereBridge provides low-level JNI bindings for the runanywhere-commons C API.
 *
 * This object maps directly to the JNI functions in runanywhere_commons_jni.cpp.
 * For higher-level usage, use CppBridge and its extensions.
 *
 * @see com.runanywhere.sdk.foundation.bridge.CppBridge
 */
object RunAnywhereBridge {
    private const val TAG = "RunAnywhereBridge"

    // ========================================================================
    // NATIVE LIBRARY LOADING
    // ========================================================================

    @Volatile
    private var nativeLibraryLoaded = false
    private val loadLock = Any()

    private val logger = SDKLogger(TAG)

    /**
     * Load the native commons library if not already loaded.
     * @return true if the library is loaded, false otherwise
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            logger.info("Loading native library 'runanywhere_jni'...")

            try {
                System.loadLibrary("runanywhere_jni")
                nativeLibraryLoaded = true
                logger.info("✅ Native library loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("❌ Failed to load native library: ${e.message}", throwable = e)
                return false
            } catch (e: Exception) {
                logger.error("❌ Unexpected error: ${e.message}", throwable = e)
                return false
            }
        }
    }

    fun isNativeLibraryLoaded(): Boolean = nativeLibraryLoaded

    // ========================================================================
    // CORE INITIALIZATION (rac_core.h)
    // ========================================================================

    @JvmStatic
    external fun racInit(): Int

    @JvmStatic
    external fun racShutdown(): Int

    @JvmStatic
    external fun racIsInitialized(): Boolean

    // ========================================================================
    // PLATFORM ADAPTER (rac_platform_adapter.h)
    // ========================================================================

    @JvmStatic
    external fun racSetPlatformAdapter(adapter: Any): Int

    @JvmStatic
    external fun racGetPlatformAdapter(): Any?

    // ========================================================================
    // LOGGING (rac_logger.h)
    // ========================================================================

    @JvmStatic
    external fun racConfigureLogging(level: Int, logFilePath: String?): Int

    @JvmStatic
    external fun racLog(level: Int, tag: String, message: String)

    // ========================================================================
    // LLM COMPONENT (rac_llm_component.h)
    // ========================================================================

    @JvmStatic
    external fun racLlmComponentCreate(): Long

    @JvmStatic
    external fun racLlmComponentDestroy(handle: Long)

    @JvmStatic
    external fun racLlmComponentConfigure(handle: Long, configJson: String): Int

    @JvmStatic
    external fun racLlmComponentIsLoaded(handle: Long): Boolean

    @JvmStatic
    external fun racLlmComponentGetModelId(handle: Long): String?

    /**
     * Load a model. Takes model path (or ID) and optional config JSON.
     */
    @JvmStatic
    external fun racLlmComponentLoadModel(handle: Long, modelPath: String, modelId: String, modelName: String?): Int

    @JvmStatic
    external fun racLlmComponentUnload(handle: Long): Int

    @JvmStatic
    external fun racLlmComponentCleanup(handle: Long): Int

    @JvmStatic
    external fun racLlmComponentCancel(handle: Long): Int

    /**
     * Generate text (non-streaming).
     * @return JSON result string or null on error
     */
    @JvmStatic
    external fun racLlmComponentGenerate(handle: Long, prompt: String, optionsJson: String?): String?

    /**
     * Generate text with streaming - simplified version that returns result JSON.
     * Streaming is handled internally, result returned on completion.
     */
    @JvmStatic
    external fun racLlmComponentGenerateStream(handle: Long, prompt: String, optionsJson: String?): String?

    /**
     * Token callback interface for streaming generation.
     */
    fun interface TokenCallback {
        fun onToken(token: String): Boolean
    }

    /**
     * Generate text with true streaming - calls tokenCallback for each token.
     * This provides real-time token-by-token streaming.
     *
     * @param handle LLM component handle
     * @param prompt The prompt to generate from
     * @param optionsJson Options as JSON string
     * @param tokenCallback Callback invoked for each generated token
     * @return JSON result string with final metrics, or null on error
     */
    @JvmStatic
    external fun racLlmComponentGenerateStreamWithCallback(
        handle: Long,
        prompt: String,
        optionsJson: String?,
        tokenCallback: TokenCallback,
    ): String?

    @JvmStatic
    external fun racLlmComponentSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun racLlmComponentGetState(handle: Long): Int

    @JvmStatic
    external fun racLlmComponentGetMetrics(handle: Long): String?

    @JvmStatic
    external fun racLlmComponentGetContextSize(handle: Long): Int

    @JvmStatic
    external fun racLlmComponentTokenize(handle: Long, text: String): Int

    @JvmStatic
    external fun racLlmSetCallbacks(streamCallback: Any?, progressCallback: Any?)

    // ========================================================================
    // STT COMPONENT (rac_stt_component.h)
    // ========================================================================

    @JvmStatic
    external fun racSttComponentCreate(): Long

    @JvmStatic
    external fun racSttComponentDestroy(handle: Long)

    @JvmStatic
    external fun racSttComponentIsLoaded(handle: Long): Boolean

    @JvmStatic
    external fun racSttComponentLoadModel(handle: Long, modelPath: String, modelId: String, modelName: String?): Int

    @JvmStatic
    external fun racSttComponentUnload(handle: Long): Int

    @JvmStatic
    external fun racSttComponentCancel(handle: Long): Int

    @JvmStatic
    external fun racSttComponentTranscribe(handle: Long, audioData: ByteArray, optionsJson: String?): String?

    @JvmStatic
    external fun racSttComponentTranscribeFile(handle: Long, audioPath: String, optionsJson: String?): String?

    @JvmStatic
    external fun racSttComponentTranscribeStream(handle: Long, audioData: ByteArray, optionsJson: String?): String?

    @JvmStatic
    external fun racSttComponentSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun racSttComponentGetState(handle: Long): Int

    @JvmStatic
    external fun racSttComponentGetLanguages(handle: Long): String?

    @JvmStatic
    external fun racSttComponentDetectLanguage(handle: Long, audioData: ByteArray): String?

    @JvmStatic
    external fun racSttSetCallbacks(frameCallback: Any?, progressCallback: Any?)

    // ========================================================================
    // TTS COMPONENT (rac_tts_component.h)
    // ========================================================================

    @JvmStatic
    external fun racTtsComponentCreate(): Long

    @JvmStatic
    external fun racTtsComponentDestroy(handle: Long)

    @JvmStatic
    external fun racTtsComponentIsLoaded(handle: Long): Boolean

    @JvmStatic
    external fun racTtsComponentLoadModel(handle: Long, modelPath: String, modelId: String, modelName: String?): Int

    @JvmStatic
    external fun racTtsComponentUnload(handle: Long): Int

    @JvmStatic
    external fun racTtsComponentCancel(handle: Long): Int

    @JvmStatic
    external fun racTtsComponentSynthesize(handle: Long, text: String, optionsJson: String?): ByteArray?

    @JvmStatic
    external fun racTtsComponentSynthesizeToFile(handle: Long, text: String, outputPath: String, optionsJson: String?): Long

    @JvmStatic
    external fun racTtsComponentSynthesizeStream(handle: Long, text: String, optionsJson: String?): ByteArray?

    @JvmStatic
    external fun racTtsComponentGetVoices(handle: Long): String?

    @JvmStatic
    external fun racTtsComponentSetVoice(handle: Long, voiceId: String): Int

    @JvmStatic
    external fun racTtsComponentGetState(handle: Long): Int

    @JvmStatic
    external fun racTtsComponentGetLanguages(handle: Long): String?

    @JvmStatic
    external fun racTtsSetCallbacks(audioCallback: Any?, progressCallback: Any?)

    // ========================================================================
    // VAD COMPONENT (rac_vad_component.h)
    // ========================================================================

    @JvmStatic
    external fun racVadComponentCreate(): Long

    @JvmStatic
    external fun racVadComponentDestroy(handle: Long)

    @JvmStatic
    external fun racVadComponentIsLoaded(handle: Long): Boolean

    @JvmStatic
    external fun racVadComponentLoadModel(handle: Long, modelId: String?, configJson: String?): Int

    @JvmStatic
    external fun racVadComponentUnload(handle: Long): Int

    @JvmStatic
    external fun racVadComponentProcess(handle: Long, samples: ByteArray, optionsJson: String?): String?

    @JvmStatic
    external fun racVadComponentProcessStream(handle: Long, samples: ByteArray, optionsJson: String?): String?

    @JvmStatic
    external fun racVadComponentProcessFrame(handle: Long, samples: ByteArray, optionsJson: String?): String?

    @JvmStatic
    external fun racVadComponentReset(handle: Long): Int

    @JvmStatic
    external fun racVadComponentCancel(handle: Long): Int

    @JvmStatic
    external fun racVadComponentSetThreshold(handle: Long, threshold: Float): Int

    @JvmStatic
    external fun racVadComponentGetState(handle: Long): Int

    @JvmStatic
    external fun racVadComponentGetMinFrameSize(handle: Long): Int

    @JvmStatic
    external fun racVadComponentGetSampleRates(handle: Long): String?

    @JvmStatic
    external fun racVadSetCallbacks(
        frameCallback: Any?,
        speechStartCallback: Any?,
        speechEndCallback: Any?,
        progressCallback: Any?,
    )

    // ========================================================================
    // BACKEND REGISTRATION
    // ========================================================================
    // NOTE: Backend registration has been MOVED to their respective module JNI bridges:
    //
    //   LlamaCPP: com.runanywhere.sdk.llm.llamacpp.LlamaCPPBridge.nativeRegister()
    //             (in module: runanywhere-core-llamacpp)
    //
    //   ONNX:     com.runanywhere.sdk.core.onnx.ONNXBridge.nativeRegister()
    //             (in module: runanywhere-core-onnx)
    //
    // This mirrors the Swift SDK architecture where each backend has its own
    // XCFramework (RABackendLlamaCPP, RABackendONNX) with separate registration.
    // ========================================================================

    // ========================================================================
    // DOWNLOAD MANAGER (rac_download.h)
    // ========================================================================

    @JvmStatic
    external fun racDownloadStart(url: String, destPath: String, progressCallback: Any?): Long

    @JvmStatic
    external fun racDownloadCancel(downloadId: Long): Int

    @JvmStatic
    external fun racDownloadGetProgress(downloadId: Long): String?

    // ========================================================================
    // MODEL REGISTRY - Direct C++ registry access (mirrors Swift CppBridge+ModelRegistry)
    // ========================================================================

    /**
     * Save model to C++ registry.
     * This stores the model directly in the C++ model registry for service provider lookup.
     *
     * @param modelId Unique model identifier
     * @param name Display name
     * @param category Model category (0=LLM, 1=STT, 2=TTS, 3=VAD)
     * @param format Model format (0=UNKNOWN, 1=GGUF, 2=ONNX, etc.)
     * @param framework Inference framework (0=LLAMACPP, 1=ONNX, etc.)
     * @param downloadUrl Download URL (nullable)
     * @param localPath Local file path (nullable)
     * @param downloadSize Size in bytes
     * @param contextLength Context length for LLM
     * @param supportsThinking Whether model supports thinking mode
     * @param description Model description (nullable)
     * @return RAC_SUCCESS on success, error code on failure
     */
    @JvmStatic
    external fun racModelRegistrySave(
        modelId: String,
        name: String,
        category: Int,
        format: Int,
        framework: Int,
        downloadUrl: String?,
        localPath: String?,
        downloadSize: Long,
        contextLength: Int,
        supportsThinking: Boolean,
        description: String?,
    ): Int

    /**
     * Get model info from C++ registry as JSON.
     *
     * @param modelId Model identifier
     * @return JSON string with model info, or null if not found
     */
    @JvmStatic
    external fun racModelRegistryGet(modelId: String): String?

    /**
     * Get all models from C++ registry as JSON array.
     *
     * @return JSON array string with all models
     */
    @JvmStatic
    external fun racModelRegistryGetAll(): String

    /**
     * Get downloaded models from C++ registry as JSON array.
     *
     * @return JSON array string with downloaded models
     */
    @JvmStatic
    external fun racModelRegistryGetDownloaded(): String

    /**
     * Remove model from C++ registry.
     *
     * @param modelId Model identifier
     * @return RAC_SUCCESS on success, error code on failure
     */
    @JvmStatic
    external fun racModelRegistryRemove(modelId: String): Int

    /**
     * Update download status in C++ registry.
     *
     * @param modelId Model identifier
     * @param localPath Local path after download (or null to clear)
     * @return RAC_SUCCESS on success, error code on failure
     */
    @JvmStatic
    external fun racModelRegistryUpdateDownloadStatus(modelId: String, localPath: String?): Int

    // ========================================================================
    // MODEL ASSIGNMENT (rac_model_assignment.h)
    // Mirrors Swift SDK's CppBridge+ModelAssignment.swift
    // ========================================================================

    /**
     * Set model assignment callbacks.
     * The callback object must implement:
     * - httpGet(endpoint: String, requiresAuth: Boolean): String (returns JSON response or "ERROR:message")
     * - getDeviceInfo(): String (returns "deviceType|platform")
     *
     * @param callback Callback object implementing the required methods
     * @param autoFetch If true, automatically fetch models after registration
     * @return RAC_SUCCESS on success, error code on failure
     */
    @JvmStatic
    external fun racModelAssignmentSetCallbacks(callback: Any, autoFetch: Boolean): Int

    /**
     * Fetch model assignments from backend.
     * Results are cached and saved to the model registry.
     *
     * @param forceRefresh If true, bypass cache and fetch fresh data
     * @return JSON array of model assignments
     */
    @JvmStatic
    external fun racModelAssignmentFetch(forceRefresh: Boolean): String

    // ========================================================================
    // AUDIO UTILS (rac_audio_utils.h)
    // ========================================================================

    /**
     * Convert Float32 PCM audio data to WAV format.
     *
     * TTS backends typically output raw Float32 PCM samples in range [-1.0, 1.0].
     * This function converts them to a complete WAV file that can be played by
     * standard audio players (MediaPlayer on Android, etc.).
     *
     * @param pcmData Float32 PCM audio data (raw bytes)
     * @param sampleRate Sample rate in Hz (e.g., 22050 for Piper TTS)
     * @return WAV file data as ByteArray, or null on error
     */
    @JvmStatic
    external fun racAudioFloat32ToWav(pcmData: ByteArray, sampleRate: Int): ByteArray?

    /**
     * Convert Int16 PCM audio data to WAV format.
     *
     * @param pcmData Int16 PCM audio data (raw bytes)
     * @param sampleRate Sample rate in Hz
     * @return WAV file data as ByteArray, or null on error
     */
    @JvmStatic
    external fun racAudioInt16ToWav(pcmData: ByteArray, sampleRate: Int): ByteArray?

    /**
     * Get the WAV header size in bytes.
     *
     * @return WAV header size (always 44 bytes for standard PCM WAV)
     */
    @JvmStatic
    external fun racAudioWavHeaderSize(): Int

    // ========================================================================
    // DEVICE MANAGER (rac_device_manager.h)
    // Mirrors Swift SDK's CppBridge+Device.swift
    // ========================================================================

    /**
     * Set device manager callbacks.
     * The callback object must implement:
     * - getDeviceInfo(): String (returns JSON)
     * - getDeviceId(): String
     * - isRegistered(): Boolean
     * - setRegistered(registered: Boolean)
     * - httpPost(endpoint: String, body: String, requiresAuth: Boolean): Int (status code)
     */
    @JvmStatic
    external fun racDeviceManagerSetCallbacks(callbacks: Any): Int

    /**
     * Register device with backend if not already registered.
     * @param environment SDK environment (0=DEVELOPMENT, 1=STAGING, 2=PRODUCTION)
     * @param buildToken Optional build token for development mode
     */
    @JvmStatic
    external fun racDeviceManagerRegisterIfNeeded(environment: Int, buildToken: String?): Int

    /**
     * Check if device is registered.
     */
    @JvmStatic
    external fun racDeviceManagerIsRegistered(): Boolean

    /**
     * Clear device registration status.
     */
    @JvmStatic
    external fun racDeviceManagerClearRegistration()

    /**
     * Get the current device ID.
     */
    @JvmStatic
    external fun racDeviceManagerGetDeviceId(): String?

    // ========================================================================
    // TELEMETRY MANAGER (rac_telemetry_manager.h)
    // Mirrors Swift SDK's CppBridge+Telemetry.swift
    // ========================================================================

    /**
     * Create telemetry manager.
     * @param environment SDK environment
     * @param deviceId Persistent device UUID
     * @param platform Platform string ("android")
     * @param sdkVersion SDK version string
     * @return Handle to telemetry manager, or 0 on failure
     */
    @JvmStatic
    external fun racTelemetryManagerCreate(
        environment: Int,
        deviceId: String,
        platform: String,
        sdkVersion: String,
    ): Long

    /**
     * Destroy telemetry manager.
     */
    @JvmStatic
    external fun racTelemetryManagerDestroy(handle: Long)

    /**
     * Set device info for telemetry payloads.
     */
    @JvmStatic
    external fun racTelemetryManagerSetDeviceInfo(handle: Long, deviceModel: String, osVersion: String)

    /**
     * Set HTTP callback for telemetry.
     * The callback object must implement:
     * - onHttpRequest(endpoint: String, body: String, bodyLength: Int, requiresAuth: Boolean)
     */
    @JvmStatic
    external fun racTelemetryManagerSetHttpCallback(handle: Long, callback: Any)

    /**
     * Flush pending telemetry events.
     */
    @JvmStatic
    external fun racTelemetryManagerFlush(handle: Long): Int

    // ========================================================================
    // ANALYTICS EVENTS (rac_analytics_events.h)
    // ========================================================================

    /**
     * Register analytics events callback with telemetry manager.
     * Events from C++ will be routed to the telemetry manager for batching and HTTP transport.
     *
     * @param telemetryHandle Handle to the telemetry manager (from racTelemetryManagerCreate)
     *                        Pass 0 to unregister the callback
     * @return RAC_SUCCESS or error code
     */
    @JvmStatic
    external fun racAnalyticsEventsSetCallback(telemetryHandle: Long): Int

    /**
     * Emit a download/extraction event.
     * Maps to rac_analytics_model_download_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitDownload(
        eventType: Int,
        modelId: String?,
        progress: Double,
        bytesDownloaded: Long,
        totalBytes: Long,
        durationMs: Double,
        sizeBytes: Long,
        archiveType: String?,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit an SDK lifecycle event.
     * Maps to rac_analytics_sdk_lifecycle_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitSdkLifecycle(
        eventType: Int,
        durationMs: Double,
        count: Int,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit a storage event.
     * Maps to rac_analytics_storage_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitStorage(
        eventType: Int,
        freedBytes: Long,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit a device event.
     * Maps to rac_analytics_device_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitDevice(
        eventType: Int,
        deviceId: String?,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit an SDK error event.
     * Maps to rac_analytics_sdk_error_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitSdkError(
        eventType: Int,
        errorCode: Int,
        errorMessage: String?,
        operation: String?,
        context: String?,
    ): Int

    /**
     * Emit a network event.
     * Maps to rac_analytics_network_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitNetwork(
        eventType: Int,
        isOnline: Boolean,
    ): Int

    /**
     * Emit an LLM generation event.
     * Maps to rac_analytics_llm_generation_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitLlmGeneration(
        eventType: Int,
        generationId: String?,
        modelId: String?,
        modelName: String?,
        inputTokens: Int,
        outputTokens: Int,
        durationMs: Double,
        tokensPerSecond: Double,
        isStreaming: Boolean,
        timeToFirstTokenMs: Double,
        framework: Int,
        temperature: Float,
        maxTokens: Int,
        contextLength: Int,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit an LLM model event.
     * Maps to rac_analytics_llm_model_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitLlmModel(
        eventType: Int,
        modelId: String?,
        modelName: String?,
        modelSizeBytes: Long,
        durationMs: Double,
        framework: Int,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit an STT transcription event.
     * Maps to rac_analytics_stt_transcription_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitSttTranscription(
        eventType: Int,
        transcriptionId: String?,
        modelId: String?,
        modelName: String?,
        text: String?,
        confidence: Float,
        durationMs: Double,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        wordCount: Int,
        realTimeFactor: Double,
        language: String?,
        sampleRate: Int,
        isStreaming: Boolean,
        framework: Int,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit a TTS synthesis event.
     * Maps to rac_analytics_tts_synthesis_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitTtsSynthesis(
        eventType: Int,
        synthesisId: String?,
        modelId: String?,
        modelName: String?,
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingDurationMs: Double,
        charactersPerSecond: Double,
        sampleRate: Int,
        framework: Int,
        errorCode: Int,
        errorMessage: String?,
    ): Int

    /**
     * Emit a VAD event.
     * Maps to rac_analytics_vad_t struct in C++.
     */
    @JvmStatic
    external fun racAnalyticsEventEmitVad(
        eventType: Int,
        speechDurationMs: Double,
        energyLevel: Float,
    ): Int

    // ========================================================================
    // DEVELOPMENT CONFIG (rac_dev_config.h)
    // Mirrors Swift SDK's CppBridge+Environment.swift DevConfig
    // ========================================================================

    /**
     * Check if development config is available (has Supabase credentials configured).
     * @return true if dev config is available
     */
    @JvmStatic
    external fun racDevConfigIsAvailable(): Boolean

    /**
     * Get Supabase URL for development mode.
     * @return Supabase URL or null if not configured
     */
    @JvmStatic
    external fun racDevConfigGetSupabaseUrl(): String?

    /**
     * Get Supabase anon key for development mode.
     * @return Supabase anon key or null if not configured
     */
    @JvmStatic
    external fun racDevConfigGetSupabaseKey(): String?

    /**
     * Get build token for development mode.
     * @return Build token or null if not configured
     */
    @JvmStatic
    external fun racDevConfigGetBuildToken(): String?

    /**
     * Get Sentry DSN for crash reporting.
     * @return Sentry DSN or null if not configured
     */
    @JvmStatic
    external fun racDevConfigGetSentryDsn(): String?

    // ========================================================================
    // SDK CONFIGURATION INITIALIZATION
    // ========================================================================

    /**
     * Initialize SDK configuration with version and platform info.
     * This must be called during SDK initialization for device registration
     * to include the correct sdk_version (instead of "unknown").
     *
     * @param environment Environment (0=development, 1=staging, 2=production)
     * @param deviceId Device ID string
     * @param platform Platform string (e.g., "android")
     * @param sdkVersion SDK version string (e.g., "0.1.0")
     * @param apiKey API key (can be empty for development)
     * @param baseUrl Base URL (can be empty for development)
     * @return 0 on success, error code on failure
     */
    @JvmStatic
    external fun racSdkInit(
        environment: Int,
        deviceId: String?,
        platform: String,
        sdkVersion: String,
        apiKey: String?,
        baseUrl: String?,
    ): Int

    // ========================================================================
    // TOOL CALLING API (rac_tool_calling.h)
    // Mirrors Swift SDK's CppBridge+ToolCalling.swift
    // ========================================================================

    /**
     * Parse LLM output for tool calls.
     *
     * @param llmOutput Raw LLM output text
     * @return JSON string with parsed result, or null on error
     */
    @JvmStatic
    external fun racToolCallParse(llmOutput: String): String?

    /**
     * Format tool definitions into system prompt.
     *
     * @param toolsJson JSON array of tool definitions
     * @return Formatted prompt string, or null on error
     */
    @JvmStatic
    external fun racToolCallFormatPromptJson(toolsJson: String): String?

    /**
     * Build initial prompt with tools and user query.
     *
     * @param userPrompt The user's question/request
     * @param toolsJson JSON array of tool definitions
     * @param optionsJson Options as JSON (nullable)
     * @return Complete formatted prompt, or null on error
     */
    @JvmStatic
    external fun racToolCallBuildInitialPrompt(
        userPrompt: String,
        toolsJson: String,
        optionsJson: String?,
    ): String?

    /**
     * Build follow-up prompt after tool execution.
     *
     * @param originalPrompt The original user prompt
     * @param toolsPrompt Formatted tools prompt (nullable)
     * @param toolName Name of the tool that was executed
     * @param toolResultJson JSON string of the tool result
     * @param keepToolsAvailable Whether to include tool definitions
     * @return Follow-up prompt, or null on error
     */
    @JvmStatic
    external fun racToolCallBuildFollowupPrompt(
        originalPrompt: String,
        toolsPrompt: String?,
        toolName: String,
        toolResultJson: String,
        keepToolsAvailable: Boolean,
    ): String?

    /**
     * Normalize JSON by adding quotes around unquoted keys.
     *
     * @param jsonStr Raw JSON string possibly with unquoted keys
     * @return Normalized JSON string, or null on error
     */
    @JvmStatic
    external fun racToolCallNormalizeJson(jsonStr: String): String?

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    // Result codes
    const val RAC_SUCCESS = 0
    const val RAC_ERROR_INVALID_PARAMS = -1
    const val RAC_ERROR_INVALID_HANDLE = -2
    const val RAC_ERROR_NOT_INITIALIZED = -3
    const val RAC_ERROR_ALREADY_INITIALIZED = -4
    const val RAC_ERROR_OPERATION_FAILED = -5
    const val RAC_ERROR_NOT_SUPPORTED = -6
    const val RAC_ERROR_MODEL_NOT_LOADED = -7
    const val RAC_ERROR_OUT_OF_MEMORY = -8
    const val RAC_ERROR_IO = -9
    const val RAC_ERROR_CANCELLED = -10
    const val RAC_ERROR_MODULE_ALREADY_REGISTERED = -20
    const val RAC_ERROR_MODULE_NOT_FOUND = -21
    const val RAC_ERROR_SERVICE_NOT_FOUND = -22

    // Lifecycle states
    const val RAC_LIFECYCLE_IDLE = 0
    const val RAC_LIFECYCLE_INITIALIZING = 1
    const val RAC_LIFECYCLE_LOADING = 2
    const val RAC_LIFECYCLE_READY = 3
    const val RAC_LIFECYCLE_ACTIVE = 4
    const val RAC_LIFECYCLE_UNLOADING = 5
    const val RAC_LIFECYCLE_ERROR = 6

    // Log levels
    const val RAC_LOG_TRACE = 0
    const val RAC_LOG_DEBUG = 1
    const val RAC_LOG_INFO = 2
    const val RAC_LOG_WARN = 3
    const val RAC_LOG_ERROR = 4
    const val RAC_LOG_FATAL = 5
}
