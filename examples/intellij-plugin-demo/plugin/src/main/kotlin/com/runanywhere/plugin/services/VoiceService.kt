package com.runanywhere.plugin.services

import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
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
        if (!com.runanywhere.plugin.isInitialized) {
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

                showNotification("Processing", "Running VAD + WhisperKit STT pipeline... (${audioData.size} bytes)", NotificationType.INFORMATION)

                // Step 1: VAD preprocessing (optional - convert bytes to floats for VAD)
                val audioSamples = convertAudioToFloats(audioData)
                println("VoiceService: Converted to ${audioSamples.size} float samples")

                // Step 2: Apply VAD filtering if available
                val serviceContainer = com.runanywhere.sdk.foundation.ServiceContainer.shared
                val processedAudioData = try {
                    val vadComponent = serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.VAD)
                        as? com.runanywhere.sdk.components.vad.VADComponent

                    if (vadComponent != null && vadComponent.isEnabled()) {
                        println("VoiceService: Applying VAD filtering...")
                        val vadOutput = vadComponent.processAudioChunk(audioSamples)
                        println("VoiceService: VAD result - Speech: ${vadOutput.isSpeech}, Energy: ${vadOutput.energyLevel}, Confidence: ${vadOutput.confidence}")

                        if (vadOutput.isSpeech) {
                            // VAD detected speech, proceed with original audio
                            audioData
                        } else {
                            // VAD detected no speech, but still process for demo purposes
                            println("VoiceService: VAD detected no speech, but proceeding with transcription...")
                            audioData
                        }
                    } else {
                        println("VoiceService: VAD not available, using raw audio")
                        audioData
                    }
                } catch (e: Exception) {
                    println("VoiceService: VAD processing failed: ${e.message}, using raw audio")
                    audioData
                }

                // Step 3: Transcribe using SDK with WhisperKit
                val startTime = System.currentTimeMillis()
                val transcriptionText = RunAnywhere.transcribe(processedAudioData)
                val endTime = System.currentTimeMillis()
                val processingTime = endTime - startTime

                println("VoiceService: Transcription result: '$transcriptionText' (time: ${processingTime}ms)")

                // Step 4: Process results
                if (transcriptionText.isNotEmpty()) {
                    // Check if it's meaningful content
                    val meaningfulText = transcriptionText.trim().replace(Regex("[.!?\\s]+"), "")
                    if (meaningfulText.isNotEmpty()) {
                        println("VoiceService: Meaningful transcription found: '$transcriptionText'")
                        onTranscription(transcriptionText)
                        showNotification("STT Pipeline Complete",
                            "WhisperKit Result: $transcriptionText (${processingTime}ms)",
                            NotificationType.INFORMATION)
                    } else {
                        println("VoiceService: Only punctuation detected")
                        onTranscription("Only punctuation detected in audio")
                        showNotification("Low Quality Audio", "VAD + WhisperKit: Only punctuation detected", NotificationType.WARNING)
                    }
                } else {
                    println("VoiceService: Empty transcription result")
                    showNotification("No Speech", "VAD + WhisperKit: No speech detected", NotificationType.WARNING)
                }

            } catch (e: Exception) {
                println("VoiceService: STT pipeline error: ${e.message}")
                e.printStackTrace()
                showNotification("Pipeline Error", "VAD + WhisperKit pipeline failed: ${e.message}", NotificationType.ERROR)
            }
        }
    }

    /**
     * Convert 16-bit PCM audio bytes to float samples for VAD processing
     */
    private fun convertAudioToFloats(audioData: ByteArray): FloatArray {
        val samples = FloatArray(audioData.size / 2)
        var index = 0

        for (i in audioData.indices step 2) {
            if (i + 1 < audioData.size) {
                // Convert 16-bit PCM to float (-1.0 to 1.0)
                val sample = ((audioData[i + 1].toInt() shl 8) or (audioData[i].toInt() and 0xFF)).toShort()
                samples[index] = sample / 32768.0f
                index++
            }
        }

        return samples.sliceArray(0 until index)
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
