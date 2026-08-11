/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android-specific secure storage backed directly by an Android Keystore AES-256-GCM key.
 */

package com.runanywhere.sdk.foundation.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android implementation of [CppBridgePlatformAdapter.PlatformSecureStorage]. Values are
 * authenticated and encrypted with AES-256-GCM; the non-exportable key lives in Android Keystore.
 *
 * @param context Any Android context; only [Context.getApplicationContext] is retained.
 */
class AndroidKeychainManager(
    context: Context,
) : CppBridgePlatformAdapter.PlatformSecureStorage {
    private val appContext: Context = context.applicationContext
    private val logger = SDKLogger(LOG_CATEGORY)

    init {
        check(appContext.deleteSharedPreferences(LEGACY_SECURE_PREFS_NAME)) {
            "Could not delete legacy secure storage"
        }
    }

    private val ciphertextStore = NoBackupCiphertextStore(appContext, STORE_DIRECTORY_NAME)
    private val encryptionKey: SecretKey by lazy {
        synchronized(KEYSTORE_LOCK) { loadOrCreateEncryptionKey() }
    }

    override fun get(key: String): ByteArray? {
        val envelope = ciphertextStore.read(key) ?: return null
        return decrypt(key, envelope)
    }

    override fun set(key: String, value: ByteArray): Boolean {
        return try {
            ciphertextStore.write(key, encrypt(key, value))
        } catch (_: Exception) {
            logger.error("Failed to write secure-storage entry")
            false
        }
    }

    override fun delete(key: String): Boolean {
        return try {
            ciphertextStore.delete(key)
        } catch (_: Exception) {
            logger.error("Failed to delete secure-storage entry")
            false
        }
    }

    override fun clear() {
        check(ciphertextStore.clear()) {
            "Could not clear secure storage"
        }
    }

    private fun encrypt(key: String, value: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey)
        cipher.updateAAD(associatedData(key))
        val ciphertext = cipher.doFinal(value)
        val iv = cipher.iv
        require(iv.size <= 0xff) { "AES-GCM IV is too large" }

        val envelope = ByteArray(1 + iv.size + ciphertext.size)
        envelope[0] = iv.size.toByte()
        iv.copyInto(envelope, destinationOffset = 1)
        ciphertext.copyInto(envelope, destinationOffset = 1 + iv.size)
        return envelope
    }

    private fun decrypt(key: String, envelope: ByteArray): ByteArray {
        require(envelope.isNotEmpty()) { "Encrypted value is empty" }
        val ivSize = envelope[0].toInt() and 0xff
        require(ivSize > 0 && envelope.size > 1 + ivSize) { "Encrypted value is malformed" }

        val iv = envelope.copyOfRange(1, 1 + ivSize)
        val ciphertext = envelope.copyOfRange(1 + ivSize, envelope.size)
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, encryptionKey, GCMParameterSpec(GCM_TAG_BITS, iv))
        cipher.updateAAD(associatedData(key))
        return cipher.doFinal(ciphertext)
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

    companion object {
        private const val STORE_DIRECTORY_NAME = "runanywhere_kotlin_secure_storage"
        private const val LEGACY_SECURE_PREFS_NAME = "runanywhere_secure_storage_encrypted"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "com.runanywhere.sdk.secure-storage.aes-gcm"
        private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val KEY_SIZE_BITS = 256
        private const val GCM_TAG_BITS = 128
        private val KEYSTORE_LOCK = Any()

        /** Logger category for secure-storage operations. */
        private const val LOG_CATEGORY = "SecureStorage"
    }
}

/**
 * Extension function to easily set Android context for CppBridgePlatformAdapter.
 * This is the recommended way to initialize storage on Android.
 *
 * @param context The Android context (will use applicationContext internally)
 */
fun CppBridgePlatformAdapter.setContext(context: Context) {
    setPlatformStorage(AndroidKeychainManager(context))
}
