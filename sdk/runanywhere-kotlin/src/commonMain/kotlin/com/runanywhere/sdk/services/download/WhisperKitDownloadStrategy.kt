package com.runanywhere.sdk.services.download

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * WhisperKit-specific download strategy for multi-file models
 * Matches iOS WhisperKitDownloadStrategy exactly
 */
class WhisperKitDownloadStrategy(
    private val networkService: NetworkService,
    private val fileManager: FileManager
) : DownloadStrategy {

    private val logger = SDKLogger("WhisperKitDownloadStrategy")

    companion object {
        // WhisperKit model file structure
        private val WHISPERKIT_MODEL_FILES = listOf(
            "AudioEncoder.mlmodelc",
            "TextDecoder.mlmodelc",
            "MelSpectrogram.mlmodelc",
            "LogitFilter.mlmodelc",
            "AudioEncoder.mlpackage",
            "TextDecoder.mlpackage"
        )

        // Base URL for WhisperKit models on HuggingFace
        private const val WHISPERKIT_BASE_URL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main"
    }

    /**
     * Check if this strategy can handle the model
     */
    override fun canHandle(model: ModelInfo): Boolean {
        return model.preferredFramework == LLMFramework.WHISPER_KIT ||
               (model.format == ModelFormat.MLMODEL &&
                model.category == com.runanywhere.sdk.models.enums.ModelCategory.SPEECH_RECOGNITION)
    }

    /**
     * Download WhisperKit model with multiple files
     */
    override suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((Double) -> Unit)?
    ): String {
        logger.info("Starting WhisperKit download for model: ${model.id}")

        // Create model directory
        fileManager.createDirectory(destinationFolder)

        // Map model ID to WhisperKit variant
        val whisperKitVariant = mapModelIdToWhisperKitVariant(model.id)

        var downloadedFiles = 0
        val totalFiles = WHISPERKIT_MODEL_FILES.size
        var overallProgress = 0.0

        // Download each model file
        for (file in WHISPERKIT_MODEL_FILES) {
            val fileUrl = "$WHISPERKIT_BASE_URL/$whisperKitVariant/$file"
            val destinationPath = "$destinationFolder/$file"

            logger.debug("Downloading WhisperKit file: $file")

            try {
                // Download with progress tracking for this file
                networkService.downloadFile(
                    url = fileUrl,
                    destinationPath = destinationPath,
                    progressCallback = { bytesDownloaded, totalBytes ->
                        // Calculate overall progress across all files
                        val fileProgress = if (totalBytes > 0) {
                            bytesDownloaded.toDouble() / totalBytes
                        } else 0.0

                        overallProgress = (downloadedFiles + fileProgress) / totalFiles
                        progressHandler?.invoke(overallProgress)
                    }
                )

                downloadedFiles++
                logger.debug("Successfully downloaded: $file ($downloadedFiles/$totalFiles)")

            } catch (e: Exception) {
                // Some files might not exist (404) - continue with others
                logger.warn("Failed to download $file: ${e.message}")

                // If it's a critical file (.mlmodelc), fail the download
                if (file.endsWith(".mlmodelc")) {
                    throw Exception("Failed to download critical WhisperKit file: $file")
                }
            }
        }

        // Verify at least the core files were downloaded
        val hasAudioEncoder = fileManager.fileExists("$destinationFolder/AudioEncoder.mlmodelc") ||
                             fileManager.fileExists("$destinationFolder/AudioEncoder.mlpackage")
        val hasTextDecoder = fileManager.fileExists("$destinationFolder/TextDecoder.mlmodelc") ||
                            fileManager.fileExists("$destinationFolder/TextDecoder.mlpackage")

        if (!hasAudioEncoder || !hasTextDecoder) {
            throw Exception("Failed to download required WhisperKit model files")
        }

        // Update progress to 100%
        progressHandler?.invoke(1.0)

        logger.info("WhisperKit model downloaded successfully to: $destinationFolder")
        return destinationFolder
    }

    /**
     * Map model ID to WhisperKit variant name
     */
    private fun mapModelIdToWhisperKitVariant(modelId: String): String {
        return when (modelId) {
            "whisperkit-tiny" -> "openai_whisper-tiny"
            "whisperkit-base" -> "openai_whisper-base"
            "whisperkit-small" -> "openai_whisper-small"
            "whisperkit-medium" -> "openai_whisper-medium"
            "whisperkit-large" -> "openai_whisper-large-v3"
            else -> "openai_whisper-base" // Default to base
        }
    }
}
