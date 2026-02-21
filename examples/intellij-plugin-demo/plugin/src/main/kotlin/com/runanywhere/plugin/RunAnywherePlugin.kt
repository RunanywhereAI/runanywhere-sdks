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
import com.runanywhere.sdk.`public`.RunAnywhere
import com.runanywhere.sdk.`public`.SDKEnvironment
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Main plugin startup activity with production backend authentication
 */
class RunAnywherePlugin : StartupActivity {

    companion object {
        private val API_KEY = System.getProperty("runanywhere.api.key")
            ?: System.getenv("RUNANYWHERE_API_KEY")
            ?: ""

        private val API_URL = System.getProperty("runanywhere.api.url")
            ?: System.getenv("RUNANYWHERE_API_URL")

        private val SDK_ENVIRONMENT = run {
            val envProperty = System.getProperty("runanywhere.environment", "development")
            when (envProperty.lowercase()) {
                "development", "dev" -> SDKEnvironment.DEVELOPMENT
                "staging" -> SDKEnvironment.STAGING
                "production", "prod" -> SDKEnvironment.PRODUCTION
                else -> SDKEnvironment.DEVELOPMENT
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun runActivity(project: Project) {
        ProgressManager.getInstance()
            .run(object : Task.Backgroundable(project, "Initializing RunAnywhere SDK", false) {
                override fun run(indicator: ProgressIndicator) {
                    indicator.text = "Initializing RunAnywhere SDK..."
                    indicator.isIndeterminate = true

                    initializationJob = GlobalScope.launch {
                        try {
                            println("[RunAnywherePlugin] Starting SDK initialization...")
                            println("[RunAnywherePlugin] Environment: $SDK_ENVIRONMENT")

                            // Initialize SDK
                            try {
                                RunAnywhere.initialize(
                                    apiKey = if (SDK_ENVIRONMENT == SDKEnvironment.DEVELOPMENT) "demo-api-key" else API_KEY,
                                    baseURL = if (SDK_ENVIRONMENT == SDKEnvironment.DEVELOPMENT) null else (API_URL ?: "https://api.runanywhere.ai"),
                                    environment = SDK_ENVIRONMENT
                                )
                            } catch (authError: Exception) {
                                if (authError.message?.contains("500") == true ||
                                    authError.message?.contains("Authentication") == true ||
                                    authError.message?.contains("failed") == true) {
                                    println("[RunAnywherePlugin] DEVELOPMENT MODE: Auth failed, continuing with local services")
                                } else {
                                    throw authError
                                }
                            }

                            // Complete services initialization (auth, model registry, etc.)
                            try {
                                RunAnywhere.completeServicesInitialization()
                            } catch (e: Exception) {
                                println("[RunAnywherePlugin] Services init warning: ${e.message}")
                            }

                            isInitialized = true

                            ApplicationManager.getApplication().invokeLater {
                                println("[RunAnywherePlugin] SDK initialized successfully")
                                showNotification(
                                    project, "SDK Ready",
                                    "RunAnywhere SDK initialized ($SDK_ENVIRONMENT)",
                                    NotificationType.INFORMATION
                                )
                            }

                        } catch (e: Exception) {
                            ApplicationManager.getApplication().invokeLater {
                                println("[RunAnywherePlugin] Failed to initialize SDK: ${e.message}")
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
}

var isInitialized = false
var initializationJob: Job? = null
