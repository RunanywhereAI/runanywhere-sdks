import com.runanywhere.sdk.public.RunAnywhereSTT
import com.runanywhere.sdk.public.STTSDKConfig
import com.runanywhere.sdk.events.TranscriptionEvent
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking

/**
 * Example usage of RunAnywhere STT SDK
 */
fun main() = runBlocking {
    println("RunAnywhere STT SDK Example")
    println("============================\n")

    // 1. Initialize the SDK with default configuration
    println("1. Initializing SDK...")
    RunAnywhereSTT.initialize()
    println("   ✓ SDK initialized\n")

    // 2. Check available models
    println("2. Available models:")
    val models = RunAnywhereSTT.getAvailableModels()
    models.forEach { model ->
        println("   - ${model.id}: ${model.size} (${model.description})")
    }
    println()

    // 3. Simple transcription
    println("3. Simple transcription:")
    val audioData = ByteArray(16000) // 1 second of audio at 16kHz
    val transcription = RunAnywhereSTT.transcribe(audioData)
    println("   Transcription: \"$transcription\"\n")

    // 4. Streaming transcription with VAD
    println("4. Streaming transcription:")
    val audioStream = flowOf(
        ByteArray(8000),  // 0.5 seconds
        ByteArray(8000),  // 0.5 seconds
        ByteArray(16000)  // 1 second
    )

    RunAnywhereSTT.transcribeStream(audioStream).collect { event ->
        when (event) {
            is TranscriptionEvent.SpeechStart ->
                println("   🎤 Speech started")

            is TranscriptionEvent.PartialTranscription ->
                println("   📝 Partial: ${event.text}")

            is TranscriptionEvent.FinalTranscription ->
                println("   ✅ Final: ${event.text}")

            is TranscriptionEvent.SpeechEnd ->
                println("   🔇 Speech ended")

            is TranscriptionEvent.Error ->
                println("   ❌ Error: ${event.error.message}")
        }
    }
    println()

    // 5. Custom configuration
    println("5. Custom configuration example:")
    RunAnywhereSTT.cleanup() // Clean up first

    val customConfig = STTSDKConfig(
        modelId = "whisper-small",
        enableVAD = true,
        language = "es",
        enableAnalytics = false
    )

    RunAnywhereSTT.initialize(customConfig)
    println("   ✓ Initialized with Spanish language and whisper-small model\n")

    // 6. Model download (if needed)
    println("6. Model management:")
    if (!RunAnywhereSTT.isModelAvailable("whisper-base")) {
        println("   Downloading whisper-base model...")
        RunAnywhereSTT.downloadModel("whisper-base")
        println("   ✓ Model downloaded")
    } else {
        println("   ✓ Model already available")
    }

    // Clean up
    println("\n7. Cleanup:")
    RunAnywhereSTT.cleanup()
    println("   ✓ SDK resources released")

    println("\n✨ Example completed successfully!")
}

/**
 * Example for Android application
 */
class AndroidExample {
    suspend fun voiceToText() {
        // Initialize once in your Application class
        RunAnywhereSTT.initialize(
            STTSDKConfig(
                modelId = "whisper-base",
                enableVAD = true,
                language = "en"
            )
        )

        // In your activity/fragment
        val audioRecorder = AudioRecorder() // Your audio recording implementation
        val audioFlow = audioRecorder.startRecording()

        RunAnywhereSTT.transcribeStream(audioFlow).collect { event ->
            when (event) {
                is TranscriptionEvent.FinalTranscription -> {
                    // Update UI with transcription
                    updateTextView(event.text)
                }

                is TranscriptionEvent.PartialTranscription -> {
                    // Show partial results
                    showPartialText(event.text)
                }

                else -> { /* Handle other events */
                }
            }
        }
    }

    // Mock functions for example
    private fun updateTextView(text: String) {}
    private fun showPartialText(text: String) {}
}

/**
 * Example for IntelliJ Plugin
 */
class IntelliJPluginExample {
    fun setupVoiceCommands(project: Project) {
        runBlocking {
            // Initialize SDK
            RunAnywhereSTT.initialize()

            // Start listening for voice commands
            val audioCapture = DesktopAudioCapture()
            val audioStream = audioCapture.startCapture()

            RunAnywhereSTT.transcribeStream(audioStream).collect { event ->
                if (event is TranscriptionEvent.FinalTranscription) {
                    processCommand(project, event.text)
                }
            }
        }
    }

    private fun processCommand(project: Project, command: String) {
        when {
            command.contains("run tests") -> runTests(project)
            command.contains("debug") -> startDebugger(project)
            command.contains("find usages") -> findUsages(project)
            else -> insertText(project, command)
        }
    }

    // Mock functions
    private fun runTests(project: Project) {}
    private fun startDebugger(project: Project) {}
    private fun findUsages(project: Project) {}
    private fun insertText(project: Project, text: String) {}
}

// Mock classes for examples
class AudioRecorder {
    fun startRecording() = flowOf(ByteArray(16000))
}

class DesktopAudioCapture {
    fun startCapture() = flowOf(ByteArray(16000))
}

class Project
