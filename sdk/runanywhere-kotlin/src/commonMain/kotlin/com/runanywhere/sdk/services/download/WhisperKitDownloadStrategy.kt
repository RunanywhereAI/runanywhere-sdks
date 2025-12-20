package com.runanywhere.sdk.services.download

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.storage.FileSystem
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.utils.io.*
import kotlinx.coroutines.*

/**
 * WhisperKit-specific download strategy for multi-file models
 * Matches iOS WhisperKitDownloadStrategy exactly
 */
class WhisperKitDownloadStrategy(
    private val httpClient: HttpClient = HttpClient(),
    private val fileSystem: FileSystem = ServiceContainer.shared.fileSystem,
) : DownloadStrategy {
    private val logger = SDKLogger("WhisperKitDownloadStrategy")

    companion object {
        // WhisperKit model file structure
        private val WHISPERKIT_MODEL_FILES =
            listOf(
                "AudioEncoder.mlmodelc",
                "TextDecoder.mlmodelc",
                "MelSpectrogram.mlmodelc",
                "LogitFilter.mlmodelc",
                "AudioEncoder.mlpackage",
                "TextDecoder.mlpackage",
            )

        // Base URL for WhisperKit models on HuggingFace
        private const val WHISPERKIT_BASE_URL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main"
    }

    /**
     * Check if this strategy can handle the model
     */
    override fun canHandle(model: ModelInfo): Boolean =
        model.preferredFramework == InferenceFramework.WHISPER_KIT ||
            (
                model.format == ModelFormat.MLMODEL &&
                    model.category == ModelCategory.SPEECH_RECOGNITION
            )

    /**
     * Download WhisperKit model with multiple files
     */
    override suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((Double) -> Unit)?,
    ): String {
        logger.info("Starting WhisperKit download for model: ${model.id}")

        // Create model directory
        fileSystem.createDirectory(destinationFolder)

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
                val response = httpClient.get(fileUrl)

                if (response.status.isSuccess()) {
                    val contentLength = response.contentLength() ?: 0L
                    val channel = response.bodyAsChannel()
                    val buffer = ByteArray(8192)
                    var bytesDownloaded = 0L
                    val fileData = mutableListOf<ByteArray>()

                    while (!channel.isClosedForRead) {
                        val bytesRead = channel.readAvailable(buffer, 0, buffer.size)
                        if (bytesRead <= 0) break

                        val chunkData = ByteArray(bytesRead)
                        buffer.copyInto(chunkData, 0, 0, bytesRead)
                        fileData.add(chunkData)
                        bytesDownloaded += bytesRead

                        // Calculate overall progress across all files
                        val fileProgress =
                            if (contentLength > 0) {
                                bytesDownloaded.toDouble() / contentLength
                            } else {
                                0.0
                            }

                        overallProgress = (downloadedFiles + fileProgress) / totalFiles
                        progressHandler?.invoke(overallProgress)
                    }

                    // Write all data to file
                    val allData = fileData.fold(ByteArray(0)) { acc, chunk -> acc + chunk }
                    fileSystem.writeBytes(destinationPath, allData)
                } else if (response.status == HttpStatusCode.NotFound) {
                    // 404 is expected for some files, just log and continue
                    logger.debug("File not found (expected for some models): $file")
                } else {
                    throw Exception("Failed to download $file: HTTP ${response.status.value}")
                }

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
        val hasAudioEncoder =
            fileSystem.exists("$destinationFolder/AudioEncoder.mlmodelc") ||
                fileSystem.exists("$destinationFolder/AudioEncoder.mlpackage")
        val hasTextDecoder =
            fileSystem.exists("$destinationFolder/TextDecoder.mlmodelc") ||
                fileSystem.exists("$destinationFolder/TextDecoder.mlpackage")

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
    private fun mapModelIdToWhisperKitVariant(modelId: String): String =
        when (modelId) {
            "whisperkit-tiny" -> "openai_whisper-tiny"
            "whisperkit-base" -> "openai_whisper-base"
            "whisperkit-small" -> "openai_whisper-small"
            "whisperkit-medium" -> "openai_whisper-medium"
            "whisperkit-large" -> "openai_whisper-large-v3"
            else -> "openai_whisper-base" // Default to base
        }
}
