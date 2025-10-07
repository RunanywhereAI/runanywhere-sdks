package com.runanywhere.ai.models.data

import java.util.Date

data class ModelInfo(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val format: ModelFormat,
    val downloadURL: String? = null,
    var localPath: String? = null,
    val downloadSize: Long? = null,
    val memoryRequired: Long? = null,
    val compatibleFrameworks: List<LLMFramework>,
    val preferredFramework: LLMFramework? = null,
    val contextLength: Int? = null,
    val supportsThinking: Boolean = false,
    val thinkingTags: List<String> = emptyList(),
    val metadata: ModelMetadata? = null,
    var state: ModelState = ModelState.NOT_AVAILABLE,
    var downloadProgress: Float = 0f,
    var lastUsed: Date? = null,
    var downloadedAt: Date? = null
) {
    val isDownloaded: Boolean
        get() = localPath != null

    val canDownload: Boolean
        get() = downloadURL != null && !isDownloaded

    val isBuiltIn: Boolean
        get() = preferredFramework == LLMFramework.FOUNDATION_MODELS

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
    }
}

data class ModelMetadata(
    val description: String? = null,
    val author: String? = null,
    val version: String? = null,
    val license: String? = null,
    val tags: List<String> = emptyList(),
    val capabilities: List<String> = emptyList(),
    val limitations: List<String> = emptyList(),
    val baseModel: String? = null,
    val quantization: String? = null
)
