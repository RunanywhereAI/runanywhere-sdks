/**
 * SecureStorageManager.kt
 *
 * Android secure storage backed directly by an Android Keystore AES-256-GCM key.
 *
 * Reference: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/security/
 * AndroidKeychainManager.kt
 */

package com.margelo.nitro.runanywhere

import android.annotation.SuppressLint
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Secure storage manager for persistent device identity and sensitive data.
 * Values are authenticated and encrypted; the non-exportable key lives in Android Keystore.
 */
object SecureStorageManager {
    private const val TAG = "SecureStorageManager"
    private const val STORE_DIRECTORY_NAME = "runanywhere_react_native_secure_storage"
    private const val LEGACY_PREFS_NAME = "runanywhere_secure_prefs"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "com.runanywhere.reactnative.secure-storage.aes-gcm"
    private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
    private const val KEY_SIZE_BITS = 256
    private const val GCM_TAG_BITS = 128

    @SuppressLint("StaticFieldLeak")
    @Volatile
    private var context: Context? = null
    @Volatile
    private var ciphertextStore: NoBackupCiphertextStore? = null
    @Volatile
    private var encryptionKey: SecretKey? = null

    /** Get the stored context for platform bridge operations. */
    @JvmStatic
    fun getContext(): Context? = context

    /**
     * Initialize with application context.
     * Thread-safe: guards against concurrent first-call races from JNI threads and NitroModules init.
     */
    @JvmStatic
    fun initialize(applicationContext: Context) {
        if (ciphertextStore != null && encryptionKey != null) return
        synchronized(this) {
            if (ciphertextStore != null && encryptionKey != null) return
            val appContext = applicationContext.applicationContext
            try {
                check(appContext.deleteSharedPreferences(LEGACY_PREFS_NAME)) {
                    "Could not delete legacy secure storage"
                }
                val initializedStore = NoBackupCiphertextStore(appContext, STORE_DIRECTORY_NAME)
                val initializedKey = loadOrCreateEncryptionKey()

                ciphertextStore = initializedStore
                encryptionKey = initializedKey
                // Publish the context last. PlatformAdapterBridge uses a non-null
                // context as the readiness signal for secure storage.
                context = appContext
                Log.i(TAG, "SecureStorageManager initialized")
            } catch (exception: Exception) {
                context = null
                ciphertextStore = null
                encryptionKey = null
                Log.e(TAG, "Failed to initialize Android Keystore secure storage", exception)
            }
        }
    }

    /** Set a secure string value. */
    @JvmStatic
    fun set(key: String, value: String): Boolean {
        val activeStore = ciphertextStore ?: return false
        val activeKey = encryptionKey ?: return false
        return try {
            activeStore.write(key, encrypt(activeKey, key, value))
        } catch (exception: Exception) {
            Log.e(TAG, "Failed to write secure-storage entry", exception)
            false
        }
    }

    /** Get a secure string value, or null only when the key is absent. */
    @JvmStatic
    fun get(key: String): String? {
        val activeStore =
            checkNotNull(ciphertextStore) { "Secure storage is not initialized" }
        val activeKey =
            checkNotNull(encryptionKey) { "Secure storage is not initialized" }
        val envelope = activeStore.read(key) ?: return null
        return decrypt(activeKey, key, envelope)
    }

    /** Delete a secure value. */
    @JvmStatic
    fun delete(key: String): Boolean {
        val activeStore = ciphertextStore ?: return false
        return try {
            activeStore.delete(key)
        } catch (exception: Exception) {
            Log.e(TAG, "Failed to delete secure-storage entry", exception)
            false
        }
    }

    private fun encrypt(encryptionKey: SecretKey, key: String, value: String): ByteArray {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey)
        cipher.updateAAD(associatedData(key))
        val ciphertext = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val iv = cipher.iv
        require(iv.size <= 0xff) { "AES-GCM IV is too large" }

        val envelope = ByteArray(1 + iv.size + ciphertext.size)
        envelope[0] = iv.size.toByte()
        iv.copyInto(envelope, destinationOffset = 1)
        ciphertext.copyInto(envelope, destinationOffset = 1 + iv.size)
        return envelope
    }

    private fun decrypt(encryptionKey: SecretKey, key: String, envelope: ByteArray): String {
        require(envelope.isNotEmpty()) { "Encrypted value is empty" }
        val ivSize = envelope[0].toInt() and 0xff
        require(ivSize > 0 && envelope.size > 1 + ivSize) { "Encrypted value is malformed" }

        val iv = envelope.copyOfRange(1, 1 + ivSize)
        val ciphertext = envelope.copyOfRange(1 + ivSize, envelope.size)
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, encryptionKey, GCMParameterSpec(GCM_TAG_BITS, iv))
        cipher.updateAAD(associatedData(key))
        return cipher.doFinal(ciphertext).toString(StandardCharsets.UTF_8)
    }

    private fun associatedData(key: String): ByteArray =
        "$STORE_DIRECTORY_NAME\u0000$key".toByteArray(StandardCharsets.UTF_8)

    private fun loadOrCreateEncryptionKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        keyGenerator.init(
            KeyGenParameterSpec
                .Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .setKeySize(KEY_SIZE_BITS)
                .build(),
        )
        return keyGenerator.generateKey()
    }
}
