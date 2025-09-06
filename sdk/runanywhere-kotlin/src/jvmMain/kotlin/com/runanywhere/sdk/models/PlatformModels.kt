package com.runanywhere.sdk.models

/**
 * JVM implementation for default models directory
 */
actual fun getDefaultModelsDirectory(): String {
    return System.getProperty("user.home") + "/.runanywhere/models"
}
