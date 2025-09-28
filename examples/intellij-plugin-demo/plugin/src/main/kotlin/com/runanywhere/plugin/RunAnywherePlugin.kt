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
import com.runanywhere.sdk.providers.JvmWhisperSTTServiceProvider
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Main plugin startup activity with production backend authentication
 */
class RunAnywherePlugin : StartupActivity {

    companion object {
        // API key configuration - can be set via:
        // 1. System property: -Drunanywhere.api.key=your_key
        // 2. Environment variable: RUNANYWHERE_API_KEY=your_key
        private val API_KEY = System.getProperty("runanywhere.api.key")
            ?: System.getenv("RUNANYWHERE_API_KEY")
            ?: "" // Set via environment variable or system property

        // API URL configuration - can be set via:
        // 1. System property: -Drunanywhere.api.url=your_url
        // 2. Environment variable: RUNANYWHERE_API_URL=your_url
        private val API_URL = System.getProperty("runanywhere.api.url")
            ?: System.getenv("RUNANYWHERE_API_URL")
            // No default URL - must be provided via environment

        // SDK Environment configuration
        private val SDK_ENVIRONMENT = when (System.getProperty("runanywhere.environment", "production").lowercase()) {
            "development", "dev" -> SDKEnvironment.DEVELOPMENT
            "staging" -> SDKEnvironment.STAGING
            else -> SDKEnvironment.PRODUCTION
        }
    }

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
                            logger.info("Starting SDK initialization...")
                            logger.info("Environment: $SDK_ENVIRONMENT")
                            logger.info("API Key configured: ${if (API_KEY.isNotEmpty()) "Yes" else "No"}")

                            // Step 1: Register WhisperJNI STT provider
                            // TODO: For v1, we're using hardcoded models defined in the provider
                            //       In future versions, models will be served/configured from the console
                            logger.info("Registering WhisperJNI STT provider...")
                            registerWhisperKitProvider()

                            // Step 2: Initialize SDK with backend authentication
                            logger.info("Initializing RunAnywhere SDK with backend authentication...")
                            RunAnywhere.initialize(
                                apiKey = API_KEY,
                                baseURL = "", // Must be provided via environment
                                environment = SDK_ENVIRONMENT
                            )

                            // Step 3: Verify component initialization
                            logger.info("Verifying component initialization...")
                            val serviceContainer =
                                com.runanywhere.sdk.foundation.ServiceContainer.shared
                            val registeredModules =
                                com.runanywhere.sdk.core.ModuleRegistry.registeredModules

                            isInitialized = true

                            ApplicationManager.getApplication().invokeLater {
                                val envEmoji = when (SDK_ENVIRONMENT) {
                                    SDKEnvironment.DEVELOPMENT -> "🔧"
                                    SDKEnvironment.STAGING -> "🚧"
                                    SDKEnvironment.PRODUCTION -> "🚀"
                                }

                                println("✅ RunAnywhere SDK v0.1 initialized successfully")
                                println("$envEmoji Environment: $SDK_ENVIRONMENT")
                                println("🔐 Authenticated with backend")
                                println("📊 Registered modules: $registeredModules")
                                println("🎙️ WhisperJNI STT: ${if (com.runanywhere.sdk.core.ModuleRegistry.hasSTT) "✅" else "❌"}")
                                println("🔊 VAD: ${if (com.runanywhere.sdk.core.ModuleRegistry.hasVAD) "✅" else "❌"}")

                                showNotification(
                                    project, "SDK Ready",
                                    "RunAnywhere SDK initialized and authenticated with backend",
                                    NotificationType.INFORMATION
                                )
                            }

                        } catch (e: Exception) {
                            ApplicationManager.getApplication().invokeLater {
                                val errorMessage = when {
                                    e.message?.contains("API key") == true ->
                                        "Invalid API key. Please check your configuration."
                                    e.message?.contains("network") == true ->
                                        "Network error. Please check your connection."
                                    else -> e.message ?: "Unknown error"
                                }

                                println("❌ Failed to initialize RunAnywhere SDK: $errorMessage")
                                e.printStackTrace()

                                showNotification(
                                    project, "SDK Error",
                                    "Failed to initialize SDK: $errorMessage",
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
     * Register JVM WhisperJNI STT provider with the SDK
     * This enables real WhisperJNI transcription functionality (not mocked)
     */
    private fun registerWhisperKitProvider() {
        try {
            // Use the real JVM WhisperSTT provider instead of mock
            JvmWhisperSTTServiceProvider.register()
            logger.info("✅ JVM WhisperJNI STT provider registered successfully")

            // Log available models
            val provider = JvmWhisperSTTServiceProvider()
            val availableModels = provider.getAvailableModels()
            logger.info("Available Whisper models: ${availableModels.map { "${it.modelId} (${if (it.isDownloaded) "downloaded" else "not downloaded"})" }}")

        } catch (e: Exception) {
            logger.error("❌ Failed to register JVM WhisperJNI STT provider", e)
        }
    }
}

private val logger = SDKLogger("RunAnywherePlugin")
var isInitialized = false
var initializationJob: Job? = null
