package com.runanywhere.plugin.services

import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import com.runanywhere.plugin.RunAnywherePlugin
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import javax.sound.sampled.*
import kotlin.concurrent.thread

/**
 * Service for managing voice capture and transcription using RunAnywhere SDK
 */
@Service(Service.Level.PROJECT)
class VoiceService(private val project: Project) : Disposable {

    private var isInitialized = false
    private var isRecording = false
    private var audioLine: TargetDataLine? = null
    private var recordingThread: Thread? = null
    private val audioOutputStream = ByteArrayOutputStream()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Audio format for recording (16kHz, 16-bit, mono - standard for STT)
    private val audioFormat = AudioFormat(
        16000f,  // Sample rate
        16,      // Sample size in bits
        1,       // Channels (mono)
        true,    // Signed
        false    // Big endian
    )

    fun initialize() {
        if (!isInitialized) {
            println("VoiceService: Initializing audio components...")
            isInitialized = true
        }
    }

    fun startVoiceCapture(onTranscription: (String) -> Unit) {
        if (!RunAnywherePlugin.isInitialized) {
            showNotification("SDK not initialized", "Please wait for SDK initialization to complete", NotificationType.WARNING)
            return
        }

        if (!RunAnywhere.isSTTPipelineReady()) {
            showNotification("STT not ready", "STT model is not loaded. Please wait...", NotificationType.WARNING)
            return
        }

        if (isRecording) {
            println("Already recording")
            return
        }

        try {
            // Get audio line
            val dataLineInfo = DataLine.Info(TargetDataLine::class.java, audioFormat)
            if (!AudioSystem.isLineSupported(dataLineInfo)) {
                showNotification("Audio Error", "Audio recording not supported on this system", NotificationType.ERROR)
                return
            }

            audioLine = AudioSystem.getLine(dataLineInfo) as TargetDataLine
            audioLine?.open(audioFormat)
            audioLine?.start()

            isRecording = true
            audioOutputStream.reset()

            showNotification("Recording", "Voice recording started. Speak now...", NotificationType.INFORMATION)

            // Start recording in separate thread
            recordingThread = thread {
                val buffer = ByteArray(4096)

                while (isRecording) {
                    val bytesRead = audioLine?.read(buffer, 0, buffer.size) ?: 0
                    if (bytesRead > 0) {
                        audioOutputStream.write(buffer, 0, bytesRead)
                    }
                }

                // Recording stopped, process the audio
                val audioData = audioOutputStream.toByteArray()
                if (audioData.isNotEmpty()) {
                    processAudioData(audioData, onTranscription)
                }
            }

        } catch (e: Exception) {
            showNotification("Recording Error", "Failed to start recording: ${e.message}", NotificationType.ERROR)
            e.printStackTrace()
        }
    }

    fun stopVoiceCapture() {
        if (!isRecording) {
            println("Not recording")
            return
        }

        isRecording = false

        // Stop and close audio line
        audioLine?.stop()
        audioLine?.close()
        audioLine = null

        // Wait for recording thread to finish
        recordingThread?.join(1000)
        recordingThread = null

        showNotification("Recording Stopped", "Processing audio...", NotificationType.INFORMATION)
    }

    private fun processAudioData(audioData: ByteArray, onTranscription: (String) -> Unit) {
        scope.launch {
            try {
                showNotification("Processing", "Transcribing audio...", NotificationType.INFORMATION)

                // Use SDK to transcribe
                val transcription = RunAnywhere.transcribe(audioData)

                if (transcription.isNotEmpty()) {
                    withContext(Dispatchers.Main) {
                        onTranscription(transcription)
                        showNotification("Transcription Complete", transcription, NotificationType.INFORMATION)
                    }
                } else {
                    showNotification("No Speech", "No speech detected in the recording", NotificationType.WARNING)
                }

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    showNotification("Transcription Error", "Failed to transcribe: ${e.message}", NotificationType.ERROR)
                }
                e.printStackTrace()
            }
        }
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
