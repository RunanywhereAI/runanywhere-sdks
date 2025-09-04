package com.runanywhere.sdk.public

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import java.io.File

/**
 * JVM-specific implementation for RunAnywhere SDK
 * This is used for JetBrains plugins and desktop applications
 */

// Store the working directory for JVM
private var workingDirectory: String = System.getProperty("user.dir")

/**
 * JVM-specific initialization with optional working directory
 */
suspend fun RunAnywhere.initialize(
    apiKey: String,
    baseURL: String? = null,
    environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT,
    workingDir: String = System.getProperty("user.dir")
) {
    workingDirectory = workingDir
    initialize(apiKey, baseURL, environment)
}

/**
 * Platform-specific initialization implementation for JVM
 */
internal actual suspend fun RunAnywhere.initializePlatform(
    apiKey: String,
    baseURL: String?,
    environment: SDKEnvironment
) {
    // Initialize JVM-specific services
    ServiceContainer.shared.initialize(workingDirectory)
    FileManager.shared.initialize(workingDirectory)

    // Create necessary directories
    val baseDir = File(workingDirectory, ".runanywhere")
    if (!baseDir.exists()) {
        baseDir.mkdirs()
    }

    println("JVM platform initialized with API key: $apiKey")
    println("Working directory: $workingDirectory")
}

/**
 * Platform-specific cleanup for JVM
 */
internal actual suspend fun RunAnywhere.cleanupPlatform() {
    // Cleanup JVM-specific resources
    ServiceContainer.shared.cleanup()
}

/**
 * Get available models - JVM implementation
 */
actual suspend fun RunAnywhere.availableModels(): List<ModelInfo> {
    requireInitialized()
    // TODO: Implement actual model listing for JVM
    return emptyList()
}

/**
 * Download a model - JVM implementation
 */
actual suspend fun RunAnywhere.downloadModel(modelId: String): Flow<Float> {
    requireInitialized()
    // TODO: Implement actual download for JVM
    return flowOf(0.0f, 0.5f, 1.0f)
}

/**
 * Simple transcription - JVM implementation
 */
actual suspend fun RunAnywhere.transcribe(audioData: ByteArray): String {
    requireInitialized()
    // TODO: Implement actual transcription using whisper-jni
    return "Transcribed text from JVM"
}
