package com.runanywhere.sdk.data.config

import android.content.Context
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * Android implementation of ConfigurationLoader
 * Loads configuration files from assets directory
 */
actual suspend fun ConfigurationLoader.loadResourceFile(fileName: String): String = withContext(Dispatchers.IO) {
    try {
        // Try to get Android context from ServiceContainer
        // Note: This requires ServiceContainer to have context available
        val context = try {
            // Access Android context if available
            val contextField = ServiceContainer::class.java.getDeclaredField("androidContext")
            contextField.isAccessible = true
            contextField.get(ServiceContainer.shared) as? Context
        } catch (e: Exception) {
            null
        }

        if (context != null) {
            try {
                context.assets.open(fileName).bufferedReader().use { it.readText() }
            } catch (e: IOException) {
                // File not found in assets - return empty string
                ""
            }
        } else {
            // Fallback: try to load from external storage or app files
            // This is a simplified implementation
            ""
        }
    } catch (e: Exception) {
        ""
    }
}

