package com.runanywhere.sdk.services

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import java.io.File
import java.security.MessageDigest

/**
 * JVM implementation of ValidationService for model validation
 * Provides model file validation, integrity checks, and format verification
 */
class ValidationService {
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

            val file = File(filePath)
            if (!file.exists()) {
                return ValidationResult.Invalid("File does not exist: $filePath")
            }

            // Check file size
            val fileSize = file.length()
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
            val extension = file.extension.lowercase()
            if (!SUPPORTED_EXTENSIONS.contains(extension)) {
                return ValidationResult.Invalid("Unsupported file extension: $extension")
            }

            // Check if it's a valid model file based on content
            val isValidFormat = when (extension) {
                "gguf" -> validateGGUFFile(file)
                "mlmodel" -> validateMLModelFile(file)
                "bin" -> validateBinaryFile(file)
                else -> true // Default to valid for unknown extensions
            }

            if (!isValidFormat) {
                return ValidationResult.Invalid("Invalid file format for extension: $extension")
            }

            // Additional validation for Whisper models
            if (isWhisperModel(model)) {
                val whisperValidation = validateWhisperModel(file)
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
    private fun validateGGUFFile(file: File): Boolean {
        return try {
            file.inputStream().use { stream ->
                val header = ByteArray(4)
                val bytesRead = stream.read(header)

                if (bytesRead != 4) {
                    logger.warn("GGUF file too small to have valid header")
                    return false
                }

                // Check GGUF magic number
                val magic = String(header, Charsets.US_ASCII)
                val isValid = magic == "GGUF"

                if (!isValid) {
                    logger.warn("Invalid GGUF magic number: $magic")
                }

                isValid
            }
        } catch (e: Exception) {
            logger.error("Error validating GGUF file", e)
            false
        }
    }

    /**
     * Validate ML Model file format (Core ML)
     */
    private fun validateMLModelFile(file: File): Boolean {
        return try {
            // For Core ML models, check if it's a directory with required files
            if (file.isDirectory) {
                val requiredFiles = listOf("model.mlmodel", "metadata.json")
                requiredFiles.all { fileName ->
                    File(file, fileName).exists()
                }
            } else {
                // Single file ML model
                file.length() > 0
            }
        } catch (e: Exception) {
            logger.error("Error validating MLModel file", e)
            false
        }
    }

    /**
     * Validate generic binary file
     */
    private fun validateBinaryFile(file: File): Boolean {
        return try {
            // Basic validation - file exists and has content
            file.exists() && file.length() > 0
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
    private fun validateWhisperModel(file: File): ValidationResult {
        return try {
            // For Whisper models, ensure minimum size (tiny model is ~39MB)
            val minSize = 10 * 1024 * 1024 // 10MB minimum
            if (file.length() < minSize) {
                ValidationResult.Invalid("Whisper model too small: ${file.length()} bytes")
            } else {
                ValidationResult.Valid(file.absolutePath)
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
            val file = File(filePath)
            val digest = MessageDigest.getInstance("MD5")

            file.inputStream().use { inputStream ->
                val buffer = ByteArray(8192)
                var bytesRead = 0

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            }

            digest.digest().joinToString("") { "%02x".format(it) }

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
