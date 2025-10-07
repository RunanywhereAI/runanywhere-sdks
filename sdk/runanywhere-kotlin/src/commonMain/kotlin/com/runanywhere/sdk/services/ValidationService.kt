package com.runanywhere.sdk.services

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.storage.FileSystem

/**
 * Common implementation of ValidationService for model validation
 * Provides model file validation, integrity checks, and format verification
 */
class ValidationService(
    private val fileSystem: FileSystem
) {
    private val logger = SDKLogger("ValidationService")

    companion object {
        private val SUPPORTED_EXTENSIONS = setOf("gguf", "bin", "mlmodel")
        private val WHISPER_MODEL_SIGNATURES = setOf(
            "whisper", "openai_whisper", "whisperkit"
        )
    }

    /**
     * Validate a downloaded model file
     */
    suspend fun validateModel(model: ModelInfo, filePath: String): ValidationResult {
        try {
            logger.info("Validating model ${model.id} at $filePath")

            if (!fileSystem.exists(filePath)) {
                return ValidationResult.Invalid("File does not exist: $filePath")
            }

            // Check file size
            val fileSize = fileSystem.fileSize(filePath)
            if (fileSize == 0L) {
                return ValidationResult.Invalid("File is empty")
            }

            // Check file size matches expected (with some tolerance)
            val expectedSize = model.downloadSize
            if (expectedSize != null && expectedSize > 0) {
                val sizeDifference = kotlin.math.abs(fileSize - expectedSize)
                val tolerance = expectedSize * 0.01 // 1% tolerance

                if (sizeDifference > tolerance) {
                    logger.warn("File size mismatch: got $fileSize, expected $expectedSize")
                    return ValidationResult.Invalid("File size mismatch: got $fileSize bytes, expected $expectedSize bytes")
                }
            }

            // Check file extension
            val extension = filePath.substringAfterLast('.').lowercase()
            if (!SUPPORTED_EXTENSIONS.contains(extension)) {
                return ValidationResult.Invalid("Unsupported file extension: $extension")
            }

            // Check if it's a valid model file based on content
            val isValidFormat = when (extension) {
                "gguf" -> validateGGUFFile(filePath)
                "mlmodel" -> validateMLModelFile(filePath)
                "bin" -> validateBinaryFile(filePath)
                else -> true // Default to valid for unknown extensions
            }

            if (!isValidFormat) {
                return ValidationResult.Invalid("Invalid file format for extension: $extension")
            }

            // Additional validation for Whisper models
            if (isWhisperModel(model)) {
                val whisperValidation = validateWhisperModel(filePath)
                if (!whisperValidation.isValid) {
                    return whisperValidation
                }
            }

            logger.info("Model validation successful for ${model.id}")
            return ValidationResult.Valid(filePath)

        } catch (e: Exception) {
            logger.error("Error during model validation", e)
            return ValidationResult.Invalid("Validation failed: ${e.message}")
        }
    }

    /**
     * Validate GGUF file format
     */
    private suspend fun validateGGUFFile(filePath: String): Boolean {
        return try {
            val header = fileSystem.readBytes(filePath).take(4).toByteArray()

            if (header.size != 4) {
                logger.warn("GGUF file too small to have valid header")
                return false
            }

            // Check GGUF magic number
            val magic = header.decodeToString()
            val isValid = magic == "GGUF"

            if (!isValid) {
                logger.warn("Invalid GGUF magic number: $magic")
            }

            isValid
        } catch (e: Exception) {
            logger.error("Error validating GGUF file", e)
            false
        }
    }

    /**
     * Validate ML Model file format (Core ML)
     */
    private suspend fun validateMLModelFile(filePath: String): Boolean {
        return try {
            // For Core ML models, check if it's a directory with required files
            if (fileSystem.isDirectory(filePath)) {
                val requiredFiles = listOf("model.mlmodel", "metadata.json")
                requiredFiles.all { fileName ->
                    fileSystem.exists("$filePath/$fileName")
                }
            } else {
                // Single file ML model
                fileSystem.fileSize(filePath) > 0
            }
        } catch (e: Exception) {
            logger.error("Error validating MLModel file", e)
            false
        }
    }

    /**
     * Validate generic binary file
     */
    private suspend fun validateBinaryFile(filePath: String): Boolean {
        return try {
            // Basic validation - file exists and has content
            fileSystem.exists(filePath) && fileSystem.fileSize(filePath) > 0
        } catch (e: Exception) {
            logger.error("Error validating binary file", e)
            false
        }
    }

    /**
     * Check if model is a Whisper model
     */
    private fun isWhisperModel(model: ModelInfo): Boolean {
        val modelName = model.name.lowercase()
        val modelId = model.id.lowercase()

        return WHISPER_MODEL_SIGNATURES.any { signature ->
            modelName.contains(signature) || modelId.contains(signature)
        }
    }

    /**
     * Validate Whisper model specific requirements
     */
    private suspend fun validateWhisperModel(filePath: String): ValidationResult {
        return try {
            // For Whisper models, ensure minimum size (tiny model is ~39MB)
            val minSize = 10 * 1024 * 1024 // 10MB minimum
            val fileSize = fileSystem.fileSize(filePath)

            if (fileSize < minSize) {
                ValidationResult.Invalid("Whisper model too small: $fileSize bytes")
            } else {
                ValidationResult.Valid(filePath)
            }
        } catch (e: Exception) {
            ValidationResult.Invalid("Whisper validation failed: ${e.message}")
        }
    }

    /**
     * Calculate MD5 checksum for a file
     */
    suspend fun calculateChecksum(filePath: String): String {
        return try {
            val data = fileSystem.readBytes(filePath)
            calculateMD5(data)
        } catch (e: Exception) {
            logger.error("Error calculating checksum for $filePath", e)
            throw e
        }
    }

    /**
     * Validate checksum if provided
     */
    suspend fun validateChecksum(filePath: String, expectedChecksum: String?): Boolean {
        if (expectedChecksum.isNullOrBlank()) {
            logger.info("No checksum provided, skipping validation")
            return true
        }

        return try {
            val actualChecksum = calculateChecksum(filePath)
            val isValid = actualChecksum.equals(expectedChecksum, ignoreCase = true)

            if (isValid) {
                logger.info("Checksum validation passed")
            } else {
                logger.warn("Checksum validation failed: expected $expectedChecksum, got $actualChecksum")
            }

            isValid

        } catch (e: Exception) {
            logger.error("Error during checksum validation", e)
            false
        }
    }

    /**
     * Validation result sealed class
     */
    sealed class ValidationResult {
        abstract val isValid: Boolean

        data class Valid(val filePath: String) : ValidationResult() {
            override val isValid: Boolean = true
        }

        data class Invalid(val reason: String) : ValidationResult() {
            override val isValid: Boolean = false
        }
    }
}

/**
 * Platform-specific MD5 calculation
 * Each platform provides its own implementation
 */
expect fun calculateMD5(data: ByteArray): String
