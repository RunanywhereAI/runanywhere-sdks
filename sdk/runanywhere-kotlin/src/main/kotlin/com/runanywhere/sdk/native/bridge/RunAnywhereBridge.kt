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

import com.runanywhere.sdk.infrastructure.logging.Logging
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.hybrid.DeviceStateProvider

/*
 * Transport DTOs/listeners used by native HTTP bindings live in
 * RunAnywhereBridgeTransportTypes.kt. External JNI declarations stay on this
 * object because the native library exports Java_*_RunAnywhereBridge_* symbols.
 */

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
                // Route metadata-redaction policy through the canonical commons
                // C ABI so Kotlin SDKLogger and the C++ logger share one
                // sensitive-substring list (mirrors Swift's SDKLogger).
                Logging.shouldRedactPolicy = { key -> racLogMetadataShouldRedact(key) }
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

    /**
     * Determine whether a metadata key should be redacted in logs, delegating
     * to the canonical C++ policy `rac_log_metadata_should_redact`. Keeps
     * Kotlin and C++ logs in sync without duplicating the substring list.
     *
     * @param key Metadata key to check (non-null).
     * @return `true` if the key matches a sensitive substring and its value
     *         should be redacted; `false` otherwise.
     */
    @JvmStatic
    external fun racLogMetadataShouldRedact(key: String): Boolean

    // ========================================================================
    // MODEL PATHS (rac_model_paths.h) — Swift-canonical schema
    // Path shape: {base_dir}/RunAnywhere/Models/{framework.rawValue}/{modelId}/
    // ========================================================================

    /**
     * Set the base directory used by C++ path utilities.
     * Must be called once during SDK init before any model path lookups.
     */
    @JvmStatic
    external fun racModelPathsSetBaseDir(baseDir: String): Int

    /**
     * Get the model folder path under the canonical schema:
     * `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
     *
     * @param modelId Model identifier
     * @param framework Inference framework int matching RAC_FRAMEWORK_* values
     * @return The model folder path, or null on error
     */
    @JvmStatic
    external fun racModelPathsGetModelFolder(modelId: String, framework: Int): String?

    // ========================================================================
    // LLM COMPONENT (rac_llm_component.h)
    // ========================================================================

    @JvmStatic
    external fun racLlmComponentCreate(): Long

    @JvmStatic
    external fun racLlmComponentDestroy(handle: Long)

    // ========================================================================
    // LLM GENERATED-PROTO ABI (rac_llm_service.h)
    // ========================================================================

    @JvmStatic
    external fun racLlmGenerateProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racLlmGenerateStreamProto(
        requestProto: ByteArray,
        listener: NativeProtoProgressListener?,
    ): Int

    @JvmStatic
    external fun racLlmCancelProto(): ByteArray?

    // ========================================================================
    // STT COMPONENT (rac_stt_component.h)
    // ========================================================================

    @JvmStatic
    external fun racSttComponentCreate(): Long

    @JvmStatic
    external fun racSttComponentDestroy(handle: Long)

    @JvmStatic
    external fun racSttComponentCancel(handle: Long): Int

    // ========================================================================
    // STT LIFECYCLE-PROTO ABI (rac_stt_transcribe_*_lifecycle_proto)
    // Swift-aligned: mirrors iOS's `rac_stt_transcribe_lifecycle_proto`.
    // Takes a serialized STTTranscriptionRequest (with audio + options
    // bundled) and resolves the lifecycle-loaded STT model internally.
    // The legacy `racSttComponentTranscribe[Stream]Proto` were deleted in
    // favour of these lifecycle variants — no component-handle threading.
    // ========================================================================

    @JvmStatic
    external fun racSttTranscribeLifecycleProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racSttTranscribeStreamLifecycleProto(
        requestProto: ByteArray,
        listener: NativeProtoProgressListener?,
    ): Int

    // ========================================================================
    // TTS COMPONENT (rac_tts_component.h)
    // ========================================================================

    @JvmStatic
    external fun racTtsComponentCreate(): Long

    @JvmStatic
    external fun racTtsComponentDestroy(handle: Long)

    @JvmStatic
    external fun racTtsComponentCancel(handle: Long): Int

    // ========================================================================
    // TTS LIFECYCLE-PROTO ABI (rac_tts_{synthesize,synthesize_stream,
    // list_voices}_lifecycle_proto).
    // Swift-aligned: mirrors iOS's lifecycle-proto path. Takes a serialized
    // TTSSynthesisRequest (text + options bundled) and resolves the
    // lifecycle-loaded TTS voice internally. The legacy
    // `racTtsComponent{Synthesize,SynthesizeStream,ListVoices}Proto` JNI
    // exports were deleted — Kotlin SDK is lifecycle-only.
    // ========================================================================

    @JvmStatic
    external fun racTtsSynthesizeLifecycleProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racTtsSynthesizeStreamLifecycleProto(
        requestProto: ByteArray,
        listener: NativeProtoProgressListener?,
    ): Int

    @JvmStatic
    external fun racTtsListVoicesLifecycleProto(): ByteArray?

    /**
     * Stop an in-flight lifecycle-owned TTS synthesis. Mirrors iOS Swift's
     * `rac_tts_stop_lifecycle_proto` path — the v2 lifecycle TTS stack does
     * not require a per-component handle and the legacy
     * `racTtsComponentCancel(handle)` only addresses the
     * ComponentActor-managed component path. Returns a serialized
     * `TTSServiceState` proto.
     */
    @JvmStatic
    external fun racTtsStopLifecycleProto(): ByteArray?

    // ========================================================================
    // VAD COMPONENT (rac_vad_component.h)
    // ========================================================================

    @JvmStatic
    external fun racVadComponentCreate(): Long

    @JvmStatic
    external fun racVadComponentDestroy(handle: Long)

    @JvmStatic
    external fun racVadComponentReset(handle: Long): Int

    @JvmStatic
    external fun racVadComponentCancel(handle: Long): Int

    // ========================================================================
    // VAD GENERATED-PROTO ABI (rac_vad_component.h)
    // ========================================================================

    @JvmStatic
    external fun racVadComponentConfigureProto(handle: Long, configProto: ByteArray): Int

    @JvmStatic
    external fun racVadComponentProcessProto(
        handle: Long,
        samples: FloatArray,
        optionsProto: ByteArray?,
    ): ByteArray?

    @JvmStatic
    external fun racVadComponentGetStatisticsProto(handle: Long): ByteArray?

    // CALLBACK_TARGET — invoked from C++ via JNI (per-handle voice-activity callback registration)
    @JvmStatic
    external fun racVadComponentSetActivityProtoCallback(
        handle: Long,
        listener: NativeProtoProgressListener?,
    ): Int

    // ========================================================================
    // VAD STREAM PROTO ABI (rac_vad_stream.h) — Wave H-5
    // Lifecycle-owned proto-byte VADStreamEvent session API. Register the
    // per-handle listener, start a session to obtain a 64-bit session id, feed
    // PCM int16 mono audio frames, and stop/cancel to tear down.
    // ========================================================================

    @JvmStatic
    external fun racVadSetStreamProtoCallback(
        handle: Long,
        listener: NativeProtoProgressListener?,
    ): Int

    @JvmStatic
    external fun racVadStreamStartProto(handle: Long, optionsProto: ByteArray?): Long

    @JvmStatic
    external fun racVadStreamFeedAudioProto(sessionId: Long, audioBytes: ByteArray?): Int

    @JvmStatic
    external fun racVadStreamStopProto(sessionId: Long): Int

    @JvmStatic
    external fun racVadStreamCancelProto(sessionId: Long): Int

    // ========================================================================
    // VLM GENERATED-PROTO SERVICE ABI (rac_vlm_service.h)
    // ========================================================================

    @JvmStatic
    external fun racVlmComponentLoadResolvedArtifactsProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racVlmProcessProto(
        handle: Long,
        imageProto: ByteArray,
        optionsProto: ByteArray,
    ): ByteArray?

    @JvmStatic
    external fun racVlmProcessStreamProto(
        handle: Long,
        imageProto: ByteArray,
        optionsProto: ByteArray,
        listener: NativeProtoProgressListener?,
    ): ByteArray?

    @JvmStatic
    external fun racVlmCancelProto(handle: Long): Int

    /**
     * Lifecycle-style cancel (Wave 7 / T23, mirrors Swift's
     * `rac_vlm_cancel_lifecycle_proto`). The lifecycle ABI acquires the
     * lifecycle-owned VLM service internally and emits canonical
     * `CANCELLATION_EVENT_KIND_*` SDKEvents — no handle threaded.
     *
     * Returns the encoded `SDKEvent` proto on success, or `null` on
     * failure (e.g. no lifecycle VLM loaded). Symbol may not yet be
     * implemented in `librunanywhere_jni.so`; callers must catch
     * `UnsatisfiedLinkError` and fall back to the handle-based path.
     */
    @JvmStatic
    external fun racVlmCancelLifecycleProto(): ByteArray?

    @JvmStatic
    external fun racVlmDestroy(handle: Long)

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

    // Download + non-proto model-registry thunks removed per
    // gaps/kotlin.md KOT-JNI-ORPHAN. All of `racDownloadStart` /
    // `racDownloadCancel` / `racDownloadGetProgress` /
    // `racModelRegistry{Save,Get,GetAll,GetDownloaded,Remove,UpdateDownloadStatus}`
    // had zero Kotlin callers; the proto-backed siblings below
    // (`racDownloadStartProto`, `racModelRegistry*Proto`) are the canonical
    // surface.

    // ========================================================================
    // MODEL REGISTRY - Direct C++ registry access (mirrors Swift CppBridge+ModelRegistry)
    // ========================================================================

    /**
     * Register model metadata from serialized runanywhere.v1.ModelInfo bytes.
     *
     * The JNI implementation should forward to `rac_model_registry_register_proto`.
     */
    @JvmStatic
    external fun racModelRegistryRegisterProto(modelInfoProto: ByteArray): Int

    /**
     * Update existing model metadata from serialized runanywhere.v1.ModelInfo bytes.
     *
     * The JNI implementation should forward to `rac_model_registry_update_proto`.
     */
    @JvmStatic
    external fun racModelRegistryUpdateProto(modelInfoProto: ByteArray): Int

    /**
     * Get serialized runanywhere.v1.ModelInfo bytes for one model.
     *
     * Returns null when the model is not found or when the native proto ABI is unavailable.
     */
    @JvmStatic
    external fun racModelRegistryGetProto(modelId: String): ByteArray?

    /**
     * List all models as serialized runanywhere.v1.ModelInfoList bytes.
     *
     * Returns null when the native proto ABI is unavailable.
     */
    @JvmStatic
    external fun racModelRegistryListProto(): ByteArray?

    /**
     * Query model metadata using serialized runanywhere.v1.ModelQuery bytes.
     *
     * Returns serialized runanywhere.v1.ModelInfoList bytes.
     */
    @JvmStatic
    external fun racModelRegistryQueryProto(queryProto: ByteArray): ByteArray?

    /**
     * List downloaded models as serialized runanywhere.v1.ModelInfoList bytes.
     */
    @JvmStatic
    external fun racModelRegistryListDownloadedProto(): ByteArray?

    /**
     * Remove a model through the proto registry ABI surface.
     *
     * The JNI implementation should forward to `rac_model_registry_remove_proto`.
     */
    @JvmStatic
    external fun racModelRegistryRemoveProto(modelId: String): Int

    /**
     * Refresh the C++ model registry using serialized runanywhere.v1.ModelRegistryRefreshRequest bytes.
     *
     * Returns serialized runanywhere.v1.ModelRegistryRefreshResult bytes, or null when the
     * native proto ABI is unavailable.
     */
    @JvmStatic
    external fun racModelRegistryRefreshProto(requestProto: ByteArray): ByteArray?

    /**
     * Infer a ModelFormat from a portable URL/file-path string.
     *
     * The JNI implementation forwards to `rac_model_format_from_url_proto`.
     * Input is serialized runanywhere.v1.ModelFormatFromUrlRequest bytes; output
     * is serialized runanywhere.v1.ModelFormatFromUrlResult bytes, or null when
     * the native proto ABI is unavailable.
     */
    @JvmStatic
    external fun racModelFormatFromUrlProto(requestBytes: ByteArray): ByteArray?

    /**
     * Infer a ModelArtifactType from a portable URL/file-path string.
     *
     * The JNI implementation forwards to `rac_artifact_infer_from_url_proto`.
     * Input is serialized runanywhere.v1.ArtifactInferFromUrlRequest bytes;
     * output is serialized runanywhere.v1.ArtifactInferFromUrlResult bytes, or
     * null when the native proto ABI is unavailable.
     */
    @JvmStatic
    external fun racArtifactInferFromUrlProto(requestBytes: ByteArray): ByteArray?

    // ========================================================================
    // MODEL LIFECYCLE PROTO ABI (rac_model_lifecycle.h)
    // ========================================================================

    @JvmStatic
    external fun racModelLifecycleLoadProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racModelLifecycleUnloadProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racModelLifecycleCurrentModelProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racComponentLifecycleSnapshotProto(component: Int): ByteArray?

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
    // UTILITY — used from JNI helpers but not directly from Kotlin
    @JvmStatic
    external fun racAudioFloat32ToWav(pcmData: ByteArray, sampleRate: Int): ByteArray?

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
    // CALLBACK_TARGET — invoked from C++ via JNI (device-manager callback registration)
    @JvmStatic
    external fun racDeviceManagerSetCallbacks(callbacks: Any): Int

    /**
     * Register device with backend if not already registered.
     * @param environment SDK environment (0=DEVELOPMENT, 1=STAGING, 2=PRODUCTION)
     * @param buildToken Optional build token for development mode
     */
    @JvmStatic
    external fun racDeviceManagerRegisterIfNeeded(environment: Int, buildToken: String?): Int

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
    // CALLBACK_TARGET — invoked from C++ via JNI (analytics → telemetry callback registration)
    @JvmStatic
    external fun racAnalyticsEventsSetCallback(telemetryHandle: Long): Int

    /**
     * Emit a download/extraction event.
     * Maps to rac_analytics_model_download_t struct in C++.
     */
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
    @JvmStatic
    external fun racAnalyticsEventEmitNetwork(
        eventType: Int,
        isOnline: Boolean,
    ): Int

    /**
     * Emit an LLM generation event.
     * Maps to rac_analytics_llm_generation_t struct in C++.
     */
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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
    // CALLBACK_TARGET — invoked from C++ via JNI (telemetry emission entry point)
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

    @JvmStatic
    external fun racToolCallFormatPromptProto(requestProto: ByteArray): ByteArray?

    // ========================================================================
    // FILE MANAGER (rac_file_manager.h)
    // ========================================================================

    /**
     * Register file manager callbacks object.
     * The callback object must implement:
     * - createDirectory(path: String, recursive: Boolean): Int
     * - deletePath(path: String, recursive: Boolean): Int
     * - listDirectory(path: String): Array<String>?
     * - pathExists(path: String): Boolean
     * - isDirectory(path: String): Boolean
     * - getFileSize(path: String): Long
     * - getAvailableSpace(): Long
     * - getTotalSpace(): Long
     */
    @JvmStatic
    external fun nativeFileManagerRegisterCallbacks(callbacksObj: Any): Int

    @JvmStatic
    external fun nativeFileManagerClearCache(): Int

    @JvmStatic
    external fun nativeFileManagerClearTemp(): Int

    // ========================================================================
    // STORAGE PROTO ABI (rac_storage_analyzer.h)
    // ========================================================================

    @JvmStatic
    external fun racStorageInfoProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racStorageAvailabilityProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racStorageDeletePlanProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racStorageDeleteProto(requestProto: ByteArray): ByteArray?

    // ========================================================================
    // SDK EVENT STREAM PROTO ABI (rac_sdk_event_stream.h)
    // ========================================================================

    @JvmStatic
    external fun racSdkEventSubscribe(listener: NativeProtoProgressListener): Long

    @JvmStatic
    external fun racSdkEventUnsubscribe(subscriptionId: Long)

    @JvmStatic
    external fun racSdkEventPublishProto(eventProto: ByteArray): Int

    @JvmStatic
    external fun racSdkEventPoll(): ByteArray?

    @JvmStatic
    external fun racSdkEventPublishFailure(
        errorCode: Int,
        message: String,
        component: String,
        operation: String,
        recoverable: Boolean,
    ): Int

    // ========================================================================
    // DOWNLOAD PROTO ABI (rac_download_orchestrator.h)
    // ========================================================================

    @JvmStatic
    external fun racDownloadSetProgressProtoCallback(listener: NativeProtoProgressListener?): Int

    @JvmStatic
    external fun racDownloadPlanProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racDownloadStartProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racDownloadCancelProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racDownloadResumeProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racDownloadProgressPollProto(requestProto: ByteArray): ByteArray?

    // ========================================================================
    // VOICE AGENT (rac_voice_agent.h)
    // ========================================================================
    //
    // v3.1 P3.2: 4 thunks exposing the voice-agent handle lifecycle to
    // Kotlin. Mirrors Swift's CppBridge.VoiceAgent.shared.getHandle()
    // pattern. The handle is what VoiceAgentStreamAdapter(handle).stream()
    // subscribes to for proto event streaming.

    /** Create a standalone voice-agent handle that owns its STT/LLM/TTS/VAD
     *  component handles. Returns 0 on failure. */
    @JvmStatic external fun racVoiceAgentCreateStandalone(): Long

    /** Initialize a voice-agent handle against already-loaded STT/LLM/TTS
     *  models in the singleton component handles. Returns rac_result_t
     *  (0 = success). */
    @JvmStatic external fun racVoiceAgentInitializeWithLoadedModels(handle: Long): Int

    /** Check if the voice agent is ready (all required models loaded). */
    @JvmStatic external fun racVoiceAgentIsReady(handle: Long): Boolean

    /** Destroy the voice-agent handle and release owned component handles
     *  (when created via standalone). */
    @JvmStatic external fun racVoiceAgentDestroy(handle: Long)

    /** Initialize a voice-agent handle from serialized VoiceAgentComposeConfig bytes. */
    @JvmStatic external fun racVoiceAgentInitializeProto(handle: Long, configProto: ByteArray): ByteArray?

    /** Snapshot component state as serialized VoiceAgentComponentStates bytes. */
    @JvmStatic external fun racVoiceAgentComponentStatesProto(handle: Long): ByteArray?

    /** Process one voice turn and return serialized VoiceAgentResult bytes. */
    @JvmStatic external fun racVoiceAgentProcessVoiceTurnProto(handle: Long, audioData: ByteArray): ByteArray?

    // ========================================================================
    // TOOL-CALLING SESSION (rac_tool_calling.h — Wave D-4 / KOT-08)
    // ========================================================================
    //
    // Native-owned state machine for generate → parse → execute → loop. The
    // session emits ToolCallingSessionEvent bytes on each step. Kotlin only
    // supplies the tool registry + executor callback.

    /**
     * Create a tool-calling session. Accepts serialized
     * ToolCallingSessionCreateRequest bytes. Events are delivered on the
     * listener as ToolCallingSessionEvent bytes. Returns the session handle
     * (0 on failure).
     */
    @JvmStatic
    external fun racToolCallingSessionCreateProto(
        requestBytes: ByteArray,
        listener: NativeProtoProgressListener,
    ): Long

    /**
     * Feed a tool result into an in-flight tool-calling session. Accepts
     * serialized ToolCallingSessionStepWithResultRequest bytes (which
     * include the session handle). Returns rac_result_t.
     */
    @JvmStatic
    external fun racToolCallingSessionStepWithResultProto(requestBytes: ByteArray): Int

    /**
     * Destroy a tool-calling session. Releases the global listener ref.
     * Idempotent for handle=0.
     */
    @JvmStatic
    external fun racToolCallingSessionDestroyProto(sessionHandle: Long): Int

    /**
     * pass2-syn-007: Cancel an in-flight tool-calling session. Latches a
     * cancel-requested flag on the session and asks the in-flight
     * LifecycleLlmRef to abort the underlying backend `ops->generate`.
     * Safe to call from any thread; does NOT take the session mutex held
     * by the generate caller. Idempotent for unknown handles.
     */
    @JvmStatic
    external fun racToolCallingSessionCancelProto(sessionHandle: Long): Int

    // ========================================================================
    // SOLUTIONS (rac/solutions/rac_solution.h) — T4.7/T4.8
    // ========================================================================
    //
    // Proto-byte / YAML driven L5 solution runtime. Each call returns a
    // Long handle that wraps a `rac_solution_handle_t` from the C side;
    // pass the same handle to start/stop/cancel/feed/closeInput/destroy.
    // 0 from `racSolutionCreateFromProto` / `racSolutionCreateFromYaml`
    // signals failure (handle was never allocated).

    /** Construct a solution from a serialized `runanywhere.v1.SolutionConfig`
     *  (or `PipelineSpec`) protobuf. Returns 0 on failure. */
    @JvmStatic external fun racSolutionCreateFromProto(configBytes: ByteArray): Long

    /** Construct a solution from a YAML document. Returns 0 on failure. */
    @JvmStatic external fun racSolutionCreateFromYaml(yamlText: String): Long

    /** Start the underlying scheduler (non-blocking). Returns rac_result_t. */
    // PENDING — wired for future feature (solution scheduler not yet driven from Kotlin)
    @JvmStatic external fun racSolutionStart(handle: Long): Int

    /** Request a graceful shutdown (non-blocking). Returns rac_result_t. */
    @JvmStatic external fun racSolutionStop(handle: Long): Int

    /** Force-cancel the graph. Returns rac_result_t. */
    @JvmStatic external fun racSolutionCancel(handle: Long): Int

    /** Feed one UTF-8 item into the root input edge. Returns rac_result_t. */
    @JvmStatic external fun racSolutionFeed(handle: Long, item: String): Int

    /** Close the root input edge (signal end-of-stream). Returns rac_result_t. */
    // PENDING — wired for future feature (no current Kotlin caller)
    @JvmStatic external fun racSolutionCloseInput(handle: Long): Int

    /** Cancel, join, and destroy the solution. Always safe; null handle is a no-op. */
    @JvmStatic external fun racSolutionDestroy(handle: Long)

    // ========================================================================
    // EMBEDDINGS GENERATED-PROTO ABI (rac_embeddings_service.h)
    // ========================================================================

    @JvmStatic external fun racEmbeddingsCreate(modelId: String): Long

    @JvmStatic external fun racEmbeddingsEmbedBatchProto(handle: Long, requestProto: ByteArray): ByteArray?

    // ========================================================================
    // RAG PIPELINE GENERATED-PROTO ABI (rac_rag_pipeline.h)
    // ========================================================================

    /** Create a RAG session. Returns 0 on failure. */
    @JvmStatic external fun racRagSessionCreateProto(configProto: ByteArray): Long

    /** Destroy a RAG session and release all resources. */
    @JvmStatic external fun racRagSessionDestroyProto(handle: Long)

    /** Ingest one serialized RAGDocument and return serialized RAGStatistics bytes. */
    @JvmStatic external fun racRagIngestProto(handle: Long, documentProto: ByteArray): ByteArray?

    /** Run a query and return serialized RAGResult proto bytes. Null on error. */
    @JvmStatic external fun racRagQueryProto(handle: Long, queryProto: ByteArray): ByteArray?

    /** Clear all ingested documents and return serialized RAGStatistics bytes. */
    @JvmStatic external fun racRagClearProto(handle: Long): ByteArray?

    /** Get serialized RAGStatistics proto bytes. Null on error. */
    @JvmStatic external fun racRagStatsProto(handle: Long): ByteArray?

    // ========================================================================
    // LORA GENERATED-PROTO ABI (rac_lora_service.h)
    // ========================================================================

    @JvmStatic external fun racLoraApplyProto(requestProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraRemoveProto(requestProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraListProto(stateProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraStateProto(stateProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraCompatibilityProto(configProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraRegisterProto(entryProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraCatalogListProto(requestProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraCatalogQueryProto(queryProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraCatalogGetProto(requestProto: ByteArray): ByteArray?

    @JvmStatic
    external fun racLoraCatalogMarkDownloadCompletedProto(requestProto: ByteArray): ByteArray?

    // ========================================================================
    // PLUGIN LOADER (rac/router/rac_plugin_loader.h) — Round 1 G-A4
    // ========================================================================
    //
    // Round 1 KOTLIN (G-A4): added external thunks for the plugin loader.

    /** Returns the compile-time plugin API version this build supports. */
    @JvmStatic external fun racRegistryGetPluginApiVersion(): Int

    /** Load a plugin shared library at runtime. Returns rac_result_t. */
    @JvmStatic external fun racRegistryLoadPlugin(path: String): Int

    /** Unload a registered plugin by name. Returns rac_result_t. */
    @JvmStatic external fun racRegistryUnloadPlugin(name: String): Int

    /** Total number of currently registered plugins. */
    @JvmStatic external fun racRegistryGetPluginCount(): Int

    /** Snapshot of currently registered plugin names. */
    @JvmStatic external fun racRegistryGetRegisteredNames(): Array<String>?

    // ========================================================================
    // NATIVE HTTP DOWNLOAD (rac/infrastructure/http/rac_http_download.h)
    // ========================================================================
    //
    // Legacy direct HTTP runner retained for modality-specific adapters that
    // still need KOT-03 migration. Registry/model downloads use the generated
    // Download* proto service in CppBridgeDownload.
    //
    // @param url                  Absolute HTTP/HTTPS URL.
    // @param destPath             Local file path to write bytes to.
    // @param expectedSha256Hex    Lowercase hex SHA-256, or null/empty
    //                             to skip checksum verification.
    // @param resumeFromByte       Byte offset to resume from (0 = fresh).
    // @param timeoutMs            Timeout in ms (0 = no timeout).
    // @param listener             Optional progress listener (nullable).
    // @param outHttpStatus        Single-element int[] out-param: the
    //                             final HTTP status code. Pass null if
    //                             you don't need it.
    // @return RAC_HTTP_DL_* code from rac_http_download.h.
    @JvmStatic external fun racHttpDownloadExecute(
        url: String,
        destPath: String,
        expectedSha256Hex: String?,
        resumeFromByte: Long,
        timeoutMs: Int,
        listener: NativeDownloadProgressListener?,
        outHttpStatus: IntArray?,
    ): Int

    // ========================================================================
    // PLATFORM HTTP TRANSPORT (rac_http_transport.h) — v2 close-out Phase H4
    // ========================================================================
    //
    // Registers / unregisters the OkHttp-backed `rac_http_transport_ops`
    // adapter. When registered, every `rac_http_request_*` call from
    // native code routes through Kotlin's `CppBridgeHTTP` instead of
    // libcurl — so Android consumers get the system CA trust store,
    // NetworkSecurityConfig, user-CAs, and proxy support for free.
    //
    // The C++ side lives in `sdk/runanywhere-commons/src/jni/
    // okhttp_transport_adapter.cpp`.

    /** Register the OkHttp platform HTTP transport. Returns rac_result_t. */
    @JvmStatic external fun racHttpTransportRegisterOkHttp(): Int

    /** Unregister the OkHttp transport and fall back to libcurl. Returns rac_result_t. */
    @JvmStatic external fun racHttpTransportUnregisterOkHttp(): Int

    // ========================================================================
    // NATIVE HTTP REQUEST (rac_http_client.h)
    // ========================================================================
    //
    // v2.1 quick-wins / T3.5. Single blocking entrypoint that wraps
    // rac_http_client_create + rac_http_request_send + rac_http_response_free
    // + rac_http_client_destroy. Used by CppBridgeHTTP, CppBridgeAuth, and
    // CppBridgeTelemetry to replace per-SDK HttpURLConnection plumbing with
    // the libcurl-backed C ABI shared across Swift / Dart / RN / Web.
    //
    // Headers are passed as parallel String[] arrays (keys, values) to keep
    // the JNI signature flat. Return is a [NativeHttpResponse] or null only
    // on catastrophic JNI failure (class resolution failed).
    //
    // @param method         HTTP method ("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD").
    // @param url            Absolute HTTP/HTTPS URL.
    // @param headerKeys     Header name array (parallel to headerValues; may be empty).
    // @param headerValues   Header value array (parallel to headerKeys).
    // @param body           Request body bytes (null for GET/HEAD).
    // @param timeoutMs      Timeout in milliseconds (0 = no timeout).
    // @param followRedirects True to follow 3xx up to 10 hops.
    // @return [NativeHttpResponse] — statusCode == -1 + non-null errorMessage on transport error.
    @JvmStatic external fun racHttpRequestExecute(
        method: String,
        url: String,
        headerKeys: Array<String>,
        headerValues: Array<String>,
        body: ByteArray?,
        timeoutMs: Int,
        followRedirects: Boolean,
    ): NativeHttpResponse?

    // ========================================================================
    // CANONICAL DEFAULT HEADERS (Swift parity)
    // ========================================================================
    //
    // Thunk wrapping commons' shared HTTP policy helper. Used by
    // `HTTPClientAdapter` to converge on the same canonical SDK header
    // list Swift emits, instead of inlining the policy on the Kotlin
    // side.
    //
    // Upsert and structured error parsing are implemented Kotlin-side in
    // `HTTPClientAdapter.jvmAndroid.kt` — commons does not expose an
    // upsert-mode HTTP variant, and `rac_api_error_from_response` is
    // internal-only (non-RAC_API, not exported in `RACommons.exports`).

    /**
     * Wrapper for `rac_http_default_headers`. Returns commons' canonical
     * SDK header list as a flat alternating key/value array
     * (`[k0, v0, k1, v1, ...]`).
     *
     * Commons currently emits four entries:
     *   - "X-SDK-Client":  "RunAnywhereSDK"
     *   - "X-SDK-Version": rac_get_version().string
     *   - "Content-Type":  "application/json"
     *   - "Accept":        "application/json"
     *
     * The "X-Platform" header is intentionally NOT included — its value
     * is platform-specific and must be supplied per-request by the
     * calling SDK.
     *
     * Returns null only if the underlying C call fails (e.g. OOM in the
     * JNI marshalling path); callers fall back to inlined headers.
     */
    @JvmStatic external fun racHttpDefaultHeaders(): Array<String>?

    // ========================================================================
    // AUTH MANAGER (rac_auth_manager.h)
    // ========================================================================
    //
    // v2.1 quick-wins Item 4 / GAP 08 #2. 16 thunks delegating to the
    // matching rac_auth_* C ABI in runanywhere_commons_jni.cpp. The
    // higher-level CppBridgeAuth facade calls these instead of doing its
    // own HTTP/JSON state bookkeeping. The HTTP transport stays in Kotlin
    // (no JNI httpPost helper); native owns request building + response
    // parsing + state.

    /** Initialize auth state with in-memory storage. KeyStore-backed
     *  variant is the v2.1-2 follow-up. */
    @JvmStatic external fun racAuthInit()

    /** Reset auth state (clears in-memory tokens + IDs). */
    @JvmStatic external fun racAuthReset()

    @JvmStatic external fun racAuthIsAuthenticated(): Boolean

    @JvmStatic external fun racAuthNeedsRefresh(): Boolean

    @JvmStatic external fun racAuthGetAccessToken(): String?

    @JvmStatic external fun racAuthGetDeviceId(): String?

    @JvmStatic external fun racAuthGetUserId(): String?

    @JvmStatic external fun racAuthGetOrganizationId(): String?

    /** Build the JSON body for POST /api/v1/auth/sdk/authenticate.
     *  Returns null on error. The 6-arg signature mirrors rac_sdk_config_t.
     *  environment: 0 = DEVELOPMENT, 1 = STAGING, 2 = PRODUCTION. */
    @JvmStatic external fun racAuthBuildAuthenticateRequest(
        apiKey: String,
        baseUrl: String,
        deviceId: String,
        platform: String,
        sdkVersion: String,
        environment: Int,
    ): String?

    /** Build the JSON body for POST /api/v1/auth/sdk/refresh.
     *  Returns null if no refresh token is available. */
    @JvmStatic external fun racAuthBuildRefreshRequest(): String?

    /** Parse + store an authenticate response. Returns 0 on success, -1 on parse error. */
    @JvmStatic external fun racAuthHandleAuthenticateResponse(json: String): Int

    /** Parse + store a refresh response. Returns 0 on success, -1 on parse error. */
    @JvmStatic external fun racAuthHandleRefreshResponse(json: String): Int

    /** Returns String[2] = [token-or-null, "true"/"false"-needs-refresh] or null on error.
     *  Java has no clean tuple type so this avoids out-param games; the typed
     *  CppBridgeAuth wrapper unpacks it into a Pair<String?, Boolean>?. */
    @JvmStatic external fun racAuthGetValidToken(): Array<String?>?

    // ========================================================================
    // STRUCTURED OUTPUT (rac/features/llm/rac_structured_output.h)
    // ========================================================================

    @JvmStatic external fun racStructuredOutputParseProto(requestProto: ByteArray): ByteArray?

    @JvmStatic external fun racStructuredOutputPreparePromptProto(requestProto: ByteArray): ByteArray?

    @JvmStatic external fun racStructuredOutputValidateProto(requestProto: ByteArray): ByteArray?

    /**
     * Stream structured generation. Emits serialized `StructuredOutputStreamEvent`
     * payloads through [listener]. Returns `RAC_SUCCESS` when the generation
     * transport completed successfully.
     */
    @JvmStatic
    external fun racStructuredOutputGenerateStreamProto(
        requestProto: ByteArray,
        listener: NativeProtoProgressListener?,
    ): Int

    // ========================================================================
    // HARDWARE PROFILE (rac/hardware/rac_hardware_profile.h) — Round 2
    // ========================================================================
    //
    // Round 2 KOTLIN: Added JNI thunk for rac_hardware_profile_get which
    // was added by the C++ round 1 fix. Returns a serialized HardwareProfileResult
    // proto, or null if the C++ implementation is not wired yet.

    /** Get the hardware profile for the current device.
     *  Returns serialized HardwareProfileResult proto bytes, or null on failure. */
    @JvmStatic external fun racHardwareProfileGet(): ByteArray?

    // ========================================================================
    // ENGINE ROUTER — CAPABILITY QUERIES (Wave H-5 / KOT-12)
    // ========================================================================
    //
    // `rac_router_frameworks_for_capability_proto` consumes a serialized
    // `runanywhere.v1.FrameworksForCapabilityRequest` and returns a serialized
    // `runanywhere.v1.FrameworksForCapabilityResponse`. Replaces the local
    // SDKComponent → ModelCategory → framework mapping that used to live in
    // Kotlin.

    // ========================================================================
    // HARDWARE ACCELERATORS (Swift-alignment Phase 1 — Group A)
    // ========================================================================
    //
    // Surface the lightweight accelerator list and preference setter that
    // Swift's CppBridge+Hardware uses (rac_hardware_get_accelerators /
    // rac_hardware_set_accelerator_preference). Different from
    // racHardwareProfileGet, which returns the full HardwareProfileResult.

    /** Get the accelerator list only (HardwareProfileResult with profile field empty).
     *  Returns serialized HardwareProfileResult proto bytes, or null on failure. */
    @JvmStatic external fun racHardwareGetAccelerators(): ByteArray?

    /** Set the accelerator preference for subsequent inference calls.
     *  @param bytes serialized AcceleratorPreference proto bytes (or single-byte enum).
     *  @return rac_result_t (0 = success). */
    @JvmStatic external fun racHardwareSetAcceleratorPreference(bytes: ByteArray): Int

    // ========================================================================
    // VAD COMPONENT METADATA (Swift-alignment Phase 1 — Group A)
    // ========================================================================

    /** Check if the VAD component is initialized. */
    @JvmStatic external fun racVadComponentIsInitialized(handle: Long): Boolean

    /** Unload the VAD model. Returns rac_result_t. */
    @JvmStatic external fun racVadComponentUnload(handle: Long): Int

    /** Cleanup the VAD component (release all resources). Returns rac_result_t. */
    @JvmStatic external fun racVadComponentCleanup(handle: Long): Int

    // ========================================================================
    // VAD LIFECYCLE PROTO ABI (rac_vad_service.h — Swift-alignment Phase 1 — Group B)
    //
    // Handle-less lifecycle-owned VAD operations. Each routes through the
    // commons VAD lifecycle to the currently-loaded VAD service. Mirrors
    // Swift `VADGeneratedProtoABI.configureLifecycle/startLifecycle/...`.
    //
    // ========================================================================

    /**
     * Configure the lifecycle-loaded VAD with a VADConfiguration proto.
     * Returns serialized VADServiceState proto bytes, or null on failure.
     */
    @JvmStatic external fun racVadConfigureLifecycleProto(configProto: ByteArray): ByteArray?

    /**
     * Start the lifecycle-loaded VAD processing session.
     * Returns serialized VADServiceState proto bytes, or null on failure.
     */
    @JvmStatic external fun racVadStartLifecycleProto(): ByteArray?

    /**
     * Stop the lifecycle-loaded VAD processing session.
     * Returns serialized VADServiceState proto bytes, or null on failure.
     */
    @JvmStatic external fun racVadStopLifecycleProto(): ByteArray?

    /**
     * Reset internal state on the lifecycle-loaded VAD.
     * Returns serialized VADServiceState proto bytes, or null on failure.
     */
    @JvmStatic external fun racVadResetLifecycleProto(): ByteArray?

    /**
     * Process one VAD frame on the lifecycle-loaded model (handle-less).
     * Takes serialized [VADProcessRequest], returns serialized [VADResult].
     */
    @JvmStatic external fun racVadProcessLifecycleProto(requestProto: ByteArray): ByteArray?

    // ========================================================================
    // VLM COMPONENT METADATA (Swift-alignment Phase 1 — Group A)
    // ========================================================================

    /** Check if the VLM component supports streaming. */
    @JvmStatic external fun racVlmComponentSupportsStreaming(handle: Long): Boolean

    /** Get current VLM lifecycle state. Returns rac_lifecycle_state_t enum value. */
    @JvmStatic external fun racVlmComponentGetState(handle: Long): Int

    // ========================================================================
    // STT COMPONENT METADATA (Swift-alignment Phase 1 — Group A)
    // ========================================================================

    /** Check if the STT component supports streaming. */
    @JvmStatic external fun racSttComponentSupportsStreaming(handle: Long): Boolean

    /** Configure the STT component with a preferred framework int.
     *  All other config fields use their RAC_STT_CONFIG_DEFAULT values.
     *  Returns rac_result_t. */
    @JvmStatic external fun racSttComponentConfigure(handle: Long, framework: Int): Int

    // ========================================================================
    // VOICE AGENT — COMPOSITE LIFECYCLE (Swift-alignment Phase 1 — Group B)
    // ========================================================================

    /** Create a voice-agent handle that wraps four already-created STT/LLM/TTS/VAD
     *  component handles. Mirrors Swift's voice-agent composite constructor.
     *  Returns 0 on failure. */
    @JvmStatic external fun racVoiceAgentCreate(llm: Long, stt: Long, tts: Long, vad: Long): Long

    /** Cleanup the voice-agent — unload child components but keep the handle alive.
     *  Returns rac_result_t. */
    @JvmStatic external fun racVoiceAgentCleanup(handle: Long): Int

    // ========================================================================
    // PROTO BRIDGES — Lifecycle/Registry/Structured Output (Group C)
    // ========================================================================

    /** Clear queued SDKEvents without removing subscriptions. Test helper.
     *  Returns 0 on success. */
    @JvmStatic external fun racSdkEventClearQueue(): Int

    /** Reset model lifecycle tracking — unloads all tracked models. Test helper.
     *  Returns 0 on success. */
    @JvmStatic external fun racModelLifecycleReset(): Int

    /** Run a model discovery against the registry from serialized
     *  ModelDiscoveryRequest bytes. Returns serialized ModelDiscoveryResult bytes. */
    @JvmStatic external fun racModelRegistryDiscoverProto(req: ByteArray): ByteArray?

    /** Import an externally-managed model into the registry from serialized
     *  ModelImportRequest bytes. Returns serialized ModelImportResult bytes. */
    @JvmStatic external fun racModelRegistryImportProto(req: ByteArray): ByteArray?

    /** Generate structured output (JSON-schema constrained) given serialized
     *  StructuredOutputRequest bytes. Returns serialized StructuredOutputResult bytes.
     *  Handle is reserved for forward compatibility — current C ABI is handle-less. */
    @JvmStatic external fun racStructuredOutputGenerateProto(handle: Long, req: ByteArray): ByteArray?

    // ========================================================================
    // SDK STATE ACCESSORS (Swift-alignment Phase 1 — Group D)
    // ========================================================================
    //
    // Mirrors Swift's CppBridge+State.swift. Reads the global SDK state
    // populated by racSdkInit. Returns null/0 if SDK is not initialized.

    /** Get current SDK environment (rac_environment_t enum value). */
    @JvmStatic external fun racStateGetEnvironment(): Int

    /** Get configured base URL, or null. */
    @JvmStatic external fun racStateGetBaseUrl(): String?

    /** Get configured API key, or null. */
    @JvmStatic external fun racStateGetApiKey(): String?

    /** Get configured device ID, or null. */
    @JvmStatic external fun racStateGetDeviceId(): String?

    /** Set the device-registered flag. Returns 0 on success. */
    @JvmStatic external fun racStateSetDeviceRegistered(registered: Boolean): Int

    /** Check whether the device-registered flag is set. */
    @JvmStatic external fun racStateIsDeviceRegistered(): Boolean

    /** Resolve or create the persistent device ID. Returns null on failure. */
    @JvmStatic external fun racDeviceGetOrCreatePersistentId(): String?

    // ========================================================================
    // MODEL PATHS — FULL SURFACE (Swift-alignment Phase 1 — Group F)
    // ========================================================================
    //
    // Mirrors Swift's CppBridge+ModelPaths. racModelPathsSetBaseDir +
    // racModelPathsGetModelFolder already exist above — the rest of the
    // canonical schema is exposed below.

    /** Get the canonical models directory ({base}/RunAnywhere/Models). Null on error. */
    @JvmStatic external fun racModelPathsGetModelsDirectory(): String?

    /** Get the framework-specific directory ({base}/.../Models/{framework}). Null on error. */
    @JvmStatic external fun racModelPathsGetFrameworkDirectory(framework: Int): String?

    /** Get the canonical model file path for a (modelId, framework, format) triple. Null on error. */
    @JvmStatic
    external fun racModelPathsGetExpectedModelPath(modelId: String, framework: Int, format: Int): String?

    /** Get the cache directory. Null on error. */
    @JvmStatic external fun racModelPathsGetCacheDirectory(): String?

    /** Get the downloads staging directory. Null on error. */
    @JvmStatic external fun racModelPathsGetDownloadsDirectory(): String?

    /** Get the temp directory. Null on error. */
    @JvmStatic external fun racModelPathsGetTempDirectory(): String?

    /** Extract the modelId from a canonical model path. Null if not a recognized model path. */
    @JvmStatic external fun racModelPathsExtractModelId(path: String): String?

    /** Extract the framework int from a canonical model path. -1 if not a recognized model path. */
    @JvmStatic external fun racModelPathsExtractFramework(path: String): Int

    /** Check if the given path is a canonical model path. */
    @JvmStatic external fun racModelPathsIsModelPath(path: String): Boolean

    // ========================================================================
    // FILE MANAGER — FULL PROTO/STRUCTURED SURFACE (Group G)
    // ========================================================================
    //
    // The racFileManager* bindings below provide the Swift-aligned naming for
    // file-manager operations, including the model-folder-has-contents and
    // proto-based variants Swift uses. Legacy nativeFileManager* thunks have
    // been removed in favour of these racFileManager* equivalents; only
    // nativeFileManagerRegisterCallbacks / ClearCache / ClearTemp remain.

    /** Create the canonical models directory structure under rootPath. Returns 0 on success. */
    @JvmStatic external fun racFileManagerCreateDirectoryStructure(rootPath: String): Int

    /** Calculate the total size of a directory (bytes). Returns 0 on error. */
    @JvmStatic external fun racFileManagerCalculateDirectorySize(path: String): Long

    /** Compute total bytes used under the models directory. Returns 0 on error. */
    @JvmStatic external fun racFileManagerModelsStorageUsed(): Long

    /** Compute total bytes used under the cache directory. Returns 0 on error. */
    @JvmStatic external fun racFileManagerCacheSize(): Long

    /** Delete a model's on-disk folder. Returns rac_result_t. */
    @JvmStatic external fun racFileManagerDeleteModel(modelId: String): Int

    /** Check if a model's on-disk folder exists. */
    @JvmStatic external fun racFileManagerModelFolderExists(modelId: String): Boolean

    /** Check if a model's on-disk folder has any files inside. */
    @JvmStatic external fun racFileManagerModelFolderHasContents(modelId: String): Boolean

    /** Get storage info as serialized FileManagerStorageInfo bytes, or null on error. */
    @JvmStatic external fun racFileManagerGetStorageInfo(): ByteArray?

    /** Check if `required` bytes are available. Returns true if so. */
    @JvmStatic external fun racFileManagerCheckStorage(required: Long): Boolean

    // ========================================================================
    // ENVIRONMENT VALIDATION + ENDPOINTS (Swift-alignment Phase 1 — Group H)
    // ========================================================================

    /** Check if an environment int requires API authentication. */
    @JvmStatic external fun racEnvRequiresAuth(env: Int): Boolean

    /** Check if an environment int requires a backend URL. */
    @JvmStatic external fun racEnvRequiresBackendUrl(env: Int): Boolean

    /** Validate an API key for the current environment. Returns true if RAC_VALIDATION_OK. */
    @JvmStatic external fun racEnvValidateApiKey(key: String): Boolean

    /** Validate a base URL for the current environment. Returns true if RAC_VALIDATION_OK. */
    @JvmStatic external fun racEnvValidateBaseUrl(url: String): Boolean

    /** Get the human-readable validation error message for the given (env, key, url) triple,
     *  or null if validation succeeds. */
    @JvmStatic external fun racEnvValidationErrorMessage(env: Int, key: String, url: String): String?

    /** Get the authenticate endpoint path. */
    @JvmStatic external fun racEndpointAuthenticate(): String?

    /** Get the auth-refresh endpoint path. */
    @JvmStatic external fun racEndpointRefresh(): String?

    /** Get the health-check endpoint path. */
    @JvmStatic external fun racEndpointHealth(): String?

    /** Get the device-registration endpoint path for an environment. */
    @JvmStatic external fun racEndpointDeviceRegistration(env: Int): String?

    /** Get the telemetry endpoint path for an environment. */
    @JvmStatic external fun racEndpointTelemetry(env: Int): String?

    /** Get the model-assignments endpoint path (env-independent). */
    @JvmStatic external fun racEndpointModelAssignments(): String?

    // ========================================================================
    // HYBRID ROUTER (rac_llm_hybrid_router.h)
    // ========================================================================

    /**
     * Wrap an in-tree LLM backend (e.g. llama.cpp) in a `rac_llm_service_t`.
     * Resolves [modelId] through the C model registry (`rac_get_model`) to
     * locate the gguf path + inference framework, then dispatches to the
     * matching plugin's `create` op.
     *
     * The returned handle is owned by the caller and must be released via
     * [racLlmServiceDestroy]. The same handle can be passed to
     * [racLlmHybridRouterSetOfflineService].
     *
     * @param modelId Registry id (or gguf path as fallback).
     * @return Native handle cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racLlmServiceCreate(modelId: String): Long

    /**
     * Destroy a handle previously returned by [racLlmServiceCreate].
     * Safe to call with 0. Releases backend resources (gguf, KV cache, ...).
     */
    @JvmStatic external fun racLlmServiceDestroy(serviceHandle: Long)

    /**
     * Register a Kotlin [DeviceStateProvider]
     * as the cross-SDK device-state vtable in commons. The C hybrid router
     * calls back into the provider's three methods on every generate() to
     * populate the routing context's `is_online`, `battery_percent`, and
     * `thermal_throttled` fields.
     *
     * Passing `null` unsets the current provider and restores commons'
     * optimistic default vtable.
     *
     * @return RAC_SUCCESS (0) on success; negative error code otherwise.
     */
    @JvmStatic external fun racHybridSetDeviceState(
        provider: DeviceStateProvider?,
    ): Int

    /**
     * Allocate a new LLM hybrid router. Returns an opaque handle that
     * subsequent `racLlmHybridRouterSet*` / `racLlmHybridRouterGenerate`
     * calls operate on.
     *
     * @return Native router handle cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racLlmHybridRouterCreate(): Long

    /**
     * Destroy a router handle returned by [racLlmHybridRouterCreate].
     * Detaches any attached services first (services are NOT freed — the
     * caller owns those).
     */
    @JvmStatic external fun racLlmHybridRouterDestroy(handle: Long)

    /**
     * Attach the offline-side LLM service to a router. Passing
     * [serviceHandle] = 0 with an empty [descriptorProto] clears the slot.
     *
     * @param routerHandle    Router handle from [racLlmHybridRouterCreate].
     * @param serviceHandle   Service handle from [racLlmServiceCreate] (or 0 to clear).
     * @param descriptorProto Serialized `runanywhere.v1.HybridModelDescriptor`
     *                        bytes (see HybridRouterProto.descriptor).
     * @return `RAC_SUCCESS` (0) or a negative error code.
     */
    @JvmStatic external fun racLlmHybridRouterSetOfflineService(
        routerHandle: Long,
        serviceHandle: Long,
        descriptorProto: ByteArray,
    ): Int

    /**
     * Attach the online-side LLM service. Symmetric to
     * [racLlmHybridRouterSetOfflineService].
     */
    @JvmStatic external fun racLlmHybridRouterSetOnlineService(
        routerHandle: Long,
        serviceHandle: Long,
        descriptorProto: ByteArray,
    ): Int

    /**
     * Install / replace the routing policy on the router.
     *
     * @param routerHandle Router handle from [racLlmHybridRouterCreate].
     * @param policyProto  Serialized `runanywhere.v1.HybridRoutingPolicy`
     *                     bytes (see HybridRouterProto.policy).
     * @return `RAC_SUCCESS` (0) or a negative error code.
     */
    @JvmStatic external fun racLlmHybridRouterSetPolicy(
        routerHandle: Long,
        policyProto: ByteArray,
    ): Int

    /**
     * Dispatch one text-generation request through the router. The native
     * side applies filters → ranks → invokes the primary candidate →
     * cascades on confidence/error → returns a
     * `runanywhere.v1.HybridLlmGenerateResponse` byte payload.
     *
     * @param routerHandle Router handle from [racLlmHybridRouterCreate].
     * @param requestProto Serialized `runanywhere.v1.HybridLlmGenerateRequest`
     *                     bytes carrying the prompt, context, and options
     *                     (see HybridRouterProto.request).
     * @return Serialized HybridLlmGenerateResponse bytes, or null on hard
     *         JNI failure.
     */
    @JvmStatic external fun racLlmHybridRouterGenerate(
        routerHandle: Long,
        requestProto: ByteArray,
    ): ByteArray?

    /**
     * Streaming variant of [racLlmHybridRouterGenerate]. Native blocks the
     * calling thread for the duration of the stream, invoking
     * [com.runanywhere.sdk.public.hybrid.HybridStreamCallback.onToken] for
     * each token and exactly one
     * [com.runanywhere.sdk.public.hybrid.HybridStreamCallback.onDone] when
     * the stream terminates (success, failure, or cancellation).
     *
     * @param routerHandle Router handle from [racLlmHybridRouterCreate].
     * @param requestProto Serialized `runanywhere.v1.HybridLlmGenerateRequest`.
     * @param callback     Non-null sink for tokens + final metadata.
     * @return The native rc; `onDone` always fires regardless.
     */
    @JvmStatic external fun racLlmHybridRouterGenerateStream(
        routerHandle: Long,
        requestProto: ByteArray,
        callback: com.runanywhere.sdk.public.hybrid.HybridStreamCallback,
    ): Int

    /**
     * Cancel the in-flight generate / generate_stream call on [routerHandle].
     * Safe to call from any thread; no-op when no call is in flight.
     */
    @JvmStatic external fun racLlmHybridRouterCancel(routerHandle: Long): Int

    // ========================================================================
    // STT HYBRID ROUTER (rac_stt_hybrid_router.h)
    // ========================================================================

    /**
     * Wrap an in-tree STT backend (e.g. sherpa-onnx) in a
     * `rac_stt_service_t`. Resolves [modelId] through the C model registry
     * (`rac_get_model`) to locate the model path + inference framework,
     * then dispatches to the matching plugin's `create` op.
     *
     * The returned handle is owned by the caller and must be released via
     * [racSttServiceDestroy]. The same handle can be passed to
     * [racSttHybridRouterSetOfflineService].
     *
     * @param modelId Registry id (or model path as fallback).
     * @return Native handle cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racSttServiceCreate(modelId: String): Long

    /**
     * Destroy a handle previously returned by [racSttServiceCreate].
     * Safe to call with 0.
     */
    @JvmStatic external fun racSttServiceDestroy(serviceHandle: Long)

    /**
     * Allocate a new STT hybrid router. Returns an opaque handle that
     * subsequent `racSttHybridRouterSet*` / `racSttHybridRouterTranscribe`
     * calls operate on.
     *
     * @return Native router handle cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racSttHybridRouterCreate(): Long

    /**
     * Destroy a router handle returned by [racSttHybridRouterCreate].
     * Detaches any attached services first (services are NOT freed — the
     * caller owns those).
     */
    @JvmStatic external fun racSttHybridRouterDestroy(handle: Long)

    /**
     * Attach the offline-side STT service to a router. Passing
     * [serviceHandle] = 0 with an empty [descriptorProto] clears the slot.
     */
    @JvmStatic external fun racSttHybridRouterSetOfflineService(
        routerHandle: Long,
        serviceHandle: Long,
        descriptorProto: ByteArray,
    ): Int

    /** Attach the online-side STT service. Symmetric to the offline setter. */
    @JvmStatic external fun racSttHybridRouterSetOnlineService(
        routerHandle: Long,
        serviceHandle: Long,
        descriptorProto: ByteArray,
    ): Int

    /**
     * Install / replace the routing policy on the STT router.
     *
     * @param policyProto Serialized `runanywhere.v1.HybridRoutingPolicy`.
     */
    @JvmStatic external fun racSttHybridRouterSetPolicy(
        routerHandle: Long,
        policyProto: ByteArray,
    ): Int

    /**
     * Dispatch one transcribe request through the router. Returns a
     * serialized `runanywhere.v1.HybridSttTranscribeResponse` byte payload,
     * or null on hard JNI failure.
     */
    @JvmStatic external fun racSttHybridRouterTranscribe(
        routerHandle: Long,
        requestProto: ByteArray,
    ): ByteArray?

    /**
     * Cancel the in-flight transcribe call on [routerHandle]. Currently a
     * no-op since rac_stt_service_ops_t has no cancel op; reserved so the
     * Kotlin facade can call it unconditionally.
     */
    @JvmStatic external fun racSttHybridRouterCancel(routerHandle: Long): Int

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
    const val RAC_ERROR_NOT_FOUND = -423
    const val RAC_ERROR_FEATURE_NOT_AVAILABLE = -801

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
