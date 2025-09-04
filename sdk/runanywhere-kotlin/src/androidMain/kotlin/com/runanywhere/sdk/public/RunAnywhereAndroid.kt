package com.runanywhere.sdk.public

import android.content.Context
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * Android-specific extensions for RunAnywhere SDK
 */

// Store the Android context
private var androidContext: Context? = null

/**
 * Android-specific initialization with Context
 */
suspend fun RunAnywhere.initialize(
    context: Context,
    apiKey: String,
    baseURL: String? = null,
    environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
) {
    androidContext = context.applicationContext
    initialize(apiKey, baseURL, environment)
}

/**
 * Platform-specific initialization implementation for Android
 */
internal actual suspend fun RunAnywhere.initializePlatform(
    apiKey: String,
    baseURL: String?,
    environment: SDKEnvironment
) {
    val context = androidContext ?: throw IllegalStateException(
        "Android context not provided. Use RunAnywhere.initialize(context, ...) on Android"
    )

    // Initialize Android-specific services
    ServiceContainer.shared.initialize(context)
    FileManager.shared.initialize(context)

    // TODO: Initialize other Android-specific services
    println("Android platform initialized with API key: $apiKey")
}

/**
 * Platform-specific cleanup for Android
 */
internal actual suspend fun RunAnywhere.cleanupPlatform() {
    // Cleanup Android-specific resources
    ServiceContainer.shared.cleanup()
    androidContext = null
}

/**
 * Get available models - Android implementation
 */
actual suspend fun RunAnywhere.availableModels(): List<ModelInfo> {
    requireInitialized()
    // TODO: Implement actual model listing
    return emptyList()
}

/**
 * Download a model - Android implementation
 */
actual suspend fun RunAnywhere.downloadModel(modelId: String): Flow<Float> {
    requireInitialized()
    // TODO: Implement actual download
    return flowOf(0.0f, 0.5f, 1.0f)
}

/**
 * Simple transcription - Android implementation
 */
actual suspend fun RunAnywhere.transcribe(audioData: ByteArray): String {
    requireInitialized()
    // TODO: Implement actual transcription
    return "Transcribed text from Android"
}
