package com.runanywhere.runanywhereai.data.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal interface SecureStringPreferences {
    fun getString(key: String): String?

    fun putString(key: String, value: String): Boolean

    fun contains(key: String): Boolean
}

internal fun securePreferences(context: Context, name: String): SecureStringPreferences {
    val appContext = context.applicationContext
    check(appContext.deleteSharedPreferences(name)) { "Could not delete legacy secure storage" }
    return AndroidKeystoreSecureStringPreferences(appContext, securePreferencesDirectoryName(name))
}

internal fun securePreferencesDirectoryName(name: String): String = "${name}_secure_storage"

private class AndroidKeystoreSecureStringPreferences(
    context: Context,
    private val directoryName: String,
) : SecureStringPreferences {
    private val ciphertextStore = NoBackupCiphertextStore(context, directoryName)
    private val encryptionKey: SecretKey = synchronized(KEYSTORE_LOCK) { loadOrCreateEncryptionKey() }

    override fun getString(key: String): String? {
        val envelope = ciphertextStore.read(key) ?: return null
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

    override fun putString(key: String, value: String): Boolean {
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
        return ciphertextStore.write(key, envelope)
    }

    override fun contains(key: String): Boolean = getString(key) != null

    private fun associatedData(key: String): ByteArray =
        "$directoryName\u0000$key".toByteArray(StandardCharsets.UTF_8)

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

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "com.runanywhere.runanywhereai.secure-preferences.aes-gcm"
        const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        const val KEY_SIZE_BITS = 256
        const val GCM_TAG_BITS = 128
        val KEYSTORE_LOCK = Any()
    }
}
