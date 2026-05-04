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
        fun onToken(token: ByteArray): Boolean
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
    // LLM LORA ADAPTER (rac_llm_component.h - LoRA section)
    // ========================================================================

    @JvmStatic
    external fun racLlmComponentLoadLora(handle: Long, adapterPath: String, scale: Float): Int

    @JvmStatic
    external fun racLlmComponentRemoveLora(handle: Long, adapterPath: String): Int

    @JvmStatic
    external fun racLlmComponentClearLora(handle: Long): Int

    @JvmStatic
    external fun racLlmComponentGetLoraInfo(handle: Long): String?

    @JvmStatic
    external fun racLlmComponentCheckLoraCompat(handle: Long, loraPath: String): String?

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

    // ========================================================================
    // STT GENERATED-PROTO ABI (rac_stt_component.h)
    // ========================================================================

    @JvmStatic
    external fun racSttComponentTranscribeProto(
        handle: Long,
        audioData: ByteArray,
        optionsProto: ByteArray?,
    ): ByteArray?

    @JvmStatic
    external fun racSttComponentTranscribeStreamProto(
        handle: Long,
        audioData: ByteArray,
        optionsProto: ByteArray?,
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

    // ========================================================================
    // TTS GENERATED-PROTO ABI (rac_tts_component.h)
    // ========================================================================

    @JvmStatic
    external fun racTtsComponentListVoicesProto(
        handle: Long,
        listener: NativeProtoProgressListener,
    ): Int

    @JvmStatic
    external fun racTtsComponentSynthesizeProto(
        handle: Long,
        text: String,
        optionsProto: ByteArray?,
    ): ByteArray?

    @JvmStatic
    external fun racTtsComponentSynthesizeStreamProto(
        handle: Long,
        text: String,
        optionsProto: ByteArray?,
        listener: NativeProtoProgressListener?,
    ): Int

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

    @JvmStatic
    external fun racVadComponentSetActivityProtoCallback(
        handle: Long,
        listener: NativeProtoProgressListener?,
    ): Int

    // ========================================================================
    // VLM COMPONENT (rac_vlm_component.h)
    // ========================================================================

    @JvmStatic
    external fun racVlmComponentCreate(): Long

    @JvmStatic
    external fun racVlmComponentDestroy(handle: Long)

    @JvmStatic
    external fun racVlmComponentLoadModel(
        handle: Long,
        modelPath: String,
        mmprojPath: String?,
        modelId: String,
        modelName: String?,
    ): Int

    @JvmStatic
    external fun racVlmComponentLoadModelById(handle: Long, modelId: String): Int

    @JvmStatic
    external fun racVlmComponentUnload(handle: Long): Int

    @JvmStatic
    external fun racVlmComponentCancel(handle: Long): Int

    @JvmStatic
    external fun racVlmComponentIsLoaded(handle: Long): Boolean

    @JvmStatic
    external fun racVlmComponentGetModelId(handle: Long): String?

    /**
     * Process an image (non-streaming).
     *
     * @param handle VLM component handle
     * @param imageFormat Image format (0=FILE_PATH, 1=RGB_PIXELS, 2=BASE64)
     * @param imagePath File path (for FILE_PATH format)
     * @param imageData RGB pixel data (for RGB_PIXELS format)
     * @param imageBase64 Base64-encoded data (for BASE64 format)
     * @param imageWidth Image width (for RGB_PIXELS format)
     * @param imageHeight Image height (for RGB_PIXELS format)
     * @param prompt Text prompt
     * @param optionsJson Generation options as JSON string
     * @return JSON result string or null on error
     */
    @JvmStatic
    external fun racVlmComponentProcess(
        handle: Long,
        imageFormat: Int,
        imagePath: String?,
        imageData: ByteArray?,
        imageBase64: String?,
        imageWidth: Int,
        imageHeight: Int,
        prompt: String,
        optionsJson: String?,
    ): String?

    /**
     * Process an image with streaming output.
     * Calls tokenCallback for each generated token.
     *
     * @param handle VLM component handle
     * @param imageFormat Image format (0=FILE_PATH, 1=RGB_PIXELS, 2=BASE64)
     * @param imagePath File path (for FILE_PATH format)
     * @param imageData RGB pixel data (for RGB_PIXELS format)
     * @param imageBase64 Base64-encoded data (for BASE64 format)
     * @param imageWidth Image width (for RGB_PIXELS format)
     * @param imageHeight Image height (for RGB_PIXELS format)
     * @param prompt Text prompt
     * @param optionsJson Generation options as JSON string
     * @param tokenCallback Callback invoked for each generated token
     * @return JSON result string with final metrics, or null on error
     */
    @JvmStatic
    external fun racVlmComponentProcessStream(
        handle: Long,
        imageFormat: Int,
        imagePath: String?,
        imageData: ByteArray?,
        imageBase64: String?,
        imageWidth: Int,
        imageHeight: Int,
        prompt: String,
        optionsJson: String?,
        tokenCallback: TokenCallback,
    ): String?

    @JvmStatic
    external fun racVlmComponentSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun racVlmComponentGetState(handle: Long): Int

    @JvmStatic
    external fun racVlmComponentGetMetrics(handle: Long): String?

    // ========================================================================
    // VLM GENERATED-PROTO SERVICE ABI (rac_vlm_service.h)
    // ========================================================================

    @JvmStatic
    external fun racVlmCreate(modelIdOrPath: String): Long

    @JvmStatic
    external fun racVlmInitialize(handle: Long, modelPath: String, mmprojPath: String?): Int

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

    @JvmStatic
    external fun racVlmDestroy(handle: Long)

    // ========================================================================
    // ARCHIVE EXTRACTION (rac_extraction.h)
    // ========================================================================

    /** Extract an archive (ZIP, TAR.GZ, TAR.BZ2, TAR.XZ) to destination directory.
     *  Returns RAC_SUCCESS (0) on success, negative error code on failure. */
    @JvmStatic
    external fun nativeExtractArchive(archivePath: String, destinationDir: String): Int

    /** Detect archive type from magic bytes. Returns rac_archive_type_t enum value, or -1 on failure. */
    @JvmStatic
    external fun nativeDetectArchiveType(filePath: String): Int

    // ========================================================================
    // DOWNLOAD ORCHESTRATOR (rac_download_orchestrator.h)
    // ========================================================================

    /** Find model path after extraction. Returns the actual model file/directory path.
     *  Uses C++ rac_find_model_path_after_extraction() — consolidated from platform-specific logic.
     *  @param extractedDir Directory where archive was extracted
     *  @param structure Archive structure hint (rac_archive_structure_t enum ordinal)
     *  @param framework Inference framework (rac_inference_framework_t enum ordinal)
     *  @param format Model format (rac_model_format_t enum ordinal)
     *  @return The found model path, or extractedDir as fallback */
    @JvmStatic
    external fun nativeFindModelPathAfterExtraction(
        extractedDir: String,
        structure: Int,
        framework: Int,
        format: Int,
    ): String

    /** Check if a download URL requires extraction.
     *  Uses C++ rac_download_requires_extraction() — handles .tar.gz, .tar.bz2, .zip, etc.
     *  @return true if URL points to an archive */
    @JvmStatic
    external fun nativeDownloadRequiresExtraction(url: String): Boolean

    /** Compute download destination path.
     *  Uses C++ rac_download_compute_destination().
     *  @return Destination path, or null on failure */
    @JvmStatic
    external fun nativeComputeDownloadDestination(
        modelId: String,
        downloadUrl: String,
        framework: Int,
        format: Int,
    ): String?

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
        supportsLora: Boolean,
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
     * Refresh the C++ model registry (T4.9).
     *
     * Backed by `rac_model_registry_refresh` in commons. Each flag is
     * independent; steps that require unavailable infrastructure (e.g. the
     * model assignment HTTP callbacks) are skipped silently.
     *
     * @param includeRemoteCatalog Fetch the backend model catalog.
     * @param rescanLocal Rescan the on-disk model directories (no-op from JVM
     *   until the Kotlin SDK wires discovery callbacks; today discovery runs
     *   in Kotlin via `ModelFileSystem`).
     * @param pruneOrphans Clear `localPath` entries whose file no longer
     *   exists (no-op from JVM for the same reason as `rescanLocal`).
     * @return `RAC_SUCCESS` (0) on success, otherwise the first error code
     *   encountered while running the requested steps.
     */
    @JvmStatic
    external fun racModelRegistryRefresh(
        includeRemoteCatalog: Boolean,
        rescanLocal: Boolean,
        pruneOrphans: Boolean,
    ): Int

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
    // LORA REGISTRY (rac_lora_registry.h)
    // ========================================================================

    @JvmStatic
    external fun racLoraRegistryRegister(
        id: String,
        name: String,
        description: String,
        downloadUrl: String,
        filename: String,
        compatibleModelIds: Array<String>,
        fileSize: Long,
        defaultScale: Float,
    ): Int

    @JvmStatic
    external fun racLoraRegistryGetForModel(modelId: String): String

    @JvmStatic
    external fun racLoraRegistryGetAll(): String

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
     * Format tool definitions into system prompt with specified format (int).
     *
     * @param toolsJson JSON array of tool definitions
     * @param format Tool calling format (0=AUTO, 1=DEFAULT, 2=LFM2, 3=OPENAI)
     * @return Formatted prompt string, or null on error
     */
    @JvmStatic
    external fun racToolCallFormatPromptJsonWithFormat(toolsJson: String, format: Int): String?

    /**
     * Format tool definitions into system prompt with format specified by name.
     *
     * *** PREFERRED API - Uses string format name ***
     *
     * Valid format names (case-insensitive): "auto", "default", "lfm2", "openai"
     * C++ is single source of truth for format validation.
     *
     * @param toolsJson JSON array of tool definitions
     * @param formatName Format name string (e.g., "lfm2", "default")
     * @return Formatted prompt string, or null on error
     */
    @JvmStatic
    external fun racToolCallFormatPromptJsonWithFormatName(toolsJson: String, formatName: String): String?

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
    external fun nativeFileManagerCreateDirectoryStructure(): Int

    @JvmStatic
    external fun nativeFileManagerCalculateDirSize(path: String): Long

    @JvmStatic
    external fun nativeFileManagerModelsStorageUsed(): Long

    @JvmStatic
    external fun nativeFileManagerClearCache(): Int

    @JvmStatic
    external fun nativeFileManagerClearTemp(): Int

    @JvmStatic
    external fun nativeFileManagerCacheSize(): Long

    @JvmStatic
    external fun nativeFileManagerDeleteModel(modelId: String, framework: Int): Int

    @JvmStatic
    external fun nativeFileManagerCreateModelFolder(modelId: String, framework: Int): String?

    @JvmStatic
    external fun nativeFileManagerModelFolderExists(modelId: String, framework: Int): Boolean

    /** Returns JSON: {isAvailable, requiredSpace, availableSpace, hasWarning, recommendation} */
    @JvmStatic
    external fun nativeFileManagerCheckStorage(requiredBytes: Long): String?

    /** Returns JSON: {deviceTotal, deviceFree, modelsSize, cacheSize, tempSize, totalAppSize} */
    @JvmStatic
    external fun nativeFileManagerGetStorageInfo(): String?

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
    // LLM THINKING (rac_llm_thinking.h)
    // ========================================================================
    //
    // v3-readiness Phase A8 / GAP 08 #6. Cross-SDK parity with Swift's
    // `CppBridge+LLMThinking.swift`. Previously missing from Kotlin per
    // the 3-agent audit; this block closes that gap.

    /** Split full text into (response, thinking) on the FIRST
     *  `<think>...</think>` block. Returns String[2]:
     *    [0] = response text (never null; empty when input is only a think block)
     *    [1] = thinking text, or null when no <think> block was found
     *  Returns null on error. */
    @JvmStatic external fun racLlmExtractThinking(text: String): Array<String?>?

    /** Remove ALL `<think>...</think>` blocks (plus trailing unclosed
     *  `<think>`). Returns the stripped remainder, or null on error. */
    @JvmStatic external fun racLlmStripThinking(text: String): String?

    /** Apportion `totalCompletionTokens` between thinking and response
     *  segments by character-length ratio. Returns int[2]:
     *    [0] = thinking tokens
     *    [1] = response tokens (0 + total when thinking is null/empty).
     *  Returns null on error. */
    @JvmStatic external fun racLlmSplitThinkingTokens(
        totalCompletionTokens: Int,
        responseText: String?,
        thinkingText: String?,
    ): IntArray?

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
    @JvmStatic external fun racSolutionStart(handle: Long): Int

    /** Request a graceful shutdown (non-blocking). Returns rac_result_t. */
    @JvmStatic external fun racSolutionStop(handle: Long): Int

    /** Force-cancel the graph. Returns rac_result_t. */
    @JvmStatic external fun racSolutionCancel(handle: Long): Int

    /** Feed one UTF-8 item into the root input edge. Returns rac_result_t. */
    @JvmStatic external fun racSolutionFeed(handle: Long, item: String): Int

    /** Close the root input edge (signal end-of-stream). Returns rac_result_t. */
    @JvmStatic external fun racSolutionCloseInput(handle: Long): Int

    /** Cancel, join, and destroy the solution. Always safe; null handle is a no-op. */
    @JvmStatic external fun racSolutionDestroy(handle: Long)

    // ========================================================================
    // EMBEDDINGS GENERATED-PROTO ABI (rac_embeddings_service.h)
    // ========================================================================

    @JvmStatic external fun racEmbeddingsCreate(modelId: String): Long

    @JvmStatic external fun racEmbeddingsCreateWithConfig(modelId: String, configJson: String?): Long

    @JvmStatic external fun racEmbeddingsEmbedBatchProto(handle: Long, requestProto: ByteArray): ByteArray?

    @JvmStatic external fun racEmbeddingsDestroy(handle: Long)

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
    // DIFFUSION GENERATED-PROTO ABI (rac_diffusion_service.h)
    // ========================================================================

    @JvmStatic external fun racDiffusionCreate(modelIdOrPath: String): Long

    @JvmStatic external fun racDiffusionInitialize(handle: Long, modelPath: String): Int

    /** Generate an image. Returns serialized DiffusionResult proto bytes, or null on error. */
    @JvmStatic external fun racDiffusionGenerateProto(handle: Long, optionsBytes: ByteArray): ByteArray?

    /** Generate an image with serialized DiffusionProgress callbacks. */
    @JvmStatic external fun racDiffusionGenerateWithProgressProto(
        handle: Long,
        optionsBytes: ByteArray,
        listener: NativeProtoProgressListener?,
    ): ByteArray?

    /** Cancel ongoing image generation. */
    @JvmStatic external fun racDiffusionCancelProto(handle: Long): Int

    @JvmStatic external fun racDiffusionDestroy(handle: Long)

    /** Get the service capability bitmask; no generated-proto getter exists yet. */
    @JvmStatic external fun racDiffusionGetCapabilitiesMask(handle: Long): Int

    // ========================================================================
    // LORA GENERATED-PROTO ABI (rac_lora_service.h)
    // ========================================================================

    @JvmStatic external fun racLoraLoadProto(llmHandle: Long, configProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraRemoveProto(llmHandle: Long, configProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraClearProto(llmHandle: Long): ByteArray?

    @JvmStatic external fun racLoraCompatibilityProto(llmHandle: Long, configProto: ByteArray): ByteArray?

    @JvmStatic external fun racLoraRegisterProto(entryProto: ByteArray): ByteArray?

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
    // LORA (rac/features/llm/rac_llm_lora.h) — Round 1 G-A7
    // ========================================================================
    //
    // Round 1 KOTLIN (G-A7): added external thunks for canonical LoRA
    // capability (RunAnywhere.lora.*). These wrap the per-handle LoRA
    // ops in rac_llm_component plus the registry in rac_lora_registry.

    /** Load a LoRA adapter. configBytes = serialized LoRAAdapterConfig proto. Returns rac_result_t. */
    @JvmStatic external fun racLoraLoad(configBytes: ByteArray): Int

    /** Remove a LoRA adapter by id. Returns rac_result_t. */
    @JvmStatic external fun racLoraRemove(adapterId: String): Int

    /** Clear all loaded LoRA adapters. */
    @JvmStatic external fun racLoraClear(): Int

    /** Snapshot of currently loaded adapters as JSON-encoded LoRAAdapterInfo[]. Null on error. */
    @JvmStatic external fun racLoraGetLoaded(): String?

    /** Check compatibility. Returns serialized LoraCompatibilityResult proto bytes. */
    @JvmStatic external fun racLoraCheckCompatibility(adapterId: String, modelId: String): ByteArray?

    // ========================================================================
    // NATIVE HTTP DOWNLOAD (rac/infrastructure/http/rac_http_download.h)
    // ========================================================================
    //
    // v2 close-out Phase H. Replaces the 1.3 KLOC HttpURLConnection path
    // that used to live in CppBridgeDownload.kt. The native runner
    // streams chunks to disk through libcurl, updates SHA-256 inline,
    // and forwards progress to the Kotlin listener via JNI on every
    // chunk. Returning `false` from the listener's onProgress cancels
    // the transfer.
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
    // @return RAC_HTTP_DL_* code (see CppBridgeDownload.DownloadError for
    //         the byte-for-byte mapping).
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
    // native code routes through Kotlin's `OkHttpTransport` instead of
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

    /** Clear all auth state including secure storage (if wired). */
    @JvmStatic external fun racAuthClear()

    /** Restore tokens from secure storage. Returns 0 on success, -1 if
     *  not found or storage callbacks not wired. */
    @JvmStatic external fun racAuthLoadStoredTokens(): Int

    /** Persist current tokens to secure storage. Returns 0 on success. */
    @JvmStatic external fun racAuthSaveTokens(): Int

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
    // Round 1 KOTLIN: JNI thunk declaration for extractStructuredOutput.
    // [CPP-BLOCKED]: the C++ side (rac_structured_output_extract_json) is not
    // yet wired in runanywhere_commons_jni.cpp. The declaration lives here so
    // the public SDK method calls the thunk naturally; callers will see
    // UnsatisfiedLinkError at runtime until the C++ track lands.
    // ========================================================================

    /** Extract a JSON object from [text], optionally validated against [schemaJson].
     *  Returns serialized StructuredOutputResult proto bytes, or null on failure. */
    @JvmStatic external fun racStructuredOutputExtractJson(text: String, schemaJson: String?): ByteArray?

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
