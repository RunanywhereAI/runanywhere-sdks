package com.runanywhere.ai.models.data

import com.runanywhere.sdk.models.ModelInfo as SdkModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.utils.SimpleInstant

/**
 * UI wrapper around SDK's ModelInfo to add app-specific UI state
 * Uses the SDK's ModelInfo as the source of truth for model data
 */
data class ModelUiState(
    val modelInfo: SdkModelInfo,
    val state: ModelState = ModelState.NOT_AVAILABLE,
    val downloadProgress: Float = 0f,
    // App-specific fields not in SDK
    val thinkingTags: List<String> = emptyList(),
    val downloadedAt: SimpleInstant? = null
) {
    // Delegate common properties to SDK ModelInfo for convenience
    val id: String get() = modelInfo.id
    val name: String get() = modelInfo.name
    val category get() = modelInfo.category
    val format get() = modelInfo.format
    val downloadURL: String? get() = modelInfo.downloadURL
    val localPath: String? get() = modelInfo.localPath
    val downloadSize: Long? get() = modelInfo.downloadSize
    val memoryRequired: Long? get() = modelInfo.memoryRequired
    val compatibleFrameworks get() = modelInfo.compatibleFrameworks
    val preferredFramework get() = modelInfo.preferredFramework
    val contextLength: Int? get() = modelInfo.contextLength
    val supportsThinking: Boolean get() = modelInfo.supportsThinking
    val metadata: ModelInfoMetadata? get() = modelInfo.metadata
    val lastUsed get() = modelInfo.lastUsed

    // Computed properties
    val isDownloaded: Boolean get() = modelInfo.isDownloaded
    val canDownload: Boolean get() = downloadURL != null && !isDownloaded
    val isBuiltIn: Boolean get() = preferredFramework == LLMFramework.FOUNDATION_MODELS

    val displaySize: String
        get() = downloadSize?.let { formatBytes(it) } ?: "Unknown"

    val displayMemory: String
        get() = memoryRequired?.let { formatBytes(it) } ?: "Unknown"

    fun updateState(): ModelState {
        return when {
            isBuiltIn -> ModelState.BUILT_IN
            downloadURL == null -> ModelState.NOT_AVAILABLE
            localPath == null -> ModelState.AVAILABLE
            else -> ModelState.DOWNLOADED
        }
    }

    companion object {
        fun formatBytes(bytes: Long): String {
            return when {
                bytes < 1024 -> "$bytes B"
                bytes < 1024 * 1024 -> String.format("%.1f KB", bytes / 1024.0)
                bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
                else -> String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024))
            }
        }

        /**
         * Create ModelUiState from SDK ModelInfo
         */
        fun fromSdkModel(sdkModel: SdkModelInfo): ModelUiState {
            return ModelUiState(
                modelInfo = sdkModel,
                state = determineInitialState(sdkModel),
                downloadProgress = 0f,
                thinkingTags = emptyList(), // Could be extracted from metadata.tags if needed
                downloadedAt = if (sdkModel.localPath != null) SimpleInstant.now() else null
            )
        }

        private fun determineInitialState(sdkModel: SdkModelInfo): ModelState {
            return when {
                sdkModel.preferredFramework == LLMFramework.FOUNDATION_MODELS -> ModelState.BUILT_IN
                sdkModel.localPath != null -> ModelState.DOWNLOADED
                sdkModel.downloadURL != null -> ModelState.AVAILABLE
                else -> ModelState.NOT_AVAILABLE
            }
        }
    }
}

// Type alias for backward compatibility during migration
typealias ModelInfo = ModelUiState
