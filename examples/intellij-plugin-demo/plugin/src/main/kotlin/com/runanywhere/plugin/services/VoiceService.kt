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
                var totalAudioData = ByteArrayOutputStream()

                while (isRecording) {
                    val bytesRead = audioLine?.read(buffer, 0, buffer.size) ?: 0
                    if (bytesRead > 0) {
                        audioOutputStream.write(buffer, 0, bytesRead)
                        totalAudioData.write(buffer, 0, bytesRead)
                    }
                }

                // Recording stopped, process the audio
                val audioData = totalAudioData.toByteArray()
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
                println("VoiceService: Processing ${audioData.size} bytes of audio data")

                showNotification("Processing", "Transcribing audio with STT pipeline... (${audioData.size} bytes)", NotificationType.INFORMATION)

                // Transcribe using SDK
                val startTime = System.currentTimeMillis()
                val transcriptionText = RunAnywhere.transcribe(audioData)
                val endTime = System.currentTimeMillis()
                val processingTime = endTime - startTime

                println("VoiceService: Transcription result: '$transcriptionText' (time: ${processingTime}ms)")

                if (transcriptionText.isNotEmpty()) {
                    // Check if it's meaningful content
                    val meaningfulText = transcriptionText.trim().replace(Regex("[.!?\\s]+"), "")
                    if (meaningfulText.isNotEmpty()) {
                        println("VoiceService: Meaningful transcription found: '$transcriptionText'")
                        onTranscription(transcriptionText)
                        showNotification("Transcription Complete",
                            "Result: $transcriptionText",
                            NotificationType.INFORMATION)
                    } else {
                        println("VoiceService: Only punctuation detected")
                        onTranscription("Only punctuation detected in audio")
                        showNotification("Low Quality Audio", "Only punctuation detected", NotificationType.WARNING)
                    }
                } else {
                    println("VoiceService: Empty transcription result")
                    showNotification("No Speech", "No speech detected in audio", NotificationType.WARNING)
                }

            } catch (e: Exception) {
                println("VoiceService: Transcription error: ${e.message}")
                e.printStackTrace()
                showNotification("Transcription Error", "Failed to transcribe: ${e.message}", NotificationType.ERROR)
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
