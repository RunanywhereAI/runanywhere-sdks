package com.runanywhere.sdk.models

import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation for default models directory
 */
actual fun getDefaultModelsDirectory(): String {
    return AndroidPlatformContext.applicationContext.filesDir.absolutePath + "/models"
}
