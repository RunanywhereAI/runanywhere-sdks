package com.runanywhere.plugin

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.service
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.StartupActivity
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Main plugin startup activity
 */
class RunAnywherePlugin : StartupActivity {

    companion object {
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
                            // Initialize SDK with production mode and real API key
                            RunAnywhere.initialize(
                                apiKey = "your-actual-api-key-here", // TODO: Replace with actual API key
                                baseURL = "https://api.runanywhere.ai",
                                environment = SDKEnvironment.PRODUCTION
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
                println("🔍 Checking STT model: ${model.id}")

                if (!RunAnywhere.getModelDownloader().isModelDownloaded(model)) {
                    println("📥 Model not found locally. Downloading STT model: ${model.id}")

                    ApplicationManager.getApplication().invokeLater {
                        println("⏳ Starting download for model: ${model.id}")
                    }

                    RunAnywhere.downloadModel(model.id).collect { progress ->
                        val percentage = (progress * 100).toInt()
                        if (percentage % 10 == 0 || percentage == 100) {
                            ApplicationManager.getApplication().invokeLater {
                                println("📊 Download progress: $percentage%")
                            }
                        }

                        if (progress >= 1.0f) {
                            ApplicationManager.getApplication().invokeLater {
                                println("✅ Model downloaded successfully: ${model.id}")
                                println("🔄 Model is being loaded automatically...")
                            }
                        }
                    }
                } else {
                    // Model already downloaded, just load it
                    println(
                        "✓ Model already downloaded at: ${
                            RunAnywhere.getModelDownloader().getModelPath(model)
                        }"
                    )

                    // Check if already loaded
                    if (RunAnywhere.getLoadedSTTModel()?.id != model.id) {
                        println("🔄 Loading existing model into memory...")
                        RunAnywhere.loadSTTModel(model)
                        ApplicationManager.getApplication().invokeLater {
                            println("✅ STT model loaded from disk: ${model.id}")
                        }
                    } else {
                        ApplicationManager.getApplication().invokeLater {
                            println("✅ STT model already loaded in memory: ${model.id}")
                        }
                    }
                }

                // Verify pipeline is ready
                if (RunAnywhere.isSTTPipelineReady()) {
                    ApplicationManager.getApplication().invokeLater {
                        println("🎤 STT pipeline is ready for voice transcription!")
                    }
                }
            } ?: run {
                println("⚠️ No STT model found in available models list")
            }
        } catch (e: Exception) {
            ApplicationManager.getApplication().invokeLater {
                println("❌ Failed to initialize STT model: ${e.message}")
                e.printStackTrace()
            }
        }
    }
}
