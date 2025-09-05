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
import com.intellij.openapi.ui.Messages
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.*
import java.util.prefs.Preferences

/**
 * Main plugin startup activity
 */
class RunAnywherePlugin : StartupActivity {

    companion object {
        private val logger = SDKLogger("RunAnywherePlugin")
        var isInitialized = false
        var initializationJob: Job? = null
        private val prefs = Preferences.userNodeForPackage(RunAnywherePlugin::class.java)
        private const val PREF_SELECTED_MODEL = "selected_stt_model"
        private const val PREF_AUTO_LOAD_MODEL = "auto_load_model"
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
                            // Initialize SDK with development mode for testing
                            RunAnywhere.initialize(
                                apiKey = "dev-api-key",
                                baseURL = "https://api.runanywhere.ai",
                                environment = SDKEnvironment.DEVELOPMENT
                            )

                            isInitialized = true

                            // Listen to SDK events
                            launch {
                                EventBus.shared.initializationEvents.collect { event ->
                                    when (event) {
                                        is SDKInitializationEvent.Started -> {
                                            // Initialization started
                                        }

                                        is SDKInitializationEvent.Completed -> {
                                            ApplicationManager.getApplication().invokeLater {
                                                println("✅ RunAnywhere SDK initialized successfully")
                                            }

                                            // Auto-download default STT model
                                            checkAndLoadSTTModel(project)
                                        }

                                        is SDKInitializationEvent.Failed -> {
                                            ApplicationManager.getApplication().invokeLater {
                                                println("❌ SDK initialization failed: ${event.error.message}")
                                            }
                                        }
                                    }
                                }
                            }

                        } catch (e: Exception) {
                            ApplicationManager.getApplication().invokeLater {
                                println("❌ Failed to initialize RunAnywhere SDK: ${e.message}")
                            }
                        }
                    }
                }
            })

        // Initialize voice service when needed
        project.service<com.runanywhere.plugin.services.VoiceService>().initialize()

        println("RunAnywhere Voice Commands plugin started for project: ${project.name}")
    }

    private suspend fun checkAndLoadSTTModel(project: Project) {
        try {
            val models = RunAnywhere.availableModels()
                .filter { it.category == ModelCategory.SPEECH_RECOGNITION }

            if (models.isEmpty()) {
                showNotification(project, "No STT Models",
                    "No STT models available", NotificationType.WARNING)
                return
            }

            logger.info("Found ${models.size} STT models available")
            val downloader = RunAnywhere.getModelDownloader()

            // Check for already downloaded models
            val downloadedModels = models.filter { downloader.isModelDownloaded(it) }

            if (downloadedModels.isNotEmpty()) {
                logger.info("Found ${downloadedModels.size} already downloaded models")
                // Auto-load the first downloaded model (preferring tiny, then base, then first)
                val modelToLoad = downloadedModels.find { it.id == "whisper-tiny" }
                    ?: downloadedModels.find { it.id == "whisper-base" }
                    ?: downloadedModels.first()

                logger.info("Auto-loading existing model: ${modelToLoad.id}")
                loadModelIntoWhisper(project, modelToLoad)
            } else {
                // No models downloaded - show notification to use UI
                logger.info("No models downloaded yet")
                showNotification(project, "Models Available",
                    "STT models available for download. Open 'RunAnywhere STT' tool window to download.",
                    NotificationType.INFORMATION)
            }

            // Always show which models are available
            val availableInfo = models.joinToString(", ") { "${it.name} (${(it.downloadSize ?: 0) / 1048576}MB)" }
            logger.info("Available models: $availableInfo")

        } catch (e: Exception) {
            logger.error("Failed to check STT models", e)
            showNotification(project, "STT Error",
                "Failed to check STT models: ${e.message}",
                NotificationType.ERROR)
        }
    }

    private suspend fun loadModelIntoWhisper(project: Project, model: ModelInfo) {
        try {
            // Check if already loaded
            val currentModel = RunAnywhere.getLoadedSTTModel()
            if (currentModel?.id == model.id) {
                logger.info("Model already loaded in WhisperJNI: ${model.id}")
                showNotification(project, "Model Ready",
                    "${model.name} is ready for transcription",
                    NotificationType.INFORMATION)
            } else {
                logger.info("Loading model into WhisperJNI: ${model.id}")
                RunAnywhere.loadSTTModel(model)

                // Save as preferred model
                prefs.put(PREF_SELECTED_MODEL, model.id)

                showNotification(project, "Model Loaded",
                    "${model.name} loaded successfully",
                    NotificationType.INFORMATION)
            }

            // Verify pipeline is ready
            if (RunAnywhere.isSTTPipelineReady()) {
                logger.info("STT pipeline is ready for voice transcription")
            }
        } catch (e: Exception) {
            logger.error("Failed to load model into WhisperJNI", e)
            showNotification(project, "Load Error",
                "Failed to load model: ${e.message}",
                NotificationType.ERROR)
        }
    }

    private suspend fun downloadAndLoadModel(project: Project, model: ModelInfo) {
        try {
            showNotification(project, "Downloading",
                "Downloading ${model.name}...",
                NotificationType.INFORMATION)

            RunAnywhere.downloadModel(model.id).collect { progress ->
                if (progress >= 1.0f) {
                    loadModelIntoWhisper(project, model)
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to download model", e)
            showNotification(project, "Download Error",
                "Failed to download: ${e.message}",
                NotificationType.ERROR)
        }
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
