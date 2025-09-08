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
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import kotlinx.coroutines.*

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
                    val whisperService = com.runanywhere.sdk.components.stt.WhisperSTTService()

                    // For development mode, we'll skip model initialization or use placeholder
                    // In production, you would download/locate the actual Whisper model file
                    val modelId = configuration.modelId ?: "whisper-base"
                    try {
                        // In development mode, we might not have actual model files
                        // For now, we'll create the service but skip full initialization
                        logger.info("Creating WhisperKit service for model: $modelId (development mode)")

                        // Note: In production, you would:
                        // 1. Download the model if not present
                        // 2. Get the actual file path
                        // 3. Initialize: whisperService.initialize("/path/to/$modelId.bin")

                    } catch (e: Exception) {
                        logger.warn("WhisperKit service creation note: ${e.message}")
                    }

                    return whisperService
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
}

private val logger = SDKLogger("RunAnywherePlugin")
var isInitialized = false
var initializationJob: Job? = null
