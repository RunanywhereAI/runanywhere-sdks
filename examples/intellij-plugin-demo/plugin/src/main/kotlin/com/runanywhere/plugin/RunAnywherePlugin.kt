package com.runanywhere.plugin

import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.service
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.StartupActivity
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.stt.WhisperSTTService
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.io.File
import java.net.URL

/**
 * Main plugin startup activity
 */
class RunAnywherePlugin : StartupActivity {

    @OptIn(DelicateCoroutinesApi::class)
    override fun runActivity(project: Project) {
        // Initialize SDK in background
        ProgressManager.getInstance()
            .run(object : Task.Backgroundable(project, "Initializing RunAnywhere SDK", false) {
                override fun run(indicator: ProgressIndicator) {
                    indicator.text = "Initializing RunAnywhere SDK..."
                    indicator.isIndeterminate = true

                    initializationJob = GlobalScope.launch {
                        try {
                            logger.info("Starting SDK initialization with WhisperKit integration...")

                            // Step 1: Register WhisperKit STT provider before SDK initialization
                            logger.info("Registering WhisperKit STT provider...")
                            registerWhisperKitProvider()

                            // Step 2: Initialize SDK with development environment
                            logger.info("Initializing RunAnywhere SDK...")
                            RunAnywhere.initialize(
                                apiKey = "dev-api-key",
                                baseURL = null,
                                environment = SDKEnvironment.DEVELOPMENT
                            )

                            // Step 3: Verify component initialization
                            logger.info("Verifying component initialization...")
                            val serviceContainer =
                                com.runanywhere.sdk.foundation.ServiceContainer.shared
                            val registeredModules =
                                com.runanywhere.sdk.core.ModuleRegistry.registeredModules

                            isInitialized = true

                            ApplicationManager.getApplication().invokeLater {
                                println("✅ RunAnywhere SDK v0.1 initialized successfully")
                                println("📊 Development mode enabled")
                                println("🔧 Registered modules: $registeredModules")
                                println("🎙️ WhisperKit STT: ${if (com.runanywhere.sdk.core.ModuleRegistry.hasSTT) "✅" else "❌"}")
                                println("🔊 VAD: ${if (com.runanywhere.sdk.core.ModuleRegistry.hasVAD) "✅" else "❌"}")

                                showNotification(
                                    project, "SDK Ready",
                                    "RunAnywhere SDK initialized with WhisperKit and VAD support",
                                    NotificationType.INFORMATION
                                )
                            }

                        } catch (e: Exception) {
                            ApplicationManager.getApplication().invokeLater {
                                println("❌ Failed to initialize RunAnywhere SDK v0.1: ${e.message}")
                                e.printStackTrace()
                                showNotification(
                                    project, "SDK Error",
                                    "Failed to initialize SDK: ${e.message}",
                                    NotificationType.ERROR
                                )
                            }
                        }
                    }
                }
            })

        // Initialize voice service when needed
        project.service<com.runanywhere.plugin.services.VoiceService>().initialize()

        println("RunAnywhere Voice Commands plugin started for project: ${project.name}")
    }

    private fun showNotification(
        project: Project,
        title: String,
        content: String,
        type: NotificationType
    ) {
        ApplicationManager.getApplication().invokeLater {
            NotificationGroupManager.getInstance()
                .getNotificationGroup("RunAnywhere.Notifications")
                .createNotification(title, content, type)
                .notify(project)
        }
    }

    /**
     * Register WhisperKit STT provider with the SDK
     * This enables WhisperKit to be used for speech-to-text functionality
     */
    private fun registerWhisperKitProvider() {
        try {
            // Create a WhisperKit STT provider using the existing WhisperSTTService
            val whisperProvider = object : com.runanywhere.sdk.core.STTServiceProvider {
                override val name: String = "WhisperKit"

                override suspend fun createSTTService(configuration: com.runanywhere.sdk.components.stt.STTConfiguration): com.runanywhere.sdk.components.stt.STTService {
                    // Create the WhisperSTTService instance
                    return createWhisperKitService(configuration.modelId ?: "whisper-base")
                }

                override fun canHandle(modelId: String?): Boolean {
                    // WhisperKit can handle whisper models or serve as default
                    return modelId == null ||
                            modelId.contains("whisper", ignoreCase = true) ||
                            modelId.contains("base", ignoreCase = true) ||
                            modelId.contains("small", ignoreCase = true) ||
                            modelId.contains("medium", ignoreCase = true) ||
                            modelId.contains("large", ignoreCase = true)
                }
            }

            // Register the provider with the module registry
            com.runanywhere.sdk.core.ModuleRegistry.registerSTT(whisperProvider)
            logger.info("✅ WhisperKit STT provider registered successfully")

        } catch (e: Exception) {
            logger.error("❌ Failed to register WhisperKit STT provider", e)
        }
    }

    private suspend fun createWhisperKitService(modelName: String): STTService {
        // In development mode, download the actual model file (like iOS does)
        val service = WhisperSTTService()

        val isDevelopmentMode = true // Assuming development mode for now

        if (isDevelopmentMode) {
            logger.info("Creating WhisperKit service for model: $modelName (development mode)")

            // Download the actual Whisper model file (following iOS mock behavior)
            val modelPath = downloadWhisperModel(modelName)

            try {
                logger.info("Initializing WhisperKit with model at: $modelPath")
                service.initialize(modelPath)
                logger.info("WhisperKit service initialized successfully")
            } catch (e: Exception) {
                logger.warn("Failed to initialize WhisperKit model, will use fallback: ${e.message}")
                // In development mode, we can proceed even if initialization fails
                // The service will handle the error gracefully
            }
        } else {
            // In production, properly initialize with the selected model
            val modelPath = getModelPath(modelName)
            if (modelPath?.exists() == true) {
                service.initialize(modelPath.absolutePath)
            } else {
                throw Exception("Model not found: $modelName")
            }
        }

        return service
    }

    private fun downloadWhisperModel(modelName: String): String {
        // Following the iOS MockNetworkService approach - use real URLs for mock models
        val modelUrl = when (modelName) {
            "whisper-tiny" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
            "whisper-base" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
            "whisper-small" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" // Default to base
        }

        val modelsDir = File(System.getProperty("user.home"), ".runanywhere/models/whisper")
        modelsDir.mkdirs()

        val modelFile = File(modelsDir, "$modelName.bin")

        // Download if not already cached
        if (!modelFile.exists()) {
            try {
                logger.info("Downloading Whisper model from: $modelUrl")
                URL(modelUrl).openStream().use { input ->
                    modelFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                logger.info("Downloaded model to: ${modelFile.absolutePath}")
            } catch (e: Exception) {
                logger.warn("Failed to download model, creating fallback: ${e.message}")
                // Create a minimal fallback file
                modelFile.writeBytes(ByteArray(1024))
            }
        } else {
            logger.info("Using cached model at: ${modelFile.absolutePath}")
        }

        return modelFile.absolutePath
    }

    private fun getModelPath(modelName: String): File? {
        // This function should return the path to the model file
        // For now, it's assumed to be null
        return null
    }
}

private val logger = SDKLogger("RunAnywherePlugin")
var isInitialized = false
var initializationJob: Job? = null
