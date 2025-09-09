package com.runanywhere.sdk.utils

import com.runanywhere.sdk.storage.SecureStorage
import com.runanywhere.sdk.storage.createSecureStorage
import kotlinx.coroutines.runBlocking
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Persistent Device Identity Management
 * Provides a consistent device UUID that persists across app launches
 * Matches iOS PersistentDeviceIdentity functionality
 */
object PersistentDeviceIdentity {

    private const val DEVICE_UUID_KEY = "com.runanywhere.sdk.device.uuid"
    private val secureStorage: SecureStorage by lazy { createSecureStorage() }

    @Volatile
    private var cachedDeviceUUID: String? = null

    /**
     * Get persistent device UUID, creating one if it doesn't exist
     * Matches iOS PersistentDeviceIdentity.getPersistentDeviceUUID()
     */
    @OptIn(ExperimentalUuidApi::class)
    fun getPersistentDeviceUUID(): String {
        // Return cached UUID if available
        cachedDeviceUUID?.let { return it }

        return runBlocking {
            // Try to load from secure storage
            val storedUUID = secureStorage.getSecureString(DEVICE_UUID_KEY)
            if (storedUUID != null) {
                cachedDeviceUUID = storedUUID
                return@runBlocking storedUUID
            }

            // Generate new UUID and store it
            val newUUID = Uuid.random().toString()
            secureStorage.setSecureString(DEVICE_UUID_KEY, newUUID)
            cachedDeviceUUID = newUUID

            return@runBlocking newUUID
        }
    }

    /**
     * Clear device identity (for testing or privacy purposes)
     */
    suspend fun clearDeviceIdentity() {
        cachedDeviceUUID = null
        secureStorage.removeSecure(DEVICE_UUID_KEY)
    }

    /**
     * Check if device identity exists
     */
    suspend fun hasDeviceIdentity(): Boolean {
        return secureStorage.containsSecure(DEVICE_UUID_KEY)
    }
}
