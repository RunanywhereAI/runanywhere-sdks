/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelRegistry extension for CppBridge.
 * Provides direct access to the C++ model registry.
 *
 * Mirrors iOS CppBridge+ModelRegistry.swift architecture:
 * - Uses the global C++ model registry directly via JNI
 * - NO Kotlin-side caching - everything is in C++
 * - Service providers in C++ look up models from this registry
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ModelInfo as ProtoModelInfo
import ai.runanywhere.proto.v1.ModelInfoList as ProtoModelInfoList
import ai.runanywhere.proto.v1.ModelQuery as ProtoModelQuery
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest as ProtoModelRegistryRefreshRequest
import ai.runanywhere.proto.v1.ModelRegistryRefreshResult as ProtoModelRegistryRefreshResult
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Model registry bridge that provides direct access to the C++ model registry.
 *
 * IMPORTANT: This does NOT maintain a Kotlin-side cache. All models are stored
 * in the C++ registry (rac_model_registry) so that C++ service providers can
 * find models when loading. This mirrors the Swift SDK architecture.
 *
 * Usage:
 * - Register models during SDK initialization via [registerModel]
 * - C++ backends will use these models when loading
 * - Download status is updated via [updateDownloadStatus]
 */
object CppBridgeModelRegistry {
    private const val TAG = "CppBridge/CppBridgeModelRegistry"

    /**
     * Model category constants matching C++ RAC_MODEL_CATEGORY_* values.
     */
    object ModelCategory {
        const val LANGUAGE = 0 // RAC_MODEL_CATEGORY_LANGUAGE
        const val SPEECH_RECOGNITION = 1 // RAC_MODEL_CATEGORY_SPEECH_RECOGNITION
        const val SPEECH_SYNTHESIS = 2 // RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS
        const val VISION = 3 // RAC_MODEL_CATEGORY_VISION
        const val IMAGE_GENERATION = 4 // RAC_MODEL_CATEGORY_IMAGE_GENERATION
        const val MULTIMODAL = 5 // RAC_MODEL_CATEGORY_MULTIMODAL
        const val AUDIO = 6 // RAC_MODEL_CATEGORY_AUDIO
        const val EMBEDDING = 7 // RAC_MODEL_CATEGORY_EMBEDDING
        const val VOICE_ACTIVITY_DETECTION = 8 // RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        const val UNKNOWN = 99 // RAC_MODEL_CATEGORY_UNKNOWN
    }

    /**
     * Model type constants (alias for category for backwards compatibility).
     */
    object ModelType {
        const val LLM = ModelCategory.LANGUAGE
        const val STT = ModelCategory.SPEECH_RECOGNITION
        const val TTS = ModelCategory.SPEECH_SYNTHESIS
        const val VAD = ModelCategory.VOICE_ACTIVITY_DETECTION
        const val EMBEDDING = ModelCategory.EMBEDDING
        const val UNKNOWN = ModelCategory.UNKNOWN

        /**
         * Get display name for a model type.
         */
        fun getName(type: Int): String =
            when (type) {
                LLM -> "LLM"
                STT -> "STT"
                TTS -> "TTS"
                VAD -> "VAD"
                EMBEDDING -> "EMBEDDING"
                else -> "UNKNOWN"
            }
    }

    /**
     * Model format constants matching C++ RAC_MODEL_FORMAT_* values.
     */
    object ModelFormat {
        const val ONNX = 0 // RAC_MODEL_FORMAT_ONNX
        const val ORT = 1 // RAC_MODEL_FORMAT_ORT
        const val GGUF = 2 // RAC_MODEL_FORMAT_GGUF
        const val BIN = 3 // RAC_MODEL_FORMAT_BIN
        const val COREML = 4 // RAC_MODEL_FORMAT_COREML
        const val QNN_CONTEXT = 5 // RAC_MODEL_FORMAT_QNN_CONTEXT
        const val UNKNOWN = 99 // RAC_MODEL_FORMAT_UNKNOWN
    }

    /**
     * Inference framework constants matching C++ RAC_FRAMEWORK_* values.
     * IMPORTANT: Must match rac_model_types.h exactly!
     */
    object Framework {
        const val ONNX = 0 // RAC_FRAMEWORK_ONNX
        const val LLAMACPP = 1 // RAC_FRAMEWORK_LLAMACPP
        const val FOUNDATION_MODELS = 2 // RAC_FRAMEWORK_FOUNDATION_MODELS
        const val SYSTEM_TTS = 3 // RAC_FRAMEWORK_SYSTEM_TTS
        const val FLUID_AUDIO = 4 // RAC_FRAMEWORK_FLUID_AUDIO
        const val BUILTIN = 5 // RAC_FRAMEWORK_BUILTIN
        const val NONE = 6 // RAC_FRAMEWORK_NONE
        const val MLX = 7 // RAC_FRAMEWORK_MLX
        const val COREML = 8 // RAC_FRAMEWORK_COREML
        const val WHISPERKIT_COREML = 9 // RAC_FRAMEWORK_WHISPERKIT_COREML
        const val METALRT = 10 // RAC_FRAMEWORK_METALRT
        const val GENIE = 11 // RAC_FRAMEWORK_GENIE
        const val SHERPA = 12 // RAC_FRAMEWORK_SHERPA (Sherpa-ONNX speech engine)
        const val UNKNOWN = 99 // RAC_FRAMEWORK_UNKNOWN
    }

    // ========================================================================
    // PUBLIC API - Mirrors Swift CppBridge.ModelRegistry
    // ========================================================================

    /**
     * Save model to C++ registry.
     *
     * This stores the model in the C++ registry so that C++ service providers
     * (like LlamaCPP) can find it when loading models.
     *
     * @param model The model info to save
     * @throws RuntimeException if save fails
     */
    fun save(model: ProtoModelInfo) {
        log(LogLevel.DEBUG, "Saving model to C++ registry: ${model.id} (framework=${model.framework})")

        val result = registerProto(model)
            ?: throw RuntimeException("Native model registry proto ABI unavailable")

        if (result != RunAnywhereBridge.RAC_SUCCESS) {
            log(LogLevel.ERROR, "Failed to save model: ${model.id}, error=$result")
            throw RuntimeException("Failed to save model to C++ registry: $result")
        }

        log(LogLevel.INFO, "Model saved to C++ registry: ${model.id}")
    }

    /**
     * Get model info from C++ registry.
     *
     * @param modelId The model ID
     * @return ModelInfo or null if not found
     */
    fun get(modelId: String): ProtoModelInfo? = getProto(modelId)

    /**
     * Get all models from C++ registry.
     *
     * @return List of all models
     */
    fun getAll(): List<ProtoModelInfo> = listProto()?.models.orEmpty()

    /**
     * Get downloaded models from C++ registry.
     *
     * @return List of downloaded models
     */
    fun getDownloaded(): List<ProtoModelInfo> = listDownloadedProto()?.models.orEmpty()

    /**
     * Query registered models using the generated ModelQuery proto.
     */
    fun query(query: ProtoModelQuery): ProtoModelInfoList =
        queryProto(query) ?: ProtoModelInfoList()

    /**
     * List downloaded models using the generated ModelInfoList proto result.
     */
    fun listDownloaded(): ProtoModelInfoList =
        listDownloadedProto() ?: ProtoModelInfoList()

    /**
     * Refresh registered models through the generated ModelRegistryRefresh proto ABI.
     */
    fun refresh(request: ProtoModelRegistryRefreshRequest): ProtoModelRegistryRefreshResult? =
        refreshProto(request)

    /**
     * Remove model from C++ registry.
     *
     * @param modelId The model ID
     * @return true if removed successfully
     */
    fun remove(modelId: String): Boolean {
        return removeProto(modelId) == RunAnywhereBridge.RAC_SUCCESS
    }

    /**
     * Update download status in C++ registry (in-memory only).
     *
     * @param modelId The model ID
     * @param localPath The local path (or null to clear download)
     * @return true if updated successfully
     */
    fun updateDownloadStatus(modelId: String, localPath: String?): Boolean {
        log(LogLevel.DEBUG, "Updating download status: $modelId -> ${localPath ?: "null"}")
        val current = getProto(modelId) ?: return false
        val updated =
            current.copy(
                local_path = localPath.orEmpty(),
                updated_at_unix_ms = System.currentTimeMillis(),
            )
        val protoResult = updateProto(updated)
        if (protoResult == RunAnywhereBridge.RAC_SUCCESS) {
            return true
        }
        if (protoResult != null) {
            log(LogLevel.WARN, "Proto download status update failed for $modelId: $protoResult")
        }
        return false
    }

    // ========================================================================
    // PROTO ABI
    // ========================================================================

    private fun registerProto(model: ProtoModelInfo): Int? =
        callProtoInt("registerProto") {
            RunAnywhereBridge.racModelRegistryRegisterProto(ProtoModelInfo.ADAPTER.encode(model))
        }

    private fun updateProto(model: ProtoModelInfo): Int? =
        callProtoInt("updateProto") {
            RunAnywhereBridge.racModelRegistryUpdateProto(ProtoModelInfo.ADAPTER.encode(model))
        }

    private fun getProto(modelId: String): ProtoModelInfo? {
        val bytes =
            callProtoBytes("getProto") {
                RunAnywhereBridge.racModelRegistryGetProto(modelId)
            } ?: return null

        return decodeProtoModel(bytes)
    }

    private fun listProto(): ProtoModelInfoList? {
        val bytes =
            callProtoBytes("listProto") {
                RunAnywhereBridge.racModelRegistryListProto()
            } ?: return null

        return try {
            ProtoModelInfoList.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode ModelInfoList proto: ${e.message}")
            null
        }
    }

    private fun queryProto(query: ProtoModelQuery): ProtoModelInfoList? {
        val bytes =
            callProtoBytes("queryProto") {
                RunAnywhereBridge.racModelRegistryQueryProto(ProtoModelQuery.ADAPTER.encode(query))
            } ?: return null

        return decodeModelInfoList(bytes, "ModelQuery")
    }

    private fun listDownloadedProto(): ProtoModelInfoList? {
        val bytes =
            callProtoBytes("listDownloadedProto") {
                RunAnywhereBridge.racModelRegistryListDownloadedProto()
            } ?: return null

        return decodeModelInfoList(bytes, "downloaded ModelInfoList")
    }

    private fun refreshProto(request: ProtoModelRegistryRefreshRequest): ProtoModelRegistryRefreshResult? {
        val bytes =
            callProtoBytes("refreshProto") {
                RunAnywhereBridge.racModelRegistryRefreshProto(
                    ProtoModelRegistryRefreshRequest.ADAPTER.encode(request),
                )
            } ?: return null

        return try {
            ProtoModelRegistryRefreshResult.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode ModelRegistryRefreshResult proto: ${e.message}")
            null
        }
    }

    private fun removeProto(modelId: String): Int? =
        callProtoInt("removeProto") {
            RunAnywhereBridge.racModelRegistryRemoveProto(modelId)
        }

    private fun decodeProtoModel(bytes: ByteArray): ProtoModelInfo? =
        try {
            ProtoModelInfo.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode ModelInfo proto: ${e.message}")
            null
        }

    private fun decodeModelInfoList(bytes: ByteArray, label: String): ProtoModelInfoList? =
        try {
            ProtoModelInfoList.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode $label proto: ${e.message}")
            null
        }

    private fun callProtoInt(operation: String, block: () -> Int): Int? =
        try {
            block()
        } catch (e: UnsatisfiedLinkError) {
            log(LogLevel.DEBUG, "Native registry proto ABI unavailable for $operation: ${e.message}")
            null
        }

    private fun callProtoBytes(operation: String, block: () -> ByteArray?): ByteArray? =
        try {
            block()
        } catch (e: UnsatisfiedLinkError) {
            log(LogLevel.DEBUG, "Native registry proto ABI unavailable for $operation: ${e.message}")
            null
        }

    // ========================================================================
    // LOGGING
    // ========================================================================

    private enum class LogLevel { DEBUG, INFO, WARN, ERROR }

    private fun log(level: LogLevel, message: String) {
        val adapterLevel =
            when (level) {
                LogLevel.DEBUG -> CppBridgePlatformAdapter.LogLevel.DEBUG
                LogLevel.INFO -> CppBridgePlatformAdapter.LogLevel.INFO
                LogLevel.WARN -> CppBridgePlatformAdapter.LogLevel.WARN
                LogLevel.ERROR -> CppBridgePlatformAdapter.LogLevel.ERROR
            }
        CppBridgePlatformAdapter.logCallback(adapterLevel, TAG, message)
    }
}
