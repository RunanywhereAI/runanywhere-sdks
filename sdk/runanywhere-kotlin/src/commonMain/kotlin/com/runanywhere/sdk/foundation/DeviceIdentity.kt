package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.security.SecureStorage
import com.runanywhere.sdk.security.SecureStorageFactory
import kotlinx.coroutines.runBlocking
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Simple utility for device identity management
 * Provides persistent UUID that survives app reinstalls
 * Matches iOS DeviceIdentity exactly
 */
object DeviceIdentity {

    private val logger = SDKLogger("DeviceIdentity")
    private val secureStorage: SecureStorage by lazy { SecureStorageFactory.create() }

    private const val DEVICE_UUID_KEY = "com.runanywhere.sdk.device.uuid"
    private const val DEVICE_FINGERPRINT_KEY = "com.runanywhere.sdk.device.fingerprint"

    @Volatile
    private var cachedDeviceUUID: String? = null

    // Lock object for synchronizing cache access
    private val cacheLock = Any()

    /**
     * Get a persistent device UUID that survives app reinstalls
     * Uses keychain/secure storage for persistence, falls back to vendor ID or generates new UUID
     * Matches iOS DeviceIdentity.persistentUUID
     *
     * Thread Safety:
     * Uses synchronized block to prevent race conditions when initializing
     * the cached UUID from multiple threads.
     */
    val persistentUUID: String
        @OptIn(ExperimentalUuidApi::class)
        get() {
            logger.debug("Attempting to retrieve persistent device UUID")

            // Double-checked locking pattern for thread-safe lazy initialization
            cachedDeviceUUID?.let {
                logger.debug("Using cached device UUID")
                return it
            }

            return synchronized(cacheLock) {
                // Check again inside synchronized block
                cachedDeviceUUID?.let {
                    logger.debug("Using cached device UUID (synchronized check)")
                    return@synchronized it
                }

                runBlocking {
                    // Strategy 1: Try to get from persistent secure storage (survives app reinstalls)
                    val storedUUID = secureStorage.getSecureString(DEVICE_UUID_KEY)
                    if (storedUUID != null) {
                        logger.debug("Retrieved device UUID from persistent secure storage")
                        cachedDeviceUUID = storedUUID
                        return@runBlocking storedUUID
                    }

                    // Strategy 2: Use platform-specific vendor UUID if available
                    val vendorUUID = getVendorBasedUUID()
                    if (vendorUUID != null) {
                        logger.debug("Retrieved device UUID from vendor identifier")
                        // Store this in persistent storage for future use
                        try {
                            secureStorage.setSecureString(DEVICE_UUID_KEY, vendorUUID)
                        } catch (e: Exception) {
                            logger.error("Failed to store vendor UUID", e)
                        }
                        cachedDeviceUUID = vendorUUID
                        return@runBlocking vendorUUID
                    }

                    // Strategy 3: Generate new UUID and store persistently
                    val newUUID = generateAndStoreNewUUID()
                    logger.debug("Generated and stored new device UUID")
                    return@runBlocking newUUID
                }
            }
        }

    /**
     * Get device fingerprint for additional validation
     * This provides device characteristics that can help verify identity
     */
    fun getDeviceFingerprint(): String {
        val components = mutableListOf<String>()

        try {
            // Get platform-specific device characteristics
            val deviceInfo = getPlatformDeviceInfo()

            // Hardware characteristics (these don't change)
            components.add("mem:${deviceInfo.totalMemory}")
            components.add("arch:${deviceInfo.architecture}")
            components.add("cores:${deviceInfo.coreCount}")
            components.add("model:${deviceInfo.deviceModel}")

            // OS info (major version only, as minor versions change)
            components.add("os:${deviceInfo.osMajorVersion}")

            // Create fingerprint hash
            val fingerprintString = components.joinToString("|")
            val fingerprint = sha256(fingerprintString)

            // Store fingerprint for future validation
            runBlocking {
                try {
                    secureStorage.setSecureString(DEVICE_FINGERPRINT_KEY, fingerprint)
                } catch (e: Exception) {
                    logger.error("Failed to store device fingerprint", e)
                }
            }

            return fingerprint
        } catch (e: Exception) {
            logger.error("Failed to generate device fingerprint", e)
            return "unknown"
        }
    }

    /**
     * Validate if a device UUID is properly formatted
     * Matches iOS DeviceIdentity.validateUUID(_:)
     */
    fun validateUUID(uuid: String): Boolean {
        return uuid.length == 36 && uuid.contains("-")
    }

    /**
     * Clear device identity (for testing or privacy purposes)
     * Thread-safe: Can be called from any thread
     */
    suspend fun clearDeviceIdentity() {
        synchronized(cacheLock) {
            cachedDeviceUUID = null
        }
        secureStorage.removeSecure(DEVICE_UUID_KEY)
        secureStorage.removeSecure(DEVICE_FINGERPRINT_KEY)
    }

    /**
     * Check if device identity exists
     */
    suspend fun hasDeviceIdentity(): Boolean {
        return secureStorage.containsKey(DEVICE_UUID_KEY)
    }

    // MARK: - Private Methods

    /**
     * Get vendor-based UUID (platform-specific implementation)
     */
    private suspend fun getVendorBasedUUID(): String? {
        return try {
            getPlatformVendorUUID()
        } catch (e: Exception) {
            logger.debug("Failed to get vendor UUID: ${e.message}")
            null
        }
    }

    /**
     * Generate and store a completely new UUID
     * Note: This is called from within synchronized block in persistentUUID getter
     */
    @OptIn(ExperimentalUuidApi::class)
    private suspend fun generateAndStoreNewUUID(): String {
        val newUUID = Uuid.random().toString()
        try {
            secureStorage.setSecureString(DEVICE_UUID_KEY, newUUID)
        } catch (e: Exception) {
            logger.error("Failed to store new UUID", e)
        }
        // Safe to set here as we're within synchronized block
        cachedDeviceUUID = newUUID
        return newUUID
    }

    /**
     * Create SHA256 hash of a string
     */
    private fun sha256(string: String): String {
        return try {
            // Platform-specific SHA256 implementation
            platformSha256(string)
        } catch (e: Exception) {
            logger.error("Failed to generate SHA256", e)
            string.hashCode().toString()
        }
    }
}

/**
 * Type alias for backward compatibility during migration
 */
@Deprecated("Use DeviceIdentity instead", ReplaceWith("DeviceIdentity"))
typealias PersistentDeviceIdentity = DeviceIdentity

/**
 * Platform-specific device information for fingerprinting
 */
data class PlatformDeviceInfo(
    val totalMemory: Long,
    val architecture: String,
    val coreCount: Int,
    val deviceModel: String,
    val osMajorVersion: String
)

/**
 * Platform-specific functions - implemented in each platform module
 */
expect suspend fun getPlatformVendorUUID(): String?
expect fun getPlatformDeviceInfo(): PlatformDeviceInfo
expect fun platformSha256(input: String): String
