package com.runanywhere.plugin.services

import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import com.runanywhere.sdk.`public`.RunAnywhere
import com.runanywhere.sdk.`public`.extensions.transcribe
import com.runanywhere.sdk.features.stt.JvmAudioCaptureManager
import com.runanywhere.sdk.features.stt.AudioChunk
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * Service for managing voice capture and transcription using RunAnywhere SDK.
 *
 * Uses JvmAudioCaptureManager for audio capture and RunAnywhere.transcribe() for batch transcription.
 */
@Service(Service.Level.PROJECT)
class VoiceService(private val project: Project) : Disposable {

    private var isInitialized = false
    private var isRecording = false

    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        println("[VoiceService] Coroutine exception: ${throwable.message}")
    }
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob() + exceptionHandler)
    private var recordingJob: Job? = null
    private var audioCaptureManager: JvmAudioCaptureManager? = null

    fun initialize() {
        if (!isInitialized) {
            println("[VoiceService] Initializing...")
            isInitialized = true
        }
    }

    /**
     * Start voice capture with batch transcription.
     * Records audio, then transcribes when stopped.
     */
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
            println("[VoiceService] Already recording")
            return
        }

        isRecording = true
        val captureManager = JvmAudioCaptureManager()
        audioCaptureManager = captureManager

        showNotification(
            "Recording",
            "Voice recording started. Press stop to transcribe...",
            NotificationType.INFORMATION
        )

        recordingJob = scope.launch {
            val audioBuffer = mutableListOf<AudioChunk>()
            try {
                captureManager.startRecording().collect { chunk ->
                    audioBuffer.add(chunk)
                }
            } catch (_: CancellationException) {
                // Normal cancellation when stopping
            }

            // Transcribe accumulated audio
            if (audioBuffer.isNotEmpty()) {
                try {
                    val audioData = audioBuffer.flatMap { it.data.toList() }.toByteArray()
                    val text = RunAnywhere.transcribe(audioData)
                    if (text.isNotEmpty()) {
                        onTranscription(text)
                        showNotification("Transcribed", text, NotificationType.INFORMATION)
                    }
                } catch (e: Exception) {
                    println("[VoiceService] Transcription error: ${e.message}")
                    showNotification("STT Error", "Transcription failed: ${e.message}", NotificationType.ERROR)
                }
            }
        }
    }

    fun stopVoiceCapture() {
        if (!isRecording) {
            println("[VoiceService] Not recording")
            return
        }

        isRecording = false
        audioCaptureManager?.stopRecording()
        recordingJob?.cancel()
        recordingJob = null
        audioCaptureManager = null

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
        println("[VoiceService] Disposed")
    }
}
