package com.runanywhere.sdk.infrastructure.modelmanagement.services

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ConfigurationSource
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

private val logger = SDKLogger("ModelDiscoveryJvm")

/**
 * JVM/Android implementation of bundle model discovery
 *
 * On JVM: Scans classpath resources for model files
 * On Android: Uses AssetManager (when available) or falls back to classpath
 */
actual suspend fun discoverBundleModelsPlatform(): List<ModelInfo> {
    val discoveredModels = mutableListOf<ModelInfo>()

    // Known model extensions to scan for
    val modelExtensions = listOf("gguf", "onnx", "tflite", "bin", "safetensors")

    try {
        // Try to find models in common resource locations
        val resourcePaths =
            listOf(
                "models/",
                "assets/models/",
                "raw/",
            )

        for (resourcePath in resourcePaths) {
            for (extension in modelExtensions) {
                val models = scanClasspathForModels(resourcePath, extension)
                discoveredModels.addAll(models)
            }
        }
    } catch (e: Exception) {
        logger.warn("Error discovering bundle models: ${e.message}")
    }

    return discoveredModels.distinctBy { it.id }
}

/**
 * Scan classpath for model files with given extension
 */
private fun scanClasspathForModels(
    resourcePath: String,
    extension: String,
): List<ModelInfo> {
    val models = mutableListOf<ModelInfo>()

    try {
        // Use the ClassLoader to find resources
        val classLoader = Thread.currentThread().contextClassLoader ?: ModelDiscoveryService::class.java.classLoader

        // Try to enumerate resources in the path
        val resources = classLoader?.getResources(resourcePath)

        while (resources?.hasMoreElements() == true) {
            val url = resources.nextElement()
            val protocol = url.protocol

            when (protocol) {
                "file" -> {
                    // File-based resources (development environment)
                    val file = java.io.File(url.toURI())
                    if (file.isDirectory) {
                        file.listFiles()?.filter { it.extension == extension }?.forEach { modelFile ->
                            val modelId = modelFile.nameWithoutExtension
                            models.add(
                                createBundledModelInfo(
                                    modelId = modelId,
                                    localPath = modelFile.absolutePath,
                                    format = getFormatFromExtension(extension),
                                    size = modelFile.length(),
                                ),
                            )
                        }
                    }
                }
                "jar" -> {
                    // JAR-based resources (packaged application)
                    scanJarForModels(url.toString(), extension)?.let { jarModels ->
                        models.addAll(jarModels)
                    }
                }
            }
        }
    } catch (e: Exception) {
        logger.debug("Could not scan $resourcePath for $extension: ${e.message}")
    }

    return models
}

/**
 * Scan inside a JAR file for model resources
 */
@Suppress("UNUSED_PARAMETER")
private fun scanJarForModels(
    jarUrl: String,
    extension: String,
): List<ModelInfo>? {
    // JAR scanning is complex and rarely needed for bundled models
    // Most Android apps use AssetManager, and JVM apps typically don't bundle large models
    logger.debug("JAR scanning not implemented for: $jarUrl")
    return null
}

/**
 * Create a ModelInfo for a bundled model
 */
private fun createBundledModelInfo(
    modelId: String,
    localPath: String,
    format: ModelFormat,
    size: Long,
): ModelInfo {
    val framework = inferFrameworkFromFormat(format)
    val category = inferCategoryFromModelId(modelId)

    return ModelInfo(
        id = modelId,
        name = modelId.replace("-", " ").replace("_", " "),
        category = category,
        format = format,
        localPath = localPath,
        downloadSize = size,
        memoryRequired = (size * 1.5).toLong(),
        compatibleFrameworks = listOf(framework),
        preferredFramework = framework,
        source = ConfigurationSource.LOCAL,
        metadata =
            ModelInfoMetadata(
                description = "Bundled model",
                version = "1.0.0",
            ),
    )
}

private fun getFormatFromExtension(extension: String): ModelFormat =
    when (extension.lowercase()) {
        "gguf", "ggml" -> ModelFormat.GGUF
        "onnx" -> ModelFormat.ONNX
        "tflite" -> ModelFormat.TFLITE
        "bin" -> ModelFormat.BIN
        "safetensors" -> ModelFormat.SAFETENSORS
        else -> ModelFormat.OTHER
    }

private fun inferFrameworkFromFormat(format: ModelFormat): InferenceFramework =
    when (format) {
        ModelFormat.GGUF -> InferenceFramework.LLAMA_CPP
        ModelFormat.ONNX -> InferenceFramework.ONNX
        ModelFormat.TFLITE -> InferenceFramework.TENSORFLOW_LITE
        ModelFormat.SAFETENSORS -> InferenceFramework.MLC
        else -> InferenceFramework.UNKNOWN
    }

private fun inferCategoryFromModelId(modelId: String): ModelCategory {
    val lower = modelId.lowercase()
    return when {
        lower.contains("whisper") -> ModelCategory.SPEECH_RECOGNITION
        lower.contains("llama") || lower.contains("llm") -> ModelCategory.LANGUAGE
        lower.contains("tts") -> ModelCategory.SPEECH_SYNTHESIS
        else -> ModelCategory.OTHER
    }
}
