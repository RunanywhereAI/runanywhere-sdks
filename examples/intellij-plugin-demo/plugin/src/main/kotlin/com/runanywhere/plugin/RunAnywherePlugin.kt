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
import com.runanywhere.sdk.components.stt.WhisperServiceProvider
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

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
            // Use the WhisperServiceProvider from the main SDK
            val whisperProvider = WhisperServiceProvider()

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
