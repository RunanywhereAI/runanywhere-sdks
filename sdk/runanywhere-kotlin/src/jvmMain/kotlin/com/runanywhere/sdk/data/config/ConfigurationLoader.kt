package com.runanywhere.sdk.data.config

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileNotFoundException

private val logger = SDKLogger("ConfigurationLoader")

/**
 * JVM implementation of ConfigurationLoader
 * Loads configuration files from classpath resources or file system
 */
internal actual suspend fun loadResourceFile(fileName: String): String =
    withContext(Dispatchers.IO) {
        try {
            // First, try to load from classpath resources
            val resourceStream =
                ConfigurationLoader::class.java.classLoader
                    ?.getResourceAsStream(fileName)

            if (resourceStream != null) {
                return@withContext resourceStream.bufferedReader().use { it.readText() }
            }

            // Fallback: try to load from current directory or config directory
            val configDir = File(System.getProperty("user.home"), ".runanywhere")
            val configFile = File(configDir, fileName)

            if (configFile.exists()) {
                return@withContext configFile.readText()
            }

            // Try current directory
            val currentDirFile = File(fileName)
            if (currentDirFile.exists()) {
                return@withContext currentDirFile.readText()
            }

            // File not found - log warning to assist debugging
            logger.debug("Configuration file '$fileName' not found in classpath, ~/.runanywhere/, or current directory")
            ""
        } catch (e: FileNotFoundException) {
            logger.debug("Configuration file '$fileName' not found: ${e.message}")
            ""
        } catch (e: Exception) {
            logger.warn("Error loading configuration file '$fileName': ${e.message}")
            ""
        }
    }
