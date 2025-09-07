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

    companion object {
        private val logger = SDKLogger("RunAnywherePlugin")
        var isInitialized = false
        var initializationJob: Job? = null
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
                            // Initialize SDK with development environment
                            RunAnywhere.initialize(
                                apiKey = "dev-api-key",
                                baseURL = null,
                                environment = SDKEnvironment.DEVELOPMENT
                            )

                            isInitialized = true

                            ApplicationManager.getApplication().invokeLater {
                                println("✅ RunAnywhere SDK v0.1 initialized successfully")
                                println("📊 Development mode enabled")
                                showNotification(project, "SDK Ready",
                                    "RunAnywhere SDK initialized successfully",
                                    NotificationType.INFORMATION)
                            }

                        } catch (e: Exception) {
                            ApplicationManager.getApplication().invokeLater {
                                println("❌ Failed to initialize RunAnywhere SDK v0.1: ${e.message}")
                                e.printStackTrace()
                                showNotification(project, "SDK Error",
                                    "Failed to initialize SDK: ${e.message}",
                                    NotificationType.ERROR)
                            }
                        }
                    }
                }
            })

        // Initialize voice service when needed
        project.service<com.runanywhere.plugin.services.VoiceService>().initialize()

        println("RunAnywhere Voice Commands plugin started for project: ${project.name}")
    }

    private fun showNotification(project: Project, title: String, content: String, type: NotificationType) {
        ApplicationManager.getApplication().invokeLater {
            NotificationGroupManager.getInstance()
                .getNotificationGroup("RunAnywhere.Notifications")
                .createNotification(title, content, type)
                .notify(project)
        }
    }
}
