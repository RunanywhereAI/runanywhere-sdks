package com.runanywhere.sdk.services.auth

import com.runanywhere.sdk.foundation.SDKLogger
import java.io.File
import java.util.Properties

/**
 * JVM Authentication Service
 * Manages authentication without Android SharedPreferences
 */
class JvmAuthenticationService(private val workingDirectory: String) {

    private val logger = SDKLogger("JvmAuthenticationService")
    private val authFile = File(workingDirectory, ".runanywhere/auth.properties")
    private var apiKey: String? = null

    suspend fun initialize(apiKey: String) {
        this.apiKey = apiKey
        saveApiKey(apiKey)
        logger.info("Authentication service initialized")
    }

    fun getApiKey(): String? = apiKey

    fun isAuthenticated(): Boolean = !apiKey.isNullOrEmpty()

    private fun saveApiKey(key: String) {
        try {
            authFile.parentFile?.mkdirs()
            val props = Properties()
            props.setProperty("api_key", key)
            authFile.outputStream().use { props.store(it, "RunAnywhere SDK Authentication") }
        } catch (e: Exception) {
            logger.error("Failed to save API key", e)
        }
    }

    private fun loadApiKey(): String? {
        return try {
            if (!authFile.exists()) return null
            val props = Properties()
            authFile.inputStream().use { props.load(it) }
            props.getProperty("api_key")
        } catch (e: Exception) {
            logger.error("Failed to load API key", e)
            null
        }
    }
}
