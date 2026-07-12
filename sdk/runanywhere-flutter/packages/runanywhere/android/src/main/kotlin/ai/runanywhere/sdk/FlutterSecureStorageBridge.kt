/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package ai.runanywhere.sdk

import android.annotation.SuppressLint
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.nio.charset.CodingErrorAction
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Synchronous, fail-closed storage for the Dart platform and auth vtables.
 *
 * Dart FFI callbacks cannot await asynchronous plugin storage. This bridge
 * keeps the synchronous C contract honest by encrypting with a non-exportable
 * Android Keystore key and committing ciphertext through [AtomicFile] before
 * returning success.
 */
internal object FlutterSecureStorageBridge {
    private const val TAG = "FlutterSecureStorage"
    private const val STORE_DIRECTORY_NAME = "runanywhere_flutter_secure_storage"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "com.runanywhere.flutter.secure-storage.aes-gcm"
    private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
    private const val KEY_SIZE_BITS = 256
    private const val GCM_TAG_BITS = 128

    @SuppressLint("StaticFieldLeak")
    @Volatile
    private var ciphertextStore: NoBackupCiphertextStore? = null

    @Volatile
    private var encryptionKey: SecretKey? = null

    /** Initialize with application-scoped state before Dart can call the FFI helpers. */
    @JvmStatic
    fun initialize(applicationContext: Context) {
        if (ciphertextStore != null && encryptionKey != null) return
        synchronized(this) {
            if (ciphertextStore != null && encryptionKey != null) return
            val appContext = applicationContext.applicationContext
            ciphertextStore = NoBackupCiphertextStore(appContext, STORE_DIRECTORY_NAME)
            encryptionKey = loadOrCreateEncryptionKey()
        }
    }

    /** Persist [value] completely before returning. */
    @JvmStatic
    fun set(
        key: ByteArray,
        value: ByteArray,
    ): Boolean {
        val activeStore = ciphertextStore ?: return false
        val activeKey = encryptionKey ?: return false
        return try {
            val storageKey = decodeStorageKey(key)
            activeStore.write(storageKey, encrypt(activeKey, storageKey, value))
        } catch (exception: Exception) {
            Log.e(TAG, "Secure-storage write failed", exception)
            false
        }
    }

    /** Return null only for a clean miss; real failures are thrown to JNI. */
    @JvmStatic
    fun get(key: ByteArray): ByteArray? {
        val activeStore =
            checkNotNull(ciphertextStore) { "Secure storage is not initialized" }
        val activeKey =
            checkNotNull(encryptionKey) { "Secure storage is not initialized" }
        val storageKey = decodeStorageKey(key)
        val envelope = activeStore.read(storageKey) ?: return null
        return decrypt(activeKey, storageKey, envelope)
    }

    /** Delete the on-disk entry completely before returning. */
    @JvmStatic
    fun delete(key: ByteArray): Boolean {
        val activeStore = ciphertextStore ?: return false
        return try {
            activeStore.delete(decodeStorageKey(key))
        } catch (exception: Exception) {
            Log.e(TAG, "Secure-storage delete failed", exception)
            false
        }
    }

    private fun encrypt(
        key: SecretKey,
        storageKey: String,
        value: ByteArray,
    ): ByteArray {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(associatedData(storageKey))
        val ciphertext = cipher.doFinal(value)
        val iv = cipher.iv
        require(iv.size <= 0xff) { "AES-GCM IV is too large" }

        return ByteArray(1 + iv.size + ciphertext.size).also { envelope ->
            envelope[0] = iv.size.toByte()
            iv.copyInto(envelope, destinationOffset = 1)
            ciphertext.copyInto(envelope, destinationOffset = 1 + iv.size)
        }
    }

    private fun decrypt(
        key: SecretKey,
        storageKey: String,
        envelope: ByteArray,
    ): ByteArray {
        require(envelope.isNotEmpty()) { "Encrypted value is empty" }
        val ivSize = envelope[0].toInt() and 0xff
        require(ivSize > 0 && envelope.size > 1 + ivSize) {
            "Encrypted value is malformed"
        }

        val iv = envelope.copyOfRange(1, 1 + ivSize)
        val ciphertext = envelope.copyOfRange(1 + ivSize, envelope.size)
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        cipher.updateAAD(associatedData(storageKey))
        return cipher.doFinal(ciphertext)
    }

    private fun decodeStorageKey(key: ByteArray): String =
        StandardCharsets.UTF_8
            .newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(key))
            .toString()

    private fun associatedData(key: String): ByteArray =
        "$STORE_DIRECTORY_NAME\u0000$key".toByteArray(StandardCharsets.UTF_8)

    private fun loadOrCreateEncryptionKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val keyGenerator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
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
