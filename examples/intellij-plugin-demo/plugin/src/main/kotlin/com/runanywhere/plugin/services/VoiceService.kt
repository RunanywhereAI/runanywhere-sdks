package com.runanywhere.plugin.services

import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.components.stt.STTStreamEvent
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * Service for managing voice capture and transcription using RunAnywhere SDK
 *
 * This service is now deprecated in favor of directly using the SDK APIs:
 * - RunAnywhere.transcribeWithRecording() for simple recording
 * - RunAnywhere.startStreamingTranscription() for continuous streaming
 *
 * The SDK handles all audio capture internally.
 */
@Service(Service.Level.PROJECT)
class VoiceService(private val project: Project) : Disposable {

    private var isInitialized = false
    private var isRecording = false

    // Create a coroutine scope with proper exception handling for IntelliJ
    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        println("VoiceService: Coroutine exception: ${throwable.message}")
    }
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob() + exceptionHandler)
    private var streamingJob: Job? = null

    fun initialize() {
        if (!isInitialized) {
            println("VoiceService: Initializing...")
            isInitialized = true
        }
    }

    /**
     * Start voice capture with streaming transcription
     * @deprecated Use RunAnywhere.startStreamingTranscription() directly
     */
    @Deprecated("Use RunAnywhere.startStreamingTranscription() directly")
    fun startVoiceCapture(onTranscription: (String) -> Unit) {
        if (!com.runanywhere.plugin.isInitialized) {
            showNotification(
                "SDK not initialized",
                "Please wait for SDK initialization to complete",
                NotificationType.WARNING
            )
            return
        }

        if (isRecording) {
            println("Already recording")
            return
        }

        isRecording = true

        showNotification(
            "Recording",
            "Voice recording started. Speaking will be transcribed in real-time...",
            NotificationType.INFORMATION
        )

        // Start streaming transcription job using SDK's internal audio capture
        streamingJob = scope.launch {
            try {
                // Use SDK's internal audio capture and streaming transcription
                val transcriptionFlow = RunAnywhere.startStreamingTranscription(
                    chunkSizeMs = 100 // 100ms chunks for real-time feedback
                )

                // Collect transcription events
                transcriptionFlow
                    .catch { e ->
                        println("VoiceService: Streaming error: ${e.message}")
                        showNotification(
                            "Streaming Error",
                            "Failed during streaming: ${e.message}",
                            NotificationType.ERROR
                        )
                    }
                    .collect { event ->
                        when (event) {
                            is STTStreamEvent.SpeechStarted -> {
                                println("VoiceService: Speech detected, starting transcription...")
                            }

                            is STTStreamEvent.PartialTranscription -> {
                                println("VoiceService: Partial: ${event.text}")
                                // Show partial results in real-time
                                if (event.text.isNotEmpty()) {
                                    onTranscription("[Listening...] ${event.text}")
                                }
                            }

                            is STTStreamEvent.FinalTranscription -> {
                                val text = event.result.transcript
                                println("VoiceService: Final: $text")
                                if (text.isNotEmpty()) {
                                    onTranscription(text)
                                    showNotification(
                                        "Transcribed",
                                        text,
                                        NotificationType.INFORMATION
                                    )
                                }
                            }

                            is STTStreamEvent.SpeechEnded -> {
                                println("VoiceService: Speech ended")
                            }

                            is STTStreamEvent.SilenceDetected -> {
                                println("VoiceService: Silence detected")
                            }

                            is STTStreamEvent.Error -> {
                                println("VoiceService: Error: ${event.error.message}")
                                showNotification(
                                    "STT Error",
                                    event.error.message,
                                    NotificationType.ERROR
                                )
                            }

                            else -> {
                                // Handle other event types if needed
                                println("VoiceService: Event: $event")
                            }
                        }
                    }
            } catch (e: kotlinx.coroutines.CancellationException) {
                // This is normal when stopping recording
                println("VoiceService: Streaming cancelled (recording stopped)")
                throw e // Must rethrow CancellationException
            } catch (e: Exception) {
                println("VoiceService: Unexpected error: ${e.message}")
                e.printStackTrace()
                showNotification(
                    "Error",
                    "Unexpected error: ${e.message}",
                    NotificationType.ERROR
                )
            }
        }
    }

    fun stopVoiceCapture() {
        if (!isRecording) {
            println("Not recording")
            return
        }

        isRecording = false

        // Stop SDK's internal audio capture
        RunAnywhere.stopStreamingTranscription()

        // Cancel streaming job
        streamingJob?.cancel()
        streamingJob = null

        showNotification("Recording Stopped", "Voice capture ended", NotificationType.INFORMATION)
    }

    fun isRecording(): Boolean = isRecording

    private fun showNotification(title: String, content: String, type: NotificationType) {
        NotificationGroupManager.getInstance()
            .getNotificationGroup("RunAnywhere.Notifications")
            .createNotification(title, content, type)
            .notify(project)
    }

    override fun dispose() {
        if (isRecording) {
            stopVoiceCapture()
        }
        scope.cancel()
        println("VoiceService disposed")
    }
}
