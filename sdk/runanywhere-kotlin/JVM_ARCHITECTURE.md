# RunAnywhere Kotlin SDK - JVM Architecture Documentation

## Table of Contents
1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Initialization Flow](#initialization-flow)
4. [Model Management](#model-management)
5. [Speech-to-Text Pipeline](#speech-to-text-pipeline)
6. [Plugin Integration](#plugin-integration)
7. [Storage & Security](#storage--security)
8. [Network Architecture](#network-architecture)
9. [Known Issues & Bugs](#known-issues--bugs)
10. [Recommendations](#recommendations)

## Overview

The RunAnywhere Kotlin SDK for JVM is a comprehensive speech-to-text solution designed for desktop and server environments. It provides on-device AI processing using OpenAI's Whisper model, with intelligent routing between local and cloud execution.

### Key Features
- **On-device Speech Recognition**: Uses Whisper models for local transcription
- **Voice Activity Detection (VAD)**: Energy-based speech detection to optimize processing
- **Streaming Support**: Real-time audio transcription with partial results
- **Model Management**: Automatic download, caching, and loading of AI models
- **Plugin-Ready Architecture**: Designed for integration with IntelliJ IDEA and other JVM-based applications

### Technology Stack
- **Language**: Kotlin with Multiplatform support
- **Native Integration**: JNI for Whisper C++ library
- **Networking**: Ktor HTTP client
- **Concurrency**: Kotlin Coroutines and Flow
- **Storage**: Java Preferences API with AES encryption

## System Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Plugin/Application Layer                 │
│                    (IntelliJ IDEA Plugin, etc.)             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│                    RunAnywhere SDK (JVM)                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Public API (RunAnywhere.kt)            │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                    │
│  ┌──────────────────────┼──────────────────────────────┐   │
│  │     Service Container & Dependency Injection        │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                    │
│  ┌──────────────────────┴──────────────────────────────┐   │
│  │                  Core Components                     │   │
│  │  ┌────────┐  ┌────────┐  ┌──────────┐  ┌────────┐ │   │
│  │  │  VAD   │  │  STT   │  │  Model   │  │Analytics│ │   │
│  │  │Component│  │Component│  │ Manager │  │ Tracker │ │   │
│  │  └────────┘  └────────┘  └──────────┘  └────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                Platform Services (JVM)               │   │
│  │  ┌────────┐  ┌────────┐  ┌──────────┐  ┌────────┐ │   │
│  │  │Network │  │Download│  │ Keychain │  │ Logger │ │   │
│  │  │Service │  │Service │  │ Manager  │  │        │ │   │
│  │  └────────┘  └────────┘  └──────────┘  └────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Native Layer (WhisperJNI)               │   │
│  │         (whisper.cpp via Java Native Interface)      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

#### 1. **RunAnywhere (Public API)**
- **Location**: `jvmMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`
- **Responsibilities**:
  - Singleton entry point for SDK
  - API key and configuration management
  - High-level transcription methods
  - Model lifecycle management
  - Event publishing for SDK state changes

#### 2. **ServiceContainer**
- **Location**: `jvmMain/kotlin/com/runanywhere/sdk/foundation/ServiceContainer.kt`
- **Responsibilities**:
  - Component lifecycle management
  - Dependency injection
  - Service registration and lookup
  - Platform-specific service initialization

#### 3. **VADComponent (Voice Activity Detection)**
- **Location**: `commonMain/.../components/vad/VADComponent.kt`
- **JVM Service**: `jvmMain/.../components/vad/JvmVADService.kt`
- **Algorithm**: RMS energy-based detection
- **Configuration**:
  ```kotlin
  data class VADConfiguration(
      val energyThreshold: Float = 0.01f,      // Minimum energy for speech
      val silenceDuration: Long = 500L,        // ms of silence to end speech
      val minSpeechDuration: Long = 100L,      // Minimum speech length
      val windowSize: Int = 512,               // Audio window size
      val sampleRate: Int = 16000             // Audio sample rate
  )
  ```

#### 4. **STTComponent (Speech-to-Text)**
- **Location**: `commonMain/.../components/stt/STTComponent.kt`
- **JVM Service**: `jvmMain/.../components/stt/WhisperSTTService.kt`
- **Model Support**: Currently only Whisper Base English
- **Features**:
  - Batch transcription
  - Streaming with partial results
  - Timestamp extraction
  - Confidence scoring

## Initialization Flow

### Complete Initialization Sequence

```kotlin
// Step 1: Plugin/Application calls initialization
RunAnywhere.initialize(
    apiKey = "your-api-key",
    baseURL = "https://api.runanywhere.ai",
    environment = SDKEnvironment.PRODUCTION
)

// Internal flow:
1. Validate API key (skipped in DEVELOPMENT mode)
2. Initialize platform logger
3. Store credentials in KeychainManager:
   - API key encrypted with AES-128
   - Base URL stored in preferences
4. Initialize ServiceContainer with working directory
5. Create and register services based on environment:
   - DEVELOPMENT: MockNetworkService (returns fake data)
   - PRODUCTION: JvmNetworkService (real HTTP calls)
6. Initialize core components:
   - VADComponent with JvmVADService
   - STTComponent with WhisperSTTService
   - ModelDownloader with progress tracking
   - AnalyticsTracker for telemetry
7. Bootstrap mode-specific features:
   - DEVELOPMENT: Create mock model catalog
   - PRODUCTION: Fetch configuration from API
8. Auto-download default model (whisper-base)
9. Publish SDKInitializationEvent.Completed
```

### State Machine

```
NOT_INITIALIZED
    ↓ initialize()
INITIALIZING
    ↓ all components ready
READY
    ↓ loadSTTModel()
MODEL_LOADING
    ↓ model loaded
ACTIVE
    ↓ transcribe()
PROCESSING
    ↓ complete
ACTIVE
```

## Model Management

### Model Download Flow

```kotlin
// User initiates download
RunAnywhere.downloadModel("whisper-base")
    ↓
// Check model registry
ModelRegistry.getAvailableModels()
    ↓
// Find model metadata
val model = ModelInfo(
    id = "whisper-base",
    name = "Whisper Base English",
    size = 147_000_000L,  // ~147 MB
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
    checksum = "137c40403d78fd54d454da0f9bd998f78703390c"
)
    ↓
// Determine storage path
val destinationPath = "${System.getProperty("user.home")}/.runanywhere/models/whisper-base.bin"
    ↓
// Download with progress
JvmDownloadService.downloadModel(model, destinationPath) { progress ->
    // Progress callbacks: 0.0 to 1.0
}
    ↓
// Validate downloaded file
- Check file size matches expected
- Verify SHA-1 checksum
    ↓
// Auto-load for STT models
STTComponent.loadModel(destinationPath)
```

### Model Storage & Caching

**Storage Location**: `~/.runanywhere/models/`

**Caching Strategy**:
- Models are downloaded once and cached locally
- No automatic re-download unless file is missing or corrupted
- Checksum validation ensures integrity
- No expiration or version checking currently implemented

**Current Issues**:
- No cleanup of partial downloads on failure
- No disk space checking before download
- Missing model version management
- No model update mechanism

## Speech-to-Text Pipeline

### Audio Processing Flow

```
Audio Input (ByteArray, 16kHz, mono)
    ↓
[Optional] VAD Processing
    ↓
Convert to FloatArray (normalized -1.0 to 1.0)
    ↓
WhisperJNI.full() - Native Processing
    ↓
Extract segments with timestamps
    ↓
TranscriptionResult
```

### Detailed STT Implementation

#### 1. **Audio Format Requirements**
- Sample Rate: 16,000 Hz (fixed)
- Channels: Mono (1 channel)
- Bit Depth: 16-bit PCM
- Byte Order: Little Endian

#### 2. **Whisper Integration**

```kotlin
// WhisperSTTService.kt implementation
class WhisperSTTService : STTService {
    private var whisperContext: Long = 0L

    // Native library loading
    companion object {
        init {
            System.loadLibrary("whisper_jni")  // Loads libwhisper_jni.so/.dll
        }
    }

    override suspend fun transcribe(
        audioData: ByteArray,
        options: TranscriptionOptions
    ): TranscriptionResult {
        // Convert audio to float array
        val audioFloat = convertToFloatArray(audioData)

        // Configure Whisper parameters
        val params = WhisperFullParams().apply {
            strategy = WHISPER_SAMPLING_GREEDY
            nThreads = 4
            language = "en"
            printProgress = false
            printTimestamps = true
        }

        // Run native transcription
        val success = WhisperJNI.full(
            ctx = whisperContext,
            params = params,
            samples = audioFloat,
            nSamples = audioFloat.size
        )

        // Extract results
        val segments = extractSegments()
        return TranscriptionResult(
            text = segments.joinToString(" ") { it.text },
            confidence = calculateConfidence(segments),
            segments = segments
        )
    }
}
```

#### 3. **Streaming Transcription**

```kotlin
// Streaming with VAD
RunAnywhere.transcribeStream(audioFlow)
    .collect { result ->
        when (result) {
            is StreamingResult.Partial -> {
                // Partial transcription during speech
                updateUI(result.text)
            }
            is StreamingResult.Final -> {
                // Final transcription after speech ends
                commitTranscription(result.text)
            }
            is StreamingResult.SpeechStart -> {
                // Speech detected, start recording indicator
                showRecordingIndicator()
            }
            is StreamingResult.SpeechEnd -> {
                // Speech ended, processing
                showProcessingIndicator()
            }
        }
    }

// Internal implementation
internal fun transcribeStreamInternal(audioFlow: Flow<ByteArray>) = flow {
    var audioBuffer = mutableListOf<ByteArray>()
    var inSpeech = false

    audioFlow.collect { chunk ->
        val vadResult = vadComponent.processAudio(chunk)

        when {
            vadResult.isSpeech && !inSpeech -> {
                inSpeech = true
                audioBuffer.clear()
                emit(StreamingResult.SpeechStart)
            }
            vadResult.isSpeech && inSpeech -> {
                audioBuffer.add(chunk)
                // Optional: Emit partial results
                if (audioBuffer.size % 10 == 0) {
                    val partial = transcribeBuffer(audioBuffer)
                    emit(StreamingResult.Partial(partial.text))
                }
            }
            !vadResult.isSpeech && inSpeech -> {
                inSpeech = false
                val final = transcribeBuffer(audioBuffer)
                emit(StreamingResult.Final(final.text))
                emit(StreamingResult.SpeechEnd)
            }
        }
    }
}
```

### VAD (Voice Activity Detection) Details

**Algorithm**: Energy-based detection using RMS (Root Mean Square)

```kotlin
// JvmVADService implementation
override suspend fun processAudioChunk(
    audioData: ByteArray,
    sampleRate: Int
): VADResult {
    // Calculate RMS energy
    val samples = audioData.size / 2  // 16-bit samples
    var sum = 0.0

    for (i in audioData.indices step 2) {
        val sample = (audioData[i].toInt() or (audioData[i + 1].toInt() shl 8)).toShort()
        val normalized = sample / 32768.0f
        sum += normalized * normalized
    }

    val rmsEnergy = sqrt(sum / samples).toFloat()

    // Determine if speech based on energy threshold
    val isSpeech = rmsEnergy > config.energyThreshold

    // Apply temporal smoothing
    updateSpeechState(isSpeech)

    return VADResult(
        isSpeech = currentState == SpeechState.SPEAKING,
        energy = rmsEnergy,
        timestamp = System.currentTimeMillis()
    )
}
```

## Plugin Integration

### IntelliJ IDEA Plugin Architecture

```
IntelliJ Plugin
    ↓
Plugin Gradle Dependencies:
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
    ↓
Plugin Initialization:
    class MyPlugin : StartupActivity {
        override fun runActivity(project: Project) {
            RunAnywhere.initialize(
                apiKey = getStoredApiKey(),
                environment = SDKEnvironment.PRODUCTION
            )
        }
    }
    ↓
Usage in Actions/Services:
    class TranscribeAction : AnAction() {
        override fun actionPerformed(e: AnActionEvent) {
            val audio = captureAudio()
            val result = RunAnywhere.transcribe(audio)
            showResult(result.text)
        }
    }
```

### Integration Points

1. **Initialization**: Plugin startup activity or service
2. **Configuration**: Plugin settings UI for API key
3. **Audio Capture**: Platform audio APIs or file input
4. **UI Integration**: Tool windows, notifications, editor actions
5. **Background Processing**: Use IntelliJ's background task API

### Plugin Best Practices

```kotlin
// Use IntelliJ's credential store for API keys
val credentialAttributes = CredentialAttributes(
    serviceName = "RunAnywhere SDK",
    userName = "api-key"
)
PasswordSafe.instance.setPassword(credentialAttributes, apiKey)

// Run SDK operations in background
ProgressManager.getInstance().run(object : Task.Backgroundable(project, "Transcribing...") {
    override fun run(indicator: ProgressIndicator) {
        val result = runBlocking {
            RunAnywhere.transcribe(audioData)
        }
        // Update UI on EDT
        ApplicationManager.getApplication().invokeLater {
            showTranscriptionResult(result)
        }
    }
})
```

## Storage & Security

### KeychainManager Implementation

**Location**: `jvmMain/.../storage/KeychainManager.kt`

**Storage Backend**: Java Preferences API
- Windows: Registry
- macOS: ~/Library/Preferences/
- Linux: ~/.java/.userPrefs/

**Encryption**:
```kotlin
class KeychainManager {
    private val cipher = Cipher.getInstance("AES/ECB/PKCS5Padding")
    private val keySpec = SecretKeySpec(getOrCreateKey(), "AES")

    private fun getOrCreateKey(): ByteArray {
        val storedKey = preferences.getByteArray(KEY_ENCRYPTION_KEY, null)
        return storedKey ?: run {
            // Generate new key
            val keyGen = KeyGenerator.getInstance("AES")
            keyGen.init(128)
            val key = keyGen.generateKey().encoded
            preferences.putByteArray(KEY_ENCRYPTION_KEY, key)
            key
        }
    }

    suspend fun storeCredential(key: String, value: String) {
        cipher.init(Cipher.ENCRYPT_MODE, keySpec)
        val encrypted = cipher.doFinal(value.toByteArray())
        preferences.putByteArray("credential_$key", encrypted)
    }
}
```

**Security Considerations**:
- ⚠️ Encryption key stored alongside encrypted data
- ⚠️ No key derivation or salt usage
- ⚠️ ECB mode vulnerable to pattern analysis
- ✓ Credentials never logged
- ✓ Memory cleared after use

### Model Storage

**Location**: `~/.runanywhere/models/`

**Structure**:
```
~/.runanywhere/
├── models/
│   ├── whisper-base.bin (147 MB)
│   ├── whisper-small.bin (future)
│   └── whisper-medium.bin (future)
├── config/
│   └── sdk_config.json (future)
└── logs/
    └── sdk.log (if debug enabled)
```

### Device Information Collection

The SDK collects minimal device information:
```kotlin
data class DeviceInfo(
    val platform: String = "JVM",
    val osName: String = System.getProperty("os.name"),
    val osVersion: String = System.getProperty("os.version"),
    val javaVersion: String = System.getProperty("java.version"),
    val availableProcessors: Int = Runtime.getRuntime().availableProcessors(),
    val maxMemory: Long = Runtime.getRuntime().maxMemory()
)
```

**Usage**: Analytics and telemetry only, not transmitted in current implementation

## Network Architecture

### Service Selection

```kotlin
// Based on environment
when (environment) {
    SDKEnvironment.DEVELOPMENT -> {
        // MockNetworkService - Returns fake data
        // No actual network calls
        // Simulated delays for realism
    }
    SDKEnvironment.PRODUCTION -> {
        // JvmNetworkService - Real HTTP client
        // Ktor-based implementation
        // Full API integration
    }
}
```

### API Endpoints (Production)

```kotlin
class JvmNetworkService {
    // Base URL: https://api.runanywhere.ai

    suspend fun validateApiKey(apiKey: String): Boolean {
        // POST /v1/auth/validate
        // Headers: Authorization: Bearer {apiKey}
    }

    suspend fun fetchAvailableModels(): List<ModelInfo> {
        // GET /v1/models
        // Returns model catalog
    }

    suspend fun fetchConfiguration(): SDKConfiguration {
        // GET /v1/config
        // Returns feature flags, limits, etc.
    }

    suspend fun reportAnalytics(events: List<AnalyticsEvent>) {
        // POST /v1/analytics
        // Batch event submission
    }
}
```

### Download Service

**Implementation**: HTTP with resume support
```kotlin
class JvmDownloadService {
    suspend fun downloadModel(
        model: ModelInfo,
        destinationPath: String,
        onProgress: (Float) -> Unit
    ): Result<String> {
        // Check existing file
        if (file.exists() && validateChecksum(file, model.checksum)) {
            return Result.success(destinationPath)
        }

        // HTTP download with progress
        val client = HttpClient()
        client.get<HttpStatement>(model.url).execute { response ->
            val contentLength = response.contentLength() ?: 0L
            var downloaded = 0L

            response.content.copyTo(fileOutputStream) { bytes ->
                downloaded += bytes
                onProgress(downloaded.toFloat() / contentLength)
            }
        }

        // Validate download
        if (!validateChecksum(file, model.checksum)) {
            file.delete()
            return Result.failure(Exception("Checksum validation failed"))
        }

        return Result.success(destinationPath)
    }
}
```

## Known Issues & Bugs

### Critical Issues

1. **Native Library Loading Failure** (WhisperSTTService.kt:31-36)
   - **Issue**: Static initializer may fail silently
   - **Impact**: SDK unusable without native library
   - **Fix Required**: Try-catch with fallback mechanism

2. **Progress Tracking Deadlock** (ModelDownloader.kt:85-88)
   - **Issue**: `runBlocking` in callback can cause deadlock
   - **Impact**: UI freezes during download
   - **Fix Required**: Use Channel or SharedFlow

3. **Memory Leak in Native Layer** (WhisperSTTService.kt:214-226)
   - **Issue**: Whisper context not freed on exceptions
   - **Impact**: Native memory accumulation
   - **Fix Required**: Use try-finally for cleanup

### High Priority Issues

4. **Configuration Never Loaded** (SDKConstants.kt:27-29)
   - **Issue**: `loadConfiguration()` exists but never called
   - **Impact**: Feature flags and settings ignored
   - **Fix Required**: Call during initialization

5. **Thread Safety Violations**
   - **Issue**: Shared mutable state without synchronization
   - **Locations**: ModuleRegistry, EventBus, Components
   - **Fix Required**: Add proper locking or use thread-safe collections

6. **Missing Error Recovery**
   - **Issue**: No retry logic for network failures
   - **Impact**: Single failure stops operation
   - **Fix Required**: Implement exponential backoff retry

### Medium Priority Issues

7. **Resource Management**
   - File handles not closed properly
   - Partial downloads not cleaned up
   - Temp directories accumulate

8. **Component State Machine**
   - Can get stuck in INITIALIZING state
   - No timeout mechanism
   - State transitions not atomic

### Performance Issues

9. **Inefficient Audio Processing**
   - Multiple format conversions
   - Large memory allocations
   - No buffer reuse

10. **Synchronous I/O Operations**
    - Model loading blocks thread
    - File operations on main thread
    - No async file I/O

## Recommendations

### Immediate Actions

1. **Fix Native Library Loading**
```kotlin
companion object {
    val isNativeLibraryAvailable = try {
        System.loadLibrary("whisper_jni")
        true
    } catch (e: UnsatisfiedLinkError) {
        logger.error("Failed to load Whisper native library", e)
        false
    }
}
```

2. **Fix Progress Tracking**
```kotlin
// Replace runBlocking with Channel
val progressChannel = Channel<Float>()
downloadService.downloadModel(model, path) { progress ->
    progressChannel.trySend(progress)
}
return progressChannel.receiveAsFlow()
```

3. **Implement Configuration Loading**
```kotlin
// In initialization
val config = configurationManager.loadConfiguration()
SDKConstants.applyConfiguration(config)
```

### Short-term Improvements

1. **Enhanced Error Handling**
   - Consistent SDKError usage
   - Structured error responses
   - User-friendly error messages

2. **Complete Analytics Implementation**
   - Finish backend transmission
   - Add batching and retry
   - Implement privacy controls

3. **Improve Thread Safety**
   - Add @Synchronized annotations
   - Use ConcurrentHashMap
   - Implement proper state machines

### Long-term Enhancements

1. **Multi-Model Support**
   - Add Whisper Small/Medium/Large
   - Support different languages
   - Model selection API

2. **Advanced VAD**
   - ML-based VAD instead of energy
   - Better noise handling
   - Adaptive thresholds

3. **Performance Optimizations**
   - Hardware acceleration support
   - Audio buffer pooling
   - Async I/O operations

4. **Production Readiness**
   - Comprehensive testing
   - Performance benchmarks
   - Security audit

## Conclusion

The RunAnywhere Kotlin SDK for JVM provides a solid foundation for speech-to-text capabilities with a well-structured architecture. The integration with Whisper through JNI enables powerful on-device transcription, while the component-based architecture allows for clean separation of concerns.

However, several critical issues need immediate attention before production deployment:
- Native library loading reliability
- Progress tracking deadlock
- Configuration management
- Thread safety violations

The SDK shows excellent potential for plugin integration, particularly with IntelliJ IDEA, but requires focused effort on completing core functionality and addressing the identified bugs. With the recommended improvements, this SDK can become a robust solution for JVM-based speech recognition applications.
