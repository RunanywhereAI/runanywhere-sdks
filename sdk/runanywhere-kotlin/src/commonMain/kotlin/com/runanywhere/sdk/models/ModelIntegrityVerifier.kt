package com.runanywhere.sdk.models

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.storage.FileSystem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Verification result for model integrity checks
 */
sealed class VerificationResult {
    object Success : VerificationResult()
    data class Failed(val reason: String) : VerificationResult()
    data class Unsupported(val reason: String) : VerificationResult()
}

/**
 * Model integrity verifier for checking downloaded models against checksums
 * EXACT copy of iOS model verification patterns
 */
class ModelIntegrityVerifier(
    private val fileSystem: FileSystem
) {
    private val logger = SDKLogger("ModelIntegrityVerifier")

    /**
     * Verify a downloaded model's integrity against its expected checksums
     * @param modelInfo The model information containing checksums
     * @param filePath The path to the downloaded file
     * @return Verification result
     */
    suspend fun verifyModel(modelInfo: ModelInfo, filePath: String): VerificationResult = withContext(Dispatchers.IO) {
        logger.info("🔍 Verifying integrity of model: ${modelInfo.id}")

        // Check if file exists
        if (!fileSystem.exists(filePath)) {
            return@withContext VerificationResult.Failed("File does not exist: $filePath")
        }

        // Check file size if available
        modelInfo.downloadSize?.let { expectedSize ->
            val actualSize = fileSystem.fileSize(filePath)
            if (actualSize != expectedSize) {
                return@withContext VerificationResult.Failed(
                    "File size mismatch. Expected: $expectedSize bytes, Actual: $actualSize bytes"
                )
            }
            logger.info("✅ File size verification passed: $actualSize bytes")
        }

        // Verify SHA256 checksum if available
        modelInfo.sha256Checksum?.let { expectedSha256 ->
            logger.info("🔐 Verifying SHA256 checksum...")
            val actualSha256 = calculateSHA256(filePath)
            if (actualSha256 != expectedSha256.lowercase()) {
                return@withContext VerificationResult.Failed(
                    "SHA256 checksum mismatch. Expected: $expectedSha256, Actual: $actualSha256"
                )
            }
            logger.info("✅ SHA256 verification passed")
            return@withContext VerificationResult.Success
        }

        // Verify MD5 checksum if available (fallback)
        modelInfo.md5Checksum?.let { expectedMd5 ->
            logger.info("🔐 Verifying MD5 checksum...")
            val actualMd5 = calculateMD5(filePath)
            if (actualMd5 != expectedMd5.lowercase()) {
                return@withContext VerificationResult.Failed(
                    "MD5 checksum mismatch. Expected: $expectedMd5, Actual: $actualMd5"
                )
            }
            logger.info("✅ MD5 verification passed")
            return@withContext VerificationResult.Success
        }

        // No checksum available - log warning but allow
        logger.warn("⚠️ No checksums available for verification of model: ${modelInfo.id}")
        return@withContext VerificationResult.Unsupported("No checksums provided")
    }

    /**
     * Calculate SHA256 checksum of a file
     * Uses platform-specific implementation
     */
    private suspend fun calculateSHA256(filePath: String): String {
        logger.debug("Calculating SHA256 for: $filePath")
        return calculatePlatformChecksum(filePath, "SHA-256", fileSystem)
    }

    /**
     * Calculate MD5 checksum of a file
     * Uses platform-specific implementation
     */
    private suspend fun calculateMD5(filePath: String): String {
        logger.debug("Calculating MD5 for: $filePath")
        return calculatePlatformChecksum(filePath, "MD5", fileSystem)
    }

    /**
     * Quick integrity check - just verify file exists and size matches
     * @param modelInfo The model information
     * @param filePath The path to the downloaded file
     * @return True if basic checks pass
     */
    suspend fun quickIntegrityCheck(modelInfo: ModelInfo, filePath: String): Boolean = withContext(Dispatchers.IO) {
        if (!fileSystem.exists(filePath)) {
            logger.warn("❌ Quick check failed: File does not exist: $filePath")
            return@withContext false
        }

        modelInfo.downloadSize?.let { expectedSize ->
            val actualSize = fileSystem.fileSize(filePath)
            if (actualSize != expectedSize) {
                logger.warn("❌ Quick check failed: Size mismatch for ${modelInfo.id}. Expected: $expectedSize, Actual: $actualSize")
                return@withContext false
            }
        }

        logger.info("✅ Quick integrity check passed for: ${modelInfo.id}")
        return@withContext true
    }
}

/**
 * Platform-specific checksum calculation - to be implemented per platform
 */
expect suspend fun calculatePlatformChecksum(filePath: String, algorithm: String, fileSystem: FileSystem): String