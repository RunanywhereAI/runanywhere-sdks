# RunAnywhere SDK Integration Guide for IntelliJ/Android Studio Plugins

This guide demonstrates how to integrate the RunAnywhere Kotlin SDK into IntelliJ/Android Studio plugins for speech-to-text functionality.

## Table of Contents
1. [Project Setup](#project-setup)
2. [SDK Configuration](#sdk-configuration)
3. [Voice Service Implementation](#voice-service-implementation)
4. [UI Components](#ui-components)
5. [Model Management](#model-management)
6. [Enhanced Sensitivity Controls](#enhanced-sensitivity-controls)
7. [Testing & Debugging](#testing--debugging)
8. [Best Practices](#best-practices)

## Project Setup

### 1. Plugin Dependencies

Add the RunAnywhere SDK dependency to your plugin's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
    implementation("io.github.givimad:whisper-jni:1.7.1")

    // Plugin development dependencies
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.20")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.7.3")
}
```

### 2. Plugin Structure

```
src/main/kotlin/com/yourcompany/plugin/
├── YourPlugin.kt                  # Main plugin class
├── services/
│   └── VoiceService.kt           # Audio capture and transcription
└── toolwindow/
    └── STTToolWindow.kt          # UI for STT functionality
```

## SDK Configuration

### 1. Plugin Initialization

```kotlin
@Service(Service.Level.PROJECT)
class YourPlugin(private val project: Project) : Disposable {

    companion object {
        private val logger = SDKLogger("YourPlugin")
        var isInitialized = false
            private set
    }

    suspend fun initializeSDK() {
        if (isInitialized) return

        try {
            // Initialize SDK in development mode for plugin testing
            RunAnywhere.initialize(
                apiKey = "", // Empty for development mode
                baseURL = null,
                environment = SDKEnvironment.DEVELOPMENT
            )

            isInitialized = true
            logger.info("RunAnywhere SDK initialized successfully")

            // Check for available models and load if downloaded
            checkAndLoadSTTModel(project)

        } catch (e: Exception) {
            logger.error("Failed to initialize RunAnywhere SDK", e)
            showNotification(project, "SDK Error",
                "Failed to initialize RunAnywhere SDK: ${e.message}",
                NotificationType.ERROR)
        }
    }

    private suspend fun checkAndLoadSTTModel(project: Project) {
        try {
            val models = RunAnywhere.availableModels()
                .filter { it.category == ModelCategory.SPEECH_RECOGNITION }

            val downloader = RunAnywhere.getModelDownloader()
            val downloadedModels = models.filter { downloader.isModelDownloaded(it) }

            if (downloadedModels.isNotEmpty()) {
                val modelToLoad = downloadedModels.find { it.id == "whisper-tiny" }
                    ?: downloadedModels.find { it.id == "whisper-base" }
                    ?: downloadedModels.first()
                loadModelIntoWhisper(project, modelToLoad)
            } else {
                showNotification(project, "Models Available",
                    "STT models available for download. Open tool window to download.",
                    NotificationType.INFORMATION)
            }
        } catch (e: Exception) {
            logger.error("Failed to check STT models", e)
        }
    }

    override fun dispose() {
        // Cleanup resources
    }
}
```

### 2. Service Registration

Register your service in `plugin.xml`:

```xml
<extensions defaultExtensionNs="com.intellij">
    <projectService serviceImplementation="com.yourcompany.plugin.YourPlugin"/>
    <projectService serviceImplementation="com.yourcompany.plugin.services.VoiceService"/>

    <toolWindow id="YourPlugin STT"
                secondary="false"
                icon="/icons/microphone.svg"
                anchor="right"
                factoryClass="com.yourcompany.plugin.toolwindow.STTToolWindowFactory"/>
</extensions>
```

## Voice Service Implementation

### 1. Audio Capture Service

```kotlin
@Service(Service.Level.PROJECT)
class VoiceService(private val project: Project) : Disposable {

    private var isRecording = false
    private var audioLine: TargetDataLine? = null
    private var recordingThread: Thread? = null
    private val audioOutputStream = ByteArrayOutputStream()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Audio format: 16kHz, 16-bit, mono - standard for STT
    private val audioFormat = AudioFormat(
        16000f,  // Sample rate
        16,      // Sample size in bits
        1,       // Channels (mono)
        true,    // Signed
        false    // Big endian
    )

    fun startVoiceCapture(onTranscription: (String) -> Unit) {
        if (!YourPlugin.isInitialized) {
            showNotification("SDK not initialized",
                "Please wait for SDK initialization to complete",
                NotificationType.WARNING)
            return
        }

        if (!RunAnywhere.isSTTPipelineReady()) {
            showNotification("STT not ready",
                "STT model is not loaded. Please wait...",
                NotificationType.WARNING)
            return
        }

        if (isRecording) return

        try {
            val dataLineInfo = DataLine.Info(TargetDataLine::class.java, audioFormat)
            if (!AudioSystem.isLineSupported(dataLineInfo)) {
                showNotification("Audio Error",
                    "Audio recording not supported on this system",
                    NotificationType.ERROR)
                return
            }

            audioLine = AudioSystem.getLine(dataLineInfo) as TargetDataLine
            audioLine?.open(audioFormat)
            audioLine?.start()

            isRecording = true
            audioOutputStream.reset()

            showNotification("Recording", "Voice recording started. Speak now...",
                NotificationType.INFORMATION)

            recordingThread = thread {
                val buffer = ByteArray(4096)
                while (isRecording) {
                    val bytesRead = audioLine?.read(buffer, 0, buffer.size) ?: 0
                    if (bytesRead > 0) {
                        audioOutputStream.write(buffer, 0, bytesRead)
                    }
                }

                val audioData = audioOutputStream.toByteArray()
                if (audioData.isNotEmpty()) {
                    processAudioData(audioData, onTranscription)
                }
            }

        } catch (e: Exception) {
            showNotification("Recording Error",
                "Failed to start recording: ${e.message}",
                NotificationType.ERROR)
        }
    }

    private fun processAudioData(audioData: ByteArray, onTranscription: (String) -> Unit) {
        scope.launch {
            try {
                // Use enhanced sensitivity transcription
                val transcription = RunAnywhere.transcribeSensitive(audioData)

                if (transcription.isNotEmpty()) {
                    val meaningfulText = transcription.trim().replace(Regex("[.!?\\s]+"), "")
                    if (meaningfulText.isNotEmpty()) {
                        onTranscription(transcription)
                        showNotification("Transcription Complete", transcription,
                            NotificationType.INFORMATION)
                    } else {
                        val message = "Only punctuation detected. Try speaking louder."
                        onTranscription(message)
                        showNotification("Low Audio Quality", message,
                            NotificationType.WARNING)
                    }
                } else {
                    showNotification("No Speech", "No speech detected in the recording",
                        NotificationType.WARNING)
                }
            } catch (e: Exception) {
                showNotification("Transcription Error",
                    "Failed to transcribe: ${e.message}",
                    NotificationType.ERROR)
            }
        }
    }
}
```

## UI Components

### 1. Tool Window Implementation

```kotlin
class STTToolWindow(private val project: Project) {

    private lateinit var mainPanel: JPanel
    private lateinit var modelsList: JList<ModelDisplayInfo>
    private lateinit var recordButton: JButton
    private lateinit var transcriptionArea: JTextArea
    private lateinit var logArea: JTextArea

    fun createContent(): JComponent {
        mainPanel = JPanel(BorderLayout())

        // Model Management Section
        val modelPanel = createModelManagementPanel()
        mainPanel.add(modelPanel, BorderLayout.NORTH)

        // Recording Controls Section
        val controlPanel = createRecordingControlPanel()
        mainPanel.add(controlPanel, BorderLayout.CENTER)

        // Transcription & Logging Section
        val outputPanel = createOutputPanel()
        mainPanel.add(outputPanel, BorderLayout.SOUTH)

        // Initialize UI state
        refreshModelsList()

        return mainPanel
    }

    private fun createModelManagementPanel(): JPanel {
        val panel = JPanel(BorderLayout())
        panel.border = BorderFactory.createTitledBorder("STT Models")

        // Models list with status
        modelsList = JList<ModelDisplayInfo>()
        modelsList.cellRenderer = ModelListCellRenderer()

        val scrollPane = JScrollPane(modelsList)
        scrollPane.preferredSize = Dimension(400, 150)
        panel.add(scrollPane, BorderLayout.CENTER)

        // Action buttons
        val buttonPanel = JPanel(FlowLayout())

        val downloadButton = JButton("Download Selected")
        downloadButton.addActionListener { downloadSelectedModel() }

        val loadButton = JButton("Load Selected")
        loadButton.addActionListener { loadSelectedModel() }

        val refreshButton = JButton("Refresh")
        refreshButton.addActionListener { refreshModelsList() }

        buttonPanel.add(downloadButton)
        buttonPanel.add(loadButton)
        buttonPanel.add(refreshButton)

        panel.add(buttonPanel, BorderLayout.SOUTH)

        return panel
    }

    private fun refreshModelsList() {
        GlobalScope.launch(Dispatchers.IO) {
            try {
                if (!YourPlugin.isInitialized) {
                    logToUI("WARN", "SDK not initialized yet")
                    return@launch
                }

                val models = RunAnywhere.availableModels()
                    .filter { it.category == ModelCategory.SPEECH_RECOGNITION }

                val downloader = RunAnywhere.getModelDownloader()
                val loadedModel = RunAnywhere.getLoadedSTTModel()

                val displayModels = models.map { model ->
                    val isDownloaded = downloader.isModelDownloaded(model)
                    val isLoaded = loadedModel?.id == model.id

                    ModelDisplayInfo(
                        model = model,
                        isDownloaded = isDownloaded,
                        isLoaded = isLoaded,
                        sizeMB = when(model.id) {
                            "whisper-tiny" -> "77"
                            "whisper-base" -> "142"
                            "whisper-small" -> "488"
                            else -> "Unknown"
                        }
                    )
                }

                SwingUtilities.invokeLater {
                    val listModel = DefaultListModel<ModelDisplayInfo>()
                    displayModels.forEach { listModel.addElement(it) }
                    modelsList.model = listModel

                    logToUI("INFO", "Found ${models.size} STT models")
                }

            } catch (e: Exception) {
                logToUI("ERROR", "Failed to refresh models: ${e.message}")
            }
        }
    }
}

// Data class for model display
data class ModelDisplayInfo(
    val model: ModelInfo,
    val isDownloaded: Boolean,
    val isLoaded: Boolean,
    val sizeMB: String
) {
    override fun toString(): String {
        val statusText = when {
            isLoaded -> "✅ Loaded in memory (${sizeMB}MB)"
            isDownloaded -> "💾 Downloaded, ready to load (${sizeMB}MB)"
            else -> "📥 Available for download (${sizeMB}MB)"
        }
        return "${model.displayName ?: model.id} - $statusText"
    }
}
```

## Model Management

### 1. Model Download and Loading

```kotlin
private fun downloadSelectedModel() {
    val selectedModel = modelsList.selectedValue?.model ?: return

    GlobalScope.launch(Dispatchers.IO) {
        try {
            logToUI("INFO", "Starting download of ${selectedModel.id}...")

            RunAnywhere.downloadModel(selectedModel.id).collect { progress ->
                SwingUtilities.invokeLater {
                    val percentage = (progress * 100).toInt()
                    logToUI("INFO", "Download progress: $percentage%")
                }
            }

            SwingUtilities.invokeLater {
                logToUI("INFO", "Download completed for ${selectedModel.id}")
                refreshModelsList()
            }

        } catch (e: Exception) {
            logToUI("ERROR", "Download failed: ${e.message}")
        }
    }
}

private fun loadSelectedModel() {
    val selectedModelInfo = modelsList.selectedValue ?: return
    val model = selectedModelInfo.model

    if (!selectedModelInfo.isDownloaded) {
        logToUI("WARN", "Model ${model.id} is not downloaded yet")
        return
    }

    GlobalScope.launch(Dispatchers.IO) {
        try {
            logToUI("INFO", "Loading model ${model.id}...")

            RunAnywhere.loadSTTModel(model)

            SwingUtilities.invokeLater {
                logToUI("INFO", "Model ${model.id} loaded successfully")
                refreshModelsList()
            }

        } catch (e: Exception) {
            logToUI("ERROR", "Failed to load model: ${e.message}")
        }
    }
}
```

## Enhanced Sensitivity Controls

### 1. Using Sensitive Transcription

The SDK provides enhanced sensitivity controls for better transcription of quiet or unclear speech:

```kotlin
// Standard transcription
val transcription = RunAnywhere.transcribe(audioData)

// Enhanced sensitivity transcription (recommended)
val sensitiveTranscription = RunAnywhere.transcribeSensitive(audioData)

// Custom sensitivity options
val customOptions = STTOptions(
    language = "en",
    detectLanguage = false,
    enablePunctuation = true,
    enableTimestamps = true,
    sensitivityMode = STTSensitivityMode.HIGH,
    beamSize = 10,
    temperature = 0.3f,
    suppressBlank = false,
    suppressNonSpeechTokens = false
)
val customTranscription = RunAnywhere.transcribeWithOptions(audioData, customOptions)
```

### 2. Sensitivity Modes

- **NORMAL**: Standard sensitivity for clear speech
- **HIGH**: Better for quiet or unclear speech
- **MAXIMUM**: For very quiet or distant speech

### 3. Audio Quality Analysis

```kotlin
private fun analyzeAudioLevels(audioData: ByteArray): AudioLevels {
    if (audioData.size < 2) return AudioLevels(0, 0.0, 0.0, false)

    var maxLevel = 0
    var sumSquares = 0.0
    var sum = 0.0
    val sampleCount = audioData.size / 2

    for (i in 0 until audioData.size - 1 step 2) {
        val sample = ((audioData[i + 1].toInt() shl 8) or
                     (audioData[i].toInt() and 0xFF)).toShort().toInt()
        val absSample = kotlin.math.abs(sample)

        maxLevel = kotlin.math.max(maxLevel, absSample)
        sum += absSample
        sumSquares += sample * sample
    }

    val average = sum / sampleCount
    val rms = kotlin.math.sqrt(sumSquares / sampleCount)
    val hasSignificantAudio = maxLevel > 1000 && rms > 500

    return AudioLevels(maxLevel, average, rms, hasSignificantAudio)
}
```

## Testing & Debugging

### 1. Logging Setup

```kotlin
private fun logToUI(level: String, message: String) {
    SwingUtilities.invokeLater {
        val timestamp = SimpleDateFormat("HH:mm:ss.SSS").format(Date())
        val logLine = "[$timestamp] $level: $message\n"
        logArea.append(logLine)
        logArea.caretPosition = logArea.document.length
    }
}
```

### 2. Using SDK Debug Script

```bash
# Build and run plugin with debug logging
./sdk/runanywhere-kotlin/scripts/sdk.sh run-plugin-as --debug
```

### 3. Common Issues and Solutions

**Issue**: Models not showing in UI
- **Solution**: Check if SDK is initialized and use proper dispatchers

**Issue**: "." punctuation only in transcription
- **Solution**: Use `transcribeSensitive()` and check audio levels

**Issue**: WhisperJNI initialization errors
- **Solution**: Ensure model files are properly downloaded and accessible

## Best Practices

### 1. Threading
- Always use `SwingUtilities.invokeLater` for UI updates from background threads
- Use appropriate coroutine dispatchers (`Dispatchers.IO` for network/file operations)

### 2. Resource Management
- Properly dispose of audio resources in service disposal
- Cancel coroutine scopes when services are disposed

### 3. Error Handling
- Provide user-friendly error messages via notifications
- Log detailed errors for debugging
- Gracefully handle SDK initialization failures

### 4. Performance
- Only load models when needed
- Use background threads for long-running operations
- Implement proper cancellation for downloads

### 5. User Experience
- Show clear model status indicators
- Provide progress feedback for downloads
- Use meaningful notification messages

## Example Project Structure

```
examples/intellij-plugin-demo/
├── plugin/
│   ├── build.gradle.kts
│   ├── src/main/
│   │   ├── kotlin/com/runanywhere/plugin/
│   │   │   ├── RunAnywherePlugin.kt
│   │   │   ├── services/VoiceService.kt
│   │   │   └── toolwindow/STTToolWindow.kt
│   │   └── resources/
│   │       ├── META-INF/plugin.xml
│   │       └── icons/microphone.svg
│   └── scripts/
└── README.md
```

This integration guide provides a complete foundation for adding RunAnywhere SDK speech-to-text functionality to any IntelliJ/Android Studio plugin. The example code can be adapted for different use cases while maintaining the core patterns demonstrated.
