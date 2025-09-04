# Android SDK STT Implementation Guide

Based on comprehensive analysis of the Swift SDK architecture, this guide outlines everything needed
for a complete STT pipeline implementation in the Android SDK.
object RunAnywhere {
suspend fun initialize(

## Core Architecture Requirements

### 1. SDK Initialization Flow (Matching Swift)

The Android SDK needs a proper 7-step initialization sequence:

```kotlin
// Main SDK entry point - mirrors Swift's RunAnywhere enum
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.PRODUCTION
    ) {
        // Step 1: Validate API key (skip in development)
        // Step 2: Initialize logging system
        // Step 3: Store credentials securely
        // Step 4: Initialize local database
        // Step 5: Authenticate with backend (skip in development)
        // Step 6: Perform health check (skip in development)
        // Step 7: Bootstrap SDK services
    }
}
```

### 2. Development Mode Support

Critical for sample app testing without backend:

```kotlin
enum class SDKEnvironment {
    DEVELOPMENT,  // Use mock services, no API calls
    STAGING,
    PRODUCTION
}

// In development mode:
// - Skip API authentication
// - Use MockNetworkService
// - Load mock model catalog
// - Return predefined responses
```

### 3. Event-Driven Architecture

Essential for real-time updates and progress tracking:

```kotlin
object EventBus {
    val initializationEvents: Flow<SDKInitializationEvent>
    val modelEvents: Flow<SDKModelEvent>
    val voiceEvents: Flow<SDKVoiceEvent>

    suspend fun publish(event: SDKEvent)
}

// Event types matching Swift
sealed class SDKInitializationEvent {
    object Started
    object Completed
    data class Failed(val error: Throwable)
}

sealed class SDKModelEvent {
    data class LoadStarted(val modelId: String)
    data class DownloadProgress(val modelId: String, val progress: Float)
    data class LoadCompleted(val modelId: String)
}

sealed class SDKVoiceEvent {
    object TranscriptionStarted
    data class TranscriptionPartial(val text: String)
    data class TranscriptionFinal(val text: String)
}
```

### 4. Service Container (Dependency Injection)

Centralized service management:

```kotlin
class ServiceContainer {
    companion object {
        val shared = ServiceContainer()
    }

    // Core services
    val configurationService: ConfigurationService
    val modelRegistry: ModelRegistry
    val modelLoadingService: ModelLoadingService
    val downloadService: DownloadService
    val memoryService: MemoryService

    // Components
    val vadComponent: VADComponent
    val sttComponent: STTComponent

    suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData
    suspend fun bootstrap(params: SDKInitParams, auth: AuthService): ConfigurationData
}
```

## Model Management System

### Model Registry

```kotlin
class ModelRegistry {
    fun discoverModels(): List<ModelInfo>
    fun loadMockModels(models: List<ModelInfo>)
    fun getModel(id: String): ModelInfo?
}

data class ModelInfo(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val format: ModelFormat,
    val downloadURL: String?,
    val downloadSize: Long,
    val memoryRequired: Long,
    val compatibleFrameworks: List<String>
)
```

### Model Loading Pipeline

1. **Discovery**: Find model in registry
2. **Validation**: Check format and compatibility
3. **Download**: If not present locally
4. **Memory Check**: Ensure sufficient memory
5. **Loading**: Load into framework
6. **Registration**: Track loaded model

### Mock Models for Development

```kotlin
// Models matching Swift's MockNetworkService
val mockModels = listOf(
    ModelInfo(
        id = "whisper-tiny",
        name = "Whisper Tiny",
        category = ModelCategory.SPEECH_RECOGNITION,
        downloadSize = 39_000_000L,
        memoryRequired = 39_000_000L
    ),
    ModelInfo(
        id = "whisper-base",
        name = "Whisper Base",
        category = ModelCategory.SPEECH_RECOGNITION,
        downloadSize = 74_000_000L,
        memoryRequired = 74_000_000L
    ),
    ModelInfo(
        id = "whisper-small",
        name = "Whisper Small",
        category = ModelCategory.SPEECH_RECOGNITION,
        downloadSize = 244_000_000L,
        memoryRequired = 244_000_000L
    )
)
```

## File Management System

### Directory Structure

```kotlin
object FileManager {
    fun initialize(context: Context)

    val baseDirectory: File         // .../files/runanywhere/
    val modelsDirectory: File       // .../files/runanywhere/models/
    val cacheDirectory: File        // .../files/runanywhere/cache/
    val tempDirectory: File         // .../files/runanywhere/temp/

    fun getModelPath(modelId: String): File
    fun getStorageInfo(): StorageInfo
    fun cleanupOldFiles(maxAge: Long)
}
```

## STT Component Architecture

### Component Lifecycle States

```kotlin
enum class ComponentState {
    NOT_INITIALIZED,
    CHECKING,
    DOWNLOAD_REQUIRED,
    DOWNLOADING,
    DOWNLOADED,
    INITIALIZING,
    READY,
    FAILED,
    TERMINATING,
    ERROR
}
```

### STT Component Implementation

```kotlin
class STTComponent(config: STTConfiguration) : BaseComponent<STTService>() {

    suspend fun initialize()
    suspend fun transcribe(audioData: ByteArray): TranscriptionResult
    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent>
    suspend fun cleanup()

    fun setCurrentModel(model: LoadedModel)
    fun getCurrentModel(): LoadedModel?
    fun isInitialized(): Boolean
}
```

### VAD Integration

```kotlin
class VADComponent(config: VADConfiguration) {
    fun processAudioChunk(audio: FloatArray): VADResult
    suspend fun initialize()
    suspend fun cleanup()
}

data class VADResult(
    val isSpeech: Boolean,
    val confidence: Float,
    val energy: Float
)
```

## Sample App Integration Requirements

### Application Class Setup

```kotlin
class RunAnywhereApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // Initialize file manager
        FileManager.initialize(this)

        // Initialize SDK in development mode
        lifecycleScope.launch {
            RunAnywhere.initialize(
                apiKey = "dev-api-key",
                environment = SDKEnvironment.DEVELOPMENT
            )

            // Preload STT model
            RunAnywhere.loadModel("whisper-base")
        }
    }
}
```

### MainActivity Requirements

1. **Permission Handling**: Request RECORD_AUDIO permission
2. **Event Subscription**: Subscribe to SDK events
3. **Audio Recording**: Create audio stream from microphone
4. **UI Updates**: Real-time transcription display
5. **State Management**: Track recording and VAD status

### UI Components Needed

```kotlin
@Composable
fun MainScreen() {
    // Status Card - Shows STT/VAD status
    // Result Card - Shows transcription text
    // Record Button - Toggle recording
}
```

## Critical Implementation Details

### 1. Audio Processing

```kotlin
// Convert byte array to float array for VAD
fun ByteArray.toFloatArray(): FloatArray {
    val floatArray = FloatArray(size / 2)
    for (i in floatArray.indices) {
        val sample = (this[i * 2].toInt() and 0xFF) or
                    (this[i * 2 + 1].toInt() shl 8)
        floatArray[i] = sample / 32768.0f
    }
    return floatArray
}
```

### 2. Streaming Transcription with VAD

```kotlin
fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent> = flow {
    val vadComponent = VADComponent(VADConfiguration())
    var isInSpeech = false
    val audioBuffer = mutableListOf<ByteArray>()

    audioStream.collect { chunk ->
        val vadResult = vadComponent.processAudioChunk(chunk.toFloatArray())

        when {
            vadResult.isSpeech && !isInSpeech -> {
                // Speech started
                isInSpeech = true
                audioBuffer.clear()
                audioBuffer.add(chunk)
                emit(TranscriptionEvent.SpeechStart)
            }
            vadResult.isSpeech && isInSpeech -> {
                // Continuing speech
                audioBuffer.add(chunk)
                if (audioBuffer.size > 5) {
                    // Emit partial transcription
                    val partial = transcribeBuffer(audioBuffer)
                    emit(TranscriptionEvent.PartialTranscription(partial))
                }
            }
            !vadResult.isSpeech && isInSpeech -> {
                // Speech ended
                isInSpeech = false
                val final = transcribeBuffer(audioBuffer)
                emit(TranscriptionEvent.FinalTranscription(final))
                emit(TranscriptionEvent.SpeechEnd)
            }
        }
    }
}
```

### 3. Configuration Data Structure

```kotlin
data class ConfigurationData(
    val id: String,
    val apiKey: String,
    val source: ConfigurationSource
)

enum class ConfigurationSource {
    LOCAL,
    REMOTE
}

data class STTConfiguration(
    val modelId: String? = "whisper-base",
    val language: String = "en",
    val sampleRate: Int = 16000,
    val enableVAD: Boolean = true,
    val enableTimestamps: Boolean = false
)
```

### 4. Error Handling

```kotlin
sealed class SDKError : Exception() {
    object NotInitialized : SDKError()
    data class InvalidAPIKey(override val message: String) : SDKError()
    data class ModelNotFound(val modelId: String) : SDKError()
    data class LoadingFailed(override val message: String) : SDKError()
    data class TranscriptionFailed(override val message: String) : SDKError()
}
```

## JNI Integration Requirements

### WhisperJNI Interface

```kotlin
class WhisperJNI {
    companion object {
        init {
            System.loadLibrary("whisper-jni")
        }
    }

    external fun loadModel(modelPath: String): Long
    external fun transcribe(modelPtr: Long, audioData: ByteArray, language: String): String
    external fun transcribePartial(modelPtr: Long, audioData: ByteArray): String
    external fun unloadModel(modelPtr: Long)
}
```

### WebRTCVadJNI Interface

```kotlin
class WebRTCVadJNI {
    companion object {
        init {
            System.loadLibrary("webrtc-vad-jni")
        }
    }

    external fun initialize(aggressiveness: Int, sampleRate: Int): Long
    external fun isSpeech(vadPtr: Long, audio: FloatArray): Boolean
    external fun destroy(vadPtr: Long)
}
```

## Analytics Integration

```kotlin
class AnalyticsTracker {
    fun track(eventName: String, properties: Map<String, Any>)
    fun trackPerformance(operation: String, duration: Long)
    fun trackError(error: Throwable)
}

// Track STT events
analytics.track("stt_initialized", mapOf(
    "model" to modelId,
    "vad_enabled" to enableVAD
))

analytics.track("transcription_completed", mapOf(
    "duration_ms" to duration,
    "text_length" to text.length
))
```

## Testing Requirements

### Unit Tests Needed

1. **SDK Initialization**: Test development mode initialization
2. **Model Management**: Test model discovery and loading
3. **VAD Processing**: Test speech detection accuracy
4. **STT Transcription**: Test transcription with mock service
5. **Event System**: Test event publishing and subscription

### Integration Tests

1. **End-to-end Pipeline**: Audio → VAD → STT → Text
2. **Streaming Transcription**: Real-time processing
3. **Error Recovery**: Handle failures gracefully
4. **Memory Management**: Test under memory pressure

## Performance Requirements

- SDK initialization: < 2 seconds
- Model loading: < 5 seconds
- VAD decision: < 10ms per frame
- STT first token: < 500ms
- Memory usage: < 500MB with base model

## Summary of Key Components Needed

1. ✅ **RunAnywhere object**: Main SDK entry point
2. ✅ **EventBus**: Event-driven communication
3. ✅ **ServiceContainer**: Dependency injection
4. ✅ **MockNetworkService**: Development mode support
5. ✅ **ModelRegistry**: Model management
6. ✅ **FileManager**: File system operations
7. ✅ **STTComponent**: Speech-to-text processing
8. ✅ **VADComponent**: Voice activity detection
9. ✅ **Configuration system**: Settings management
10. ✅ **Error handling**: Comprehensive error types
11. ✅ **Analytics**: Usage tracking
12. ✅ **JNI wrappers**: Native library integration

This implementation guide provides everything needed to build a production-ready STT pipeline that
matches the Swift SDK's capabilities and architecture.
