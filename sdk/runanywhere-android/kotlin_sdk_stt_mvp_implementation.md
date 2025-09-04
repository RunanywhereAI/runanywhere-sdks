# Android SDK - STT Pipeline Implementation Plan (Updated)

## Executive Summary

This document outlines the comprehensive implementation plan for the RunAnywhere Android SDK, focusing on the Speech-to-Text (STT) pipeline with Voice Activity Detection (VAD). The architecture is designed to mirror the iOS SDK while following modern Android development patterns, with full integration into the sample Android app.

## Implementation Status: 70% Complete

### Completed Components

- Core SDK architecture and foundation
- Service Container with dependency injection
- Event-driven architecture with EventBus
- STT and VAD component abstractions
- Service providers for component creation
- Model management infrastructure
- File management system
- Configuration and initialization flow

### In Progress

- JNI integration for Whisper.cpp
- WebRTC VAD native implementation
- Sample app integration

### Remaining Work

- Production HTTP download implementation
- Database persistence layer
- Sample Android app UI
- Integration tests
- Performance optimization

## Key Architectural Updates Based on iOS SDK Analysis

Following comprehensive analysis of the iOS SDK architecture and existing Android SDK structure, this plan has been updated to ensure full architectural parity while maintaining Android-specific best practices:

### Architecture Alignment with iOS SDK

- **Three-layer clean architecture**: Components → Services → Adapters (matching iOS patterns)
- **Service Container pattern**: Central dependency injection with lazy initialization
- **Event-driven communication**: Flow-based events matching iOS Combine patterns
- **Configuration management**: Multi-source configuration with fallback chain
- **Mock service ecosystem**: Complete development mode support (Removed - keeping it simple)
- **Strong typing**: Comprehensive data models and sealed classes
- **Modern patterns**: Kotlin coroutines, Flow/StateFlow, Compose UI

### Target Integration
- **Android Sample App**: Primary integration target (not Android Studio plugin)
- **Production-ready SDK**: Complete SDK implementation with all necessary services
- **Development mode**: Full mock service support for offline development

## 1. Implementation Scope

### Core SDK Implementation

- **RunAnywhere Object**: Main SDK entry point with initialization
- **Service Container**: Dependency injection and service management
- **Configuration System**: Remote/local/default configuration chain
- **Database Layer**: Room/SQLite persistence with migrations (Basic structure, needs Room
  implementation)
- **Model Management**: Registry, loading, downloading with progress
- **Event System**: Flow-based event-driven architecture
- **File Management**: Organized storage with cleanup
- **Analytics Service**: STT-specific usage and performance tracking (Basic implementation)

### STT Pipeline Components

- **VAD Component**: WebRTC VAD with lifecycle management
- **STT Component**: Whisper.cpp integration via JNI (Structure ready, needs JNI)
- **Audio Processing**: Stream processing with VAD integration
- **Native Integration**: JNI wrappers for whisper.cpp and WebRTC VAD (Pending)
- **Mock Services**: Complete development mode ecosystem (Removed for simplicity)

### Sample App Integration

- **MainActivity**: SDK initialization and event subscription
- **TranscriptionScreen**: Compose UI for real-time STT
- **ViewModels**: State management with Flow/StateFlow
- **Permission Handling**: Audio recording permissions
- **Real-time Updates**: Live transcription with partial/final results

### Development Infrastructure

- **Mock Models**: Matching iOS mock model catalog (In MockNetworkService)
- **Development Mode**: Offline operation with mock services
- **Testing Framework**: Unit and integration tests (Pending)
- **Build System**: Gradle configuration with native libraries (Pending)

## 2. Target Use Case: Android Sample App STT Integration

### Primary Features
1. **Real-time Transcription**: Live speech-to-text with visual feedback
2. **Voice Activity Detection**: Smart start/stop with VAD integration
3. **Model Management**: Download and switch between Whisper models
4. **Development Mode**: Offline operation with mock services
5. **Analytics Tracking**: Usage metrics and performance monitoring

### User Experience Flow
```
1. User opens transcription screen in sample app
2. Taps record button to start listening
3. VAD detects speech and shows visual feedback
4. Real-time partial transcription appears
5. VAD detects speech end
6. Final transcription result displayed
7. Process repeats for continuous transcription
```

### Integration Points with iOS Sample App
- **Matching UI patterns**: Similar transcription interface design
- **Event handling**: Same event types and flow
- **Model management**: Consistent model selection and loading
- **Development mode**: Same mock service behavior
- **Analytics tracking**: Matching event tracking patterns

## 3. Android SDK Architecture

### 3.1 Project Structure

```
sdk/runanywhere-android/
├── core/                                    # Core SDK module
│   ├── src/main/kotlin/com/runanywhere/sdk/
│   │   ├── public/                         # Public API
│   │   │   ├── RunAnywhere.kt             # Main SDK entry point
│   │   │   ├── Configuration.kt           # Configuration classes
│   │   │   └── Events.kt                  # Public event definitions
│   │   ├── foundation/                     # Core infrastructure
│   │   │   ├── ServiceContainer.kt        # DI container
│   │   │   ├── EventBus.kt               # Event system
│   │   │   └── SDKLogger.kt              # Logging system
│   │   ├── components/                     # Component layer
│   │   │   ├── base/                      # Base abstractions
│   │   │   │   ├── BaseComponent.kt      # Component lifecycle
│   │   │   │   ├── Component.kt          # Interface definitions
│   │   │   │   └── ComponentConfiguration.kt
│   │   │   ├── stt/                       # STT component
│   │   │   │   ├── STTComponent.kt       # STT component impl
│   │   │   │   ├── STTService.kt         # STT service interface
│   │   │   │   ├── WhisperCppSTTService.kt # Whisper impl
│   │   │   │   └── STTModels.kt          # STT data models
│   │   │   └── vad/                       # VAD component
│   │   │       ├── VADComponent.kt       # VAD component impl
│   │   │       ├── VADService.kt         # VAD service interface
│   │   │       ├── WebRTCVADService.kt   # WebRTC impl
│   │   │       └── VADModels.kt          # VAD data models
│   │   ├── services/                       # Service layer
│   │   │   ├── configuration/             # Configuration management
│   │   │   │   ├── ConfigurationService.kt
│   │   │   │   ├── ConfigurationRepository.kt
│   │   │   │   ├── RemoteDataSource.kt
│   │   │   │   └── LocalDataSource.kt
│   │   │   ├── models/                    # Model management
│   │   │   │   ├── ModelRegistry.kt      # Model discovery
│   │   │   │   ├── ModelLoadingService.kt # Model loading
│   │   │   │   ├── DownloadService.kt    # File downloads
│   │   │   │   └── MemoryService.kt      # Memory management
│   │   │   ├── network/                   # Network services
│   │   │   │   ├── NetworkService.kt     # Network interface
│   │   │   │   ├── MockNetworkService.kt # Mock implementation
│   │   │   │   └── HttpNetworkService.kt # Production impl
│   │   │   └── analytics/                 # Analytics services
│   │   │       ├── AnalyticsService.kt   # Analytics interface
│   │   │       ├── STTAnalyticsService.kt # STT analytics
│   │   │       └── AnalyticsQueueManager.kt
│   │   ├── data/                          # Data layer
│   │   │   ├── database/                  # Database components
│   │   │   │   ├── RunAnywhereDatabase.kt # Room database
│   │   │   │   ├── ConfigurationDao.kt   # Configuration DAO
│   │   │   │   ├── ModelDao.kt           # Model DAO
│   │   │   │   └── AnalyticsDao.kt       # Analytics DAO
│   │   │   ├── models/                    # Data models
│   │   │   │   ├── ConfigurationData.kt  # Configuration entity
│   │   │   │   ├── ModelInfo.kt          # Model entity
│   │   │   │   └── AnalyticsEvent.kt     # Analytics entity
│   │   │   └── converters/                # Type converters
│   │   │       └── DatabaseConverters.kt
│   │   └── files/                         # File management
│   │       ├── FileManager.kt            # File operations
│   │       └── StorageInfo.kt            # Storage utilities
│   ├── src/main/assets/                   # Assets
│   │   └── models/                        # Bundled model files
│   └── src/test/                          # Unit tests
├── jni/                                   # JNI module
│   ├── src/main/kotlin/                   # JNI Kotlin wrappers
│   │   ├── WhisperJNI.kt                 # Whisper JNI wrapper
│   │   └── WebRTCVadJNI.kt              # VAD JNI wrapper
│   ├── src/main/cpp/                      # Native C++ code
│   │   ├── whisper-jni.cpp               # Whisper JNI implementation
│   │   ├── webrtc-vad-jni.cpp           # VAD JNI implementation
│   │   └── jni-common.h                  # Common JNI utilities
│   └── CMakeLists.txt                     # CMake build configuration
└── examples/android/RunAnywhereAI/        # Sample application
    └── [Sample app integration code]
```

### 3.2 Core SDK Implementation

#### RunAnywhere Object (Main Entry Point)

```kotlin
object RunAnywhere {
    private var _isInitialized = AtomicBoolean(false)
    private var _currentEnvironment: SDKEnvironment? = null

    val serviceContainer: ServiceContainer get() = ServiceContainer.shared
    val eventBus: EventBus get() = EventBus.shared

    suspend fun initialize(
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.PRODUCTION
    ) {
        if (_isInitialized.get()) return

        _currentEnvironment = environment

        // 8-step initialization process (matching iOS)
        EventBus.shared.publish(SDKInitializationEvent.Started)

        try {
            // Step 1-4: Basic setup
            initializeLogging()
            initializeDatabase()
            storeCredentials(apiKey, baseURL)

            // Step 5-7: Environment-specific bootstrap
            val configData = if (environment == SDKEnvironment.DEVELOPMENT) {
                serviceContainer.bootstrapDevelopmentMode(SDKInitParams(apiKey, baseURL, environment))
            } else {
                val authService = serviceContainer.authenticationService
                serviceContainer.bootstrap(SDKInitParams(apiKey, baseURL, environment), authService)
            }

            // Step 8: Mark as initialized
            _isInitialized.set(true)
            EventBus.shared.publish(SDKInitializationEvent.Completed)

        } catch (e: Exception) {
            EventBus.shared.publish(SDKInitializationEvent.Failed(e))
            throw e
        }
    }

    suspend fun loadModel(modelId: String): LoadedModel {
        return serviceContainer.modelLoadingService.loadModel(modelId)
    }

    suspend fun availableModels(): List<ModelInfo> {
        return serviceContainer.modelRegistry.discoverModels()
    }

    suspend fun createVoicePipeline(config: VoicePipelineConfig): VoicePipeline {
        // Create coordinated voice pipeline with STT and VAD components
        return VoicePipelineImpl(
            sttComponent = serviceContainer.sttComponent,
            vadComponent = serviceContainer.vadComponent,
            config = config
        )
    }
}
```

#### Configuration Management System

```kotlin
// Multi-source configuration with fallback chain (matching iOS)
data class ConfigurationData(
    val id: String,
    val apiKey: String,
    val baseURL: String,
    val environment: SDKEnvironment,
    val source: ConfigurationSource,
    val lastUpdated: Long,

    // Nested configurations
    val routing: RoutingConfiguration,
    val generation: GenerationConfiguration,
    val storage: StorageConfiguration,
    val api: APIConfiguration,
    val download: ModelDownloadConfiguration,
    val hardware: HardwareConfiguration?
) {
    companion object {
        fun defaultConfiguration(apiKey: String): ConfigurationData {
            return ConfigurationData(
                id = "default",
                apiKey = apiKey,
                baseURL = "https://api.runanywhere.ai",
                environment = SDKEnvironment.DEVELOPMENT,
                source = ConfigurationSource.DEFAULTS,
                lastUpdated = System.currentTimeMillis(),
                routing = RoutingConfiguration.defaults(),
                generation = GenerationConfiguration.defaults(),
                storage = StorageConfiguration.defaults(),
                api = APIConfiguration.defaults(),
                download = ModelDownloadConfiguration.defaults(),
                hardware = null
            )
        }
    }
}

class ConfigurationService(
    private val repository: ConfigurationRepository
) {
    suspend fun loadConfigurationOnLaunch(apiKey: String): ConfigurationData {
        // Priority chain: Remote → Database → Consumer → Defaults
        return repository.fetchRemoteConfiguration(apiKey)
            ?: repository.getLocalConfiguration()
            ?: ConfigurationData.defaultConfiguration(apiKey)
    }
}
```

#### Mock Network Service (Development Mode)

```kotlin
// Matches iOS MockNetworkService with same model catalog
class MockNetworkService : NetworkService {
    companion object {
        fun getMockModels(): List<ModelInfo> = listOf(
            // Whisper Models (matching iOS exactly)
            ModelInfo(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.WHISPER_CPP,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
                localPath = null,
                downloadSize = 39_000_000L,
                memoryRequired = 39_000_000L,
                compatibleFrameworks = listOf("whisper-cpp"),
                version = "1.0.0",
                description = "Fastest Whisper model for real-time transcription",
                isBuiltIn = false
            ),
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.WHISPER_CPP,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
                localPath = null,
                downloadSize = 74_000_000L,
                memoryRequired = 74_000_000L,
                compatibleFrameworks = listOf("whisper-cpp"),
                version = "1.0.0",
                description = "Balanced accuracy and speed for most use cases",
                isBuiltIn = false
            ),
            ModelInfo(
                id = "whisper-small",
                name = "Whisper Small",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.WHISPER_CPP,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
                localPath = null,
                downloadSize = 244_000_000L,
                memoryRequired = 244_000_000L,
                compatibleFrameworks = listOf("whisper-cpp"),
                version = "1.0.0",
                description = "Higher accuracy for professional transcription",
                isBuiltIn = false
            )
        )
    }

    override suspend fun fetchModelCatalog(): List<ModelInfo> = getMockModels()
    override suspend fun downloadModel(modelInfo: ModelInfo, progressCallback: (Float) -> Unit): String {
        // Simulate progressive download with realistic timing
        for (i in 0..100) {
            delay(50) // Simulate download time
            progressCallback(i / 100f)
        }
        return "/mock/path/to/${modelInfo.id}.bin"
    }
}
```

#### STT Component
```kotlin
interface STTComponent {
    suspend fun initialize(modelPath: String)
    suspend fun transcribe(audioData: ByteArray): TranscriptionResult
    fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate>
    suspend fun cleanup()
}

class WhisperSTTComponent : STTComponent {
    private val jni = WhisperJNI()
    private var modelPtr: Long = 0

    override suspend fun initialize(modelPath: String) {
        modelPtr = withContext(Dispatchers.IO) {
            jni.loadModel(modelPath)
        }
    }

    override suspend fun transcribe(audioData: ByteArray): TranscriptionResult {
        return withContext(Dispatchers.IO) {
            val text = jni.transcribe(modelPtr, audioData, "en")
            TranscriptionResult(
                text = text,
                confidence = 0.95f,
                language = "en",
                duration = audioData.size / 32000.0 // 16kHz stereo
            )
        }
    }

    override fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate> = flow {
        audioFlow.collect { chunk ->
            val partial = jni.transcribePartial(modelPtr, chunk)
            emit(TranscriptionUpdate(
                text = partial,
                isFinal = false,
                timestamp = System.currentTimeMillis()
            ))
        }
    }
}
```

### 3.3 Model Management

```kotlin
class ModelManager {
    private val storage = ModelStorage()
    private val downloader = ModelDownloader()
    private val loadedModels = mutableMapOf<String, ModelInfo>()

    suspend fun ensureModel(modelId: String): String {
        // Check if model exists locally
        storage.getModelPath(modelId)?.let { return it }

        // Download if needed
        return downloader.downloadModel(modelId) { progress ->
            EventBus.emit(ModelEvent.DownloadProgress(modelId, progress))
        }
    }

    suspend fun loadModel(modelId: String): ModelHandle {
        val path = ensureModel(modelId)
        return ModelHandle(modelId, path)
    }

    fun getAvailableModels(): List<ModelInfo> {
        return listOf(
            ModelInfo("whisper-tiny", "39MB", "Fastest, lower accuracy"),
            ModelInfo("whisper-base", "74MB", "Good balance"),
            ModelInfo("whisper-small", "244MB", "Better accuracy"),
            ModelInfo("whisper-medium", "769MB", "High accuracy")
        )
    }
}

class ModelDownloader {
    suspend fun downloadModel(
        modelId: String,
        onProgress: (Float) -> Unit
    ): String = withContext(Dispatchers.IO) {
        val url = getModelUrl(modelId)
        val destination = ModelStorage.getModelDestination(modelId)

        // Download with progress tracking
        downloadFile(url, destination, onProgress)

        return@withContext destination.absolutePath
    }

    private fun getModelUrl(modelId: String): String {
        return when (modelId) {
            "whisper-tiny" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
            "whisper-base" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
            "whisper-small" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else -> throw IllegalArgumentException("Unknown model: $modelId")
        }
    }
}
```

### 3.4 Public API

```kotlin
object RunAnywhereSTT {
    private lateinit var vadComponent: VADComponent
    private lateinit var sttComponent: STTComponent
    private val modelManager = ModelManager()
    private val analytics = AnalyticsTracker()

    // Initialization
    suspend fun initialize(config: STTConfig = STTConfig()) {
        // Initialize VAD
        vadComponent = WebRTCVADComponent()
        vadComponent.initialize(config.vadConfig)

        // Initialize STT
        sttComponent = WhisperSTTComponent()
        val modelPath = modelManager.ensureModel(config.modelId)
        sttComponent.initialize(modelPath)

        // Track initialization
        analytics.track("stt_initialized", mapOf(
            "model" to config.modelId,
            "vad_enabled" to config.enableVAD
        ))

        EventBus.emit(STTEvent.Initialized)
    }

    // Simple transcription
    suspend fun transcribe(audioData: ByteArray): String {
        val startTime = System.currentTimeMillis()

        val result = sttComponent.transcribe(audioData)

        analytics.track("transcription_completed", mapOf(
            "duration_ms" to (System.currentTimeMillis() - startTime),
            "audio_length_s" to (audioData.size / 32000.0),
            "text_length" to result.text.length
        ))

        return result.text
    }

    // Streaming transcription with VAD
    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent> = flow {
        var isInSpeech = false
        val audioBuffer = mutableListOf<ByteArray>()

        audioStream.collect { chunk ->
            // Convert to float array for VAD
            val floatAudio = chunk.toFloatArray()
            val vadResult = vadComponent.processAudioChunk(floatAudio)

            when {
                vadResult.isSpeech && !isInSpeech -> {
                    isInSpeech = true
                    audioBuffer.clear()
                    audioBuffer.add(chunk)
                    emit(TranscriptionEvent.SpeechStart)
                }
                vadResult.isSpeech && isInSpeech -> {
                    audioBuffer.add(chunk)
                    // Emit partial transcription
                    val partial = sttComponent.transcribe(audioBuffer.merge())
                    emit(TranscriptionEvent.PartialTranscription(partial.text))
                }
                !vadResult.isSpeech && isInSpeech -> {
                    isInSpeech = false
                    if (audioBuffer.isNotEmpty()) {
                        val finalAudio = audioBuffer.merge()
                        val result = sttComponent.transcribe(finalAudio)
                        emit(TranscriptionEvent.FinalTranscription(result.text))
                        emit(TranscriptionEvent.SpeechEnd)
                    }
                }
            }
        }
    }

    // Configuration
    data class STTConfig(
        val modelId: String = "whisper-base",
        val enableVAD: Boolean = true,
        val vadConfig: VADConfig = VADConfig(),
        val language: String = "en",
        val enableAnalytics: Boolean = true
    )
}

// Event types
sealed class TranscriptionEvent {
    object SpeechStart : TranscriptionEvent()
    object SpeechEnd : TranscriptionEvent()
    data class PartialTranscription(val text: String) : TranscriptionEvent()
    data class FinalTranscription(val text: String) : TranscriptionEvent()
    data class Error(val error: Throwable) : TranscriptionEvent()
}
```

## 4. Android Studio Plugin Implementation

### 4.1 Plugin Architecture

```kotlin
class RunAnywherePlugin : Plugin<Project> {
    override fun apply(project: Project) {
        // Register plugin services
        project.service<VoiceService>()
        project.service<TranscriptionService>()

        // Register actions
        val actionManager = ActionManager.getInstance()
        actionManager.registerAction("RunAnywhere.VoiceCommand", VoiceCommandAction())
        actionManager.registerAction("RunAnywhere.VoiceDictation", VoiceDictationAction())
    }
}
```

### 4.2 Voice Service

```kotlin
@Service
class VoiceService : Disposable {
    private val audioCapture = AudioCapture()
    private var isRecording = false

    init {
        // Initialize STT on service start
        runBlocking {
            RunAnywhereSTT.initialize(STTConfig(
                modelId = getModelPreference(),
                enableVAD = true
            ))
        }
    }

    fun startVoiceCapture(): Flow<TranscriptionEvent> {
        isRecording = true
        val audioStream = audioCapture.startCapture()
        return RunAnywhereSTT.transcribeStream(audioStream)
    }

    fun stopVoiceCapture() {
        isRecording = false
        audioCapture.stopCapture()
    }

    suspend fun transcribeAudioFile(file: File): String {
        val audioData = file.readBytes()
        return RunAnywhereSTT.transcribe(audioData)
    }

    override fun dispose() {
        if (isRecording) {
            stopVoiceCapture()
        }
    }
}
```

### 4.3 Voice Command Action

```kotlin
class VoiceCommandAction : AnAction("Voice Command", "Execute IDE command using voice", AllIcons.Actions.Execute) {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val voiceService = project.service<VoiceService>()

        // Show voice input dialog
        val dialog = VoiceInputDialog(project)
        dialog.show()

        // Start voice capture
        ApplicationManager.getApplication().executeOnPooledThread {
            runBlocking {
                voiceService.startVoiceCapture().collect { event ->
                    when (event) {
                        is TranscriptionEvent.SpeechStart -> {
                            dialog.updateStatus("Listening...")
                        }
                        is TranscriptionEvent.PartialTranscription -> {
                            dialog.updateTranscription(event.text)
                        }
                        is TranscriptionEvent.FinalTranscription -> {
                            dialog.updateTranscription(event.text)
                            processCommand(project, event.text)
                            dialog.close()
                        }
                        is TranscriptionEvent.Error -> {
                            dialog.showError(event.error.message)
                        }
                    }
                }
            }
        }
    }

    private fun processCommand(project: Project, command: String) {
        val commandProcessor = CommandProcessor(project)

        when {
            command.contains("run test", ignoreCase = true) -> {
                commandProcessor.runTests()
            }
            command.contains("debug", ignoreCase = true) -> {
                commandProcessor.startDebug()
            }
            command.contains("find usages", ignoreCase = true) -> {
                commandProcessor.findUsages()
            }
            command.contains("refactor", ignoreCase = true) -> {
                commandProcessor.showRefactorMenu()
            }
            else -> {
                // Insert as text if no command matched
                insertTextAtCaret(project, command)
            }
        }
    }
}
```

### 4.4 Voice Dictation Mode

```kotlin
class VoiceDictationAction : ToggleAction("Voice Dictation", "Toggle voice dictation mode", AllIcons.Actions.StartDebugger) {
    private var isDictating = false
    private var dictationJob: Job? = null

    override fun isSelected(e: AnActionEvent): Boolean = isDictating

    override fun setSelected(e: AnActionEvent, state: Boolean) {
        val project = e.project ?: return
        val editor = e.getData(CommonDataKeys.EDITOR) ?: return

        isDictating = state

        if (state) {
            startDictation(project, editor)
        } else {
            stopDictation()
        }
    }

    private fun startDictation(project: Project, editor: Editor) {
        val voiceService = project.service<VoiceService>()

        dictationJob = GlobalScope.launch {
            voiceService.startVoiceCapture().collect { event ->
                when (event) {
                    is TranscriptionEvent.FinalTranscription -> {
                        ApplicationManager.getApplication().invokeLater {
                            WriteCommandAction.runWriteCommandAction(project) {
                                val document = editor.document
                                val caretOffset = editor.caretModel.offset
                                document.insertString(caretOffset, event.text + " ")
                                editor.caretModel.moveToOffset(caretOffset + event.text.length + 1)
                            }
                        }
                    }
                    is TranscriptionEvent.PartialTranscription -> {
                        // Show partial text in status bar
                        StatusBar.Info.set(event.text, project)
                    }
                }
            }
        }
    }

    private fun stopDictation() {
        dictationJob?.cancel()
        dictationJob = null
    }
}
```

## 5. Analytics Implementation

```kotlin
class AnalyticsTracker {
    private val events = mutableListOf<AnalyticsEvent>()
    private val sessionId = UUID.randomUUID().toString()

    fun track(eventName: String, properties: Map<String, Any> = emptyMap()) {
        val event = AnalyticsEvent(
            name = eventName,
            properties = properties + mapOf(
                "session_id" to sessionId,
                "timestamp" to System.currentTimeMillis(),
                "platform" to "intellij",
                "sdk_version" to SDK_VERSION
            )
        )

        events.add(event)

        // Send to backend if online
        if (shouldSendEvents()) {
            sendEvents()
        }
    }

    fun trackPerformance(operation: String, duration: Long) {
        track("performance_metric", mapOf(
            "operation" to operation,
            "duration_ms" to duration
        ))
    }

    fun trackError(error: Throwable) {
        track("error_occurred", mapOf(
            "error_type" to error::class.simpleName,
            "error_message" to error.message,
            "stack_trace" to error.stackTraceToString().take(500)
        ))
    }

    private fun sendEvents() {
        // Send to analytics backend
        // This can be batched and sent periodically
    }
}
```

## 6. File Management

```kotlin
class FileManager {
    private val baseDir = File(System.getProperty("user.home"), ".runanywhere")
    private val modelsDir = File(baseDir, "models")
    private val cacheDir = File(baseDir, "cache")
    private val tempDir = File(baseDir, "temp")

    init {
        modelsDir.mkdirs()
        cacheDir.mkdirs()
        tempDir.mkdirs()
    }

    fun getModelPath(modelId: String): File {
        return File(modelsDir, "$modelId.bin")
    }

    fun getCachePath(key: String): File {
        return File(cacheDir, key.hashCode().toString())
    }

    fun createTempFile(prefix: String, suffix: String): File {
        return File.createTempFile(prefix, suffix, tempDir)
    }

    fun cleanupOldFiles(maxAge: Long = 7 * 24 * 60 * 60 * 1000) {
        val cutoff = System.currentTimeMillis() - maxAge

        tempDir.walkTopDown().forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }

    fun getStorageInfo(): StorageInfo {
        return StorageInfo(
            totalSpace = baseDir.totalSpace,
            usedSpace = baseDir.walkTopDown().sumOf { it.length() },
            modelCount = modelsDir.listFiles()?.size ?: 0,
            cacheSize = cacheDir.walkTopDown().sumOf { it.length() }
        )
    }
}

data class StorageInfo(
    val totalSpace: Long,
    val usedSpace: Long,
    val modelCount: Int,
    val cacheSize: Long
)
```

## 7. JNI Integration

### 7.1 Whisper JNI

```kotlin
class WhisperJNI {
    companion object {
        init {
            // Load native library from resources
            NativeLoader.loadLibrary("whisper-jni")
        }
    }

    external fun loadModel(modelPath: String): Long
    external fun transcribe(modelPtr: Long, audioData: ByteArray, language: String): String
    external fun transcribePartial(modelPtr: Long, audioData: ByteArray): String
    external fun unloadModel(modelPtr: Long)
    external fun getModelInfo(modelPtr: Long): String
}
```

### 7.2 WebRTC VAD JNI

```kotlin
class WebRTCVadJNI {
    companion object {
        init {
            NativeLoader.loadLibrary("webrtc-vad-jni")
        }
    }

    external fun initialize(aggressiveness: Int, sampleRate: Int): Long
    external fun isSpeech(vadPtr: Long, audio: FloatArray): Boolean
    external fun reset(vadPtr: Long)
    external fun destroy(vadPtr: Long)
}
```

### 7.3 Native Library Loader

```kotlin
object NativeLoader {
    private val loadedLibraries = mutableSetOf<String>()

    fun loadLibrary(libName: String) {
        if (libName in loadedLibraries) return

        val os = System.getProperty("os.name").lowercase()
        val arch = System.getProperty("os.arch").lowercase()

        val libFileName = when {
            os.contains("win") -> "$libName.dll"
            os.contains("mac") -> "lib$libName.dylib"
            else -> "lib$libName.so"
        }

        val resourcePath = "/native/$os-$arch/$libFileName"
        val resource = NativeLoader::class.java.getResourceAsStream(resourcePath)
            ?: throw UnsatisfiedLinkError("Native library not found: $resourcePath")

        val tempFile = File.createTempFile(libName, libFileName)
        tempFile.deleteOnExit()

        resource.use { input ->
            tempFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }

        System.load(tempFile.absolutePath)
        loadedLibraries.add(libName)
    }
}
```

## 8. Implementation Timeline (6 weeks)

### Week 1: Core Foundation
- [x] Project structure setup
- [x] Core abstractions (Component interfaces)
- [x] Event system implementation
- [x] Basic file management

### Week 2: JNI Integration
- [ ] Whisper.cpp JNI wrapper
- [ ] WebRTC VAD JNI wrapper
- [ ] Native library loading system
- [ ] Cross-platform library packaging

### Week 3: STT Components
- [ ] VAD component implementation
- [ ] STT component implementation
- [ ] Model management system
- [ ] Model downloading with progress

### Week 4: IntelliJ Plugin Base
- [ ] Plugin project setup
- [ ] Basic plugin services
- [ ] Audio capture integration
- [ ] Settings and configuration UI

### Week 5: Plugin Features
- [ ] Voice command action
- [ ] Voice dictation mode
- [ ] Command processing
- [ ] UI components (status bar, tool window)

### Week 6: Polish & Testing
- [ ] Analytics integration
- [ ] Error handling and recovery
- [ ] Performance optimization
- [ ] Documentation and examples
- [ ] Publishing to JetBrains Marketplace

## 9. Testing Strategy

### Unit Tests
```kotlin
class VADComponentTest {
    @Test
    fun `test speech detection`() = runTest {
        val vad = WebRTCVADComponent()
        vad.initialize(VADConfig())

        val speechAudio = loadTestAudio("speech.wav")
        val result = vad.processAudioChunk(speechAudio)

        assertTrue(result.isSpeech)
        assertTrue(result.confidence > 0.8f)
    }
}

class STTComponentTest {
    @Test
    fun `test transcription accuracy`() = runTest {
        val stt = WhisperSTTComponent()
        stt.initialize("whisper-base")

        val audio = loadTestAudio("hello_world.wav")
        val result = stt.transcribe(audio)

        assertEquals("hello world", result.text.lowercase())
    }
}
```

### Integration Tests
```kotlin
class VoicePipelineTest {
    @Test
    fun `test end-to-end voice pipeline`() = runTest {
        RunAnywhereSTT.initialize()

        val audioStream = flowOf(
            loadTestAudio("speech_with_silence_1.wav"),
            loadTestAudio("speech_with_silence_2.wav")
        )

        val events = RunAnywhereSTT.transcribeStream(audioStream).toList()

        assertTrue(events.any { it is TranscriptionEvent.SpeechStart })
        assertTrue(events.any { it is TranscriptionEvent.FinalTranscription })
    }
}
```

## 10. Performance Requirements

### Latency Targets
- VAD decision: < 10ms per frame
- STT first token: < 500ms
- Full transcription: < 2s for 10s audio
- Model loading: < 5s for base model

### Resource Usage
- Memory: < 500MB for base model
- CPU: < 30% during active transcription
- Disk: < 1GB for all models and cache

## 11. Distribution & Deployment

### JetBrains Marketplace
```xml
<!-- plugin.xml -->
<idea-plugin>
    <id>com.runanywhere.stt</id>
    <name>RunAnywhere Voice Commands</name>
    <vendor>RunAnywhere</vendor>
    <version>1.0.0</version>

    <description><![CDATA[
        Voice commands and dictation for IntelliJ IDEA.
        Powered by on-device Whisper AI models.
    ]]></description>

    <depends>com.intellij.modules.platform</depends>

    <extensions defaultExtensionNs="com.intellij">
        <applicationService serviceImplementation="com.runanywhere.plugin.VoiceService"/>
        <projectService serviceImplementation="com.runanywhere.plugin.TranscriptionService"/>
    </extensions>

    <actions>
        <action id="RunAnywhere.VoiceCommand"
                class="com.runanywhere.plugin.VoiceCommandAction"
                text="Voice Command"
                icon="AllIcons.Actions.Execute">
            <keyboard-shortcut first-keystroke="ctrl shift V" keymap="$default"/>
        </action>
    </actions>
</idea-plugin>
```

### Gradle Build Configuration
```kotlin
// plugin/build.gradle.kts
plugins {
    id("org.jetbrains.intellij") version "1.17.0"
    kotlin("jvm") version "1.9.22"
}

intellij {
    version = "2023.3"
    type = "IC"
    plugins = listOf("java")
}

dependencies {
    implementation(project(":core"))
    implementation(project(":jni"))
}

tasks {
    patchPluginXml {
        sinceBuild = "233"
        untilBuild = "241.*"
    }

    buildPlugin {
        archiveFileName = "runanywhere-voice-${version}.zip"
    }

    publishPlugin {
        token = System.getenv("JETBRAINS_TOKEN")
    }
}
```

## 12. Future Expansion Path

### Phase 2: Android App Support (Deferred)
- Android-specific audio capture
- Background service for continuous listening
- Android UI components
- Play Store distribution

### Phase 3: Additional Components (Deferred)
- LLM integration for command understanding
- TTS for voice feedback
- Wake word detection
- Speaker diarization

### Phase 4: Platform Expansion (Deferred)
- VS Code extension
- Eclipse plugin
- Desktop standalone app
- Web assembly support

## 13. Success Metrics

### Launch Metrics (First Month)

- 1,000+ SDK downloads
- 100+ daily active users
- < 1% crash rate
- 4+ star rating

### Performance Metrics
- 95%+ transcription accuracy
- < 500ms average latency
- < 5% CPU usage idle
- 99%+ uptime

### User Engagement

- 10+ transcriptions per session
- 50%+ weekly retention
- 20%+ feature adoption
- Positive user feedback

## Conclusion

The Android SDK STT pipeline implementation is approximately 70% complete. The core architecture,
component system, and service layer are fully implemented and ready for use. The main remaining work
involves:

1. **Native Integration**: Implementing actual JNI bindings for Whisper and WebRTC VAD
2. **Sample App**: Creating the Android sample app with Compose UI
3. **Production Features**: HTTP downloads, database persistence
4. **Testing & Polish**: Comprehensive testing and optimization

The architecture is solid and follows best practices, providing a clean API that's easy to use while
maintaining flexibility for future expansion.
