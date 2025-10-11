package com.runanywhere.sdk.platform

/**
 * Platform-specific checksum calculation APIs.
 * ALL business logic stays in commonMain - only file I/O is platform-specific.
 *
 * Matches Swift SDK's checksum verification approach.
 */

/**
 * Calculate SHA-256 checksum of a file.
 * Platform-specific implementation required for file I/O.
 *
 * @param filePath Absolute path to file
 * @return Hex string of SHA-256 hash (lowercase)
 */
expect suspend fun calculateSHA256(filePath: String): String

/**
 * Calculate MD5 checksum of a file.
 * Platform-specific implementation required for file I/O.
 *
 * @param filePath Absolute path to file
 * @return Hex string of MD5 hash (lowercase)
 */
expect suspend fun calculateMD5(filePath: String): String

/**
 * Calculate checksum of byte array (common implementation).
 * Business logic in commonMain.
 */
expect fun calculateSHA256Bytes(data: ByteArray): String

/**
 * Calculate MD5 of byte array (common implementation).
 * Business logic in commonMain.
 */
expect fun calculateMD5Bytes(data: ByteArray): String
