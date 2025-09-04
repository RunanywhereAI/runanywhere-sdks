package com.runanywhere.plugin

import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.StartupActivity
import com.intellij.openapi.components.service
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.models.enums.ModelCategory
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect

/**
 * Main plugin startup activity
 */
class RunAnywherePlugin : StartupActivity {

    companion object {
        var isInitialized = false
        var initializationJob: Job? = null
    }

    override fun runActivity(project: Project) {
        // Initialize SDK in background
        ProgressManager.getInstance().run(object : Task.Backgroundable(project, "Initializing RunAnywhere SDK", false) {
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
                                        downloadDefaultSTTModel()
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

    private suspend fun downloadDefaultSTTModel() {
        try {
            val models = RunAnywhere.availableModels()
            val whisperModel = models.find {
                it.category == ModelCategory.SPEECH_RECOGNITION &&
                it.id == "whisper-tiny"
            }

            whisperModel?.let { model ->
                if (!RunAnywhere.getModelDownloader().isModelDownloaded(model)) {
                    println("📥 Downloading STT model: ${model.id}")

                    RunAnywhere.downloadModel(model.id).collect { progress ->
                        val percentage = (progress * 100).toInt()
                        if (percentage % 20 == 0) {
                            println("Download progress: $percentage%")
                        }

                        if (progress >= 1.0f) {
                            println("✅ Model downloaded and loaded: ${model.id}")
                        }
                    }
                } else {
                    // Load existing model
                    RunAnywhere.loadSTTModel(model)
                    println("✅ STT model loaded: ${model.id}")
                }
            }
        } catch (e: Exception) {
            println("❌ Failed to download STT model: ${e.message}")
        }
    }
}
