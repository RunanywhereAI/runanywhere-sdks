# KMP SDK Architecture

> This document describes the target architecture for the Kotlin Multiplatform SDK, aligned with the iOS SDK.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PUBLIC API LAYER                             │
│  RunAnywhere + Extensions (STT, TTS, LLM, VAD, VoiceAgent, etc.)    │
└───────────────────────────────────────┬─────────────────────────────┘
                                        │
┌───────────────────────────────────────┴─────────────────────────────┐
│                            CORE LAYER                                │
│  ModuleRegistry | ServiceRegistry | Capability Protocols             │
└───────────────────────────────────────┬─────────────────────────────┘
                                        │
┌───────────────────────────────────────┴─────────────────────────────┐
│                         INFRASTRUCTURE                               │
│  Events | Logging | Analytics | Download | ModelManagement | Device  │
└───────────────────────────────────────┬─────────────────────────────┘
                                        │
┌───────────────────────────────────────┴─────────────────────────────┐
│                          FEATURES                                    │
│  STT | TTS | LLM | VAD | SpeakerDiarization | VoiceAgent             │
└───────────────────────────────────────┬─────────────────────────────┘
                                        │
┌───────────────────────────────────────┴─────────────────────────────┐
│                         DATA LAYER                                   │
│  Network (APIClient) | Storage (Database) | Repositories             │
└───────────────────────────────────────┬─────────────────────────────┘
                                        │
┌───────────────────────────────────────┴─────────────────────────────┐
│                         FOUNDATION                                   │
│  ServiceContainer (DI) | SDKLogger | SecureStorage | Utilities       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Package Structure

```
commonMain/kotlin/com/runanywhere/sdk/
├── public/                     # Public API surface (minimal, stable)
├── core/                       # Core infrastructure
├── foundation/                 # Foundation services
├── infrastructure/             # Cross-cutting concerns
├── features/                   # Feature implementations
└── data/                       # Data layer
```

---

## Key Components

### 1. RunAnywhere (Main Entry Point)

**Location:** `public/RunAnywhere.kt`

The `RunAnywhere` object is the main SDK entry point, providing:
- SDK initialization (two-phase: fast sync + async services)
- State access (isInitialized, areServicesReady, version, environment)
- Event access via `events` property
- Feature access via extensions (RunAnywhere.stt, RunAnywhere.llm, etc.)

**Initialization Flow:**
```kotlin
// Phase 1: Core init (fast, synchronous-ish)
RunAnywhere.initialize()
// or with config:
RunAnywhere.initialize(
    apiKey = "your_key",
    baseURL = "https://api.runanywhere.ai",
    environment = SDKEnvironment.PRODUCTION
)

// Phase 2: Services init (async, automatic after Phase 1)
// Called automatically in background, or explicitly:
RunAnywhere.completeServicesInitialization()
```

### 2. ServiceContainer (Dependency Injection)

**Location:** `foundation/di/ServiceContainer.kt`

Centralized singleton managing all SDK services:

```kotlin
object ServiceContainer {
    val fileSystem: FileSystem by lazy { createFileSystem() }
    val httpClient: HttpClient by lazy { createHttpClient() }
    val secureStorage: SecureStorage by lazy { createSecureStorage() }

    // Capabilities
    val sttCapability: STTCapability by lazy { STTCapability() }
    val llmCapability: LLMCapability by lazy { LLMCapability() }
    val ttsCapability: TTSCapability by lazy { TTSCapability() }
    val vadCapability: VADCapability by lazy { VADCapability() }

    // Services
    val modelInfoService: ModelInfoService by lazy { ... }
    val analyticsService: AnalyticsService by lazy { ... }
    val downloadService: DownloadService by lazy { ... }

    fun reset() { ... }
}
```

### 3. ModuleRegistry + ServiceRegistry (Plugin System)

**ModuleRegistry** tracks loaded modules (ONNX, LlamaCPP, WhisperKit, etc.):
```kotlin
object ModuleRegistry {
    fun register(module: RunAnywhereModule, priority: Int = 100)
    fun isRegistered(moduleId: String): Boolean
    fun modules(for capability: CapabilityType): List<ModuleMetadata>
    fun storageStrategy(for framework: InferenceFramework): ModelStorageStrategy?
}
```

**ServiceRegistry** manages service factories per capability:
```kotlin
object ServiceRegistry {
    fun registerSTT(name: String, priority: Int, canHandle: (String?) -> Boolean, factory: suspend (STTConfiguration) -> STTService)
    fun registerLLM(...)
    fun registerTTS(...)
    fun registerVAD(...)

    suspend fun createSTT(modelId: String?, config: STTConfiguration): STTService
    suspend fun createLLM(modelId: String?, config: LLMConfiguration): LLMService
    // etc.
}
```

### 4. Event System

**Dual-path event flow:**
1. **Public EventBus** - For consumer subscriptions (Flow-based)
2. **Analytics Pipeline** - Events → Analytics → Network → Backend

**Event Types:**
```kotlin
sealed interface SDKEvent {
    val id: String
    val type: String
    val timestamp: Long
    val destination: EventDestination
}

sealed class SDKLifecycleEvent : SDKEvent {
    data class InitStarted(...) : SDKLifecycleEvent()
    data class InitCompleted(...) : SDKLifecycleEvent()
    data class InitFailed(...) : SDKLifecycleEvent()
}

sealed class STTEvent : SDKEvent { ... }
sealed class LLMEvent : SDKEvent { ... }
// etc.
```

**EventBus:**
```kotlin
object EventBus {
    private val _events = MutableSharedFlow<SDKEvent>()
    val events: SharedFlow<SDKEvent> = _events.asSharedFlow()

    fun publish(event: SDKEvent)
    fun <T: SDKEvent> on(type: KClass<T>): Flow<T>
}
```

### 5. Environment Configuration

**SDKEnvironment:**
```kotlin
enum class SDKEnvironment {
    DEVELOPMENT,  // Local, uses mock/Supabase
    STAGING,      // Real services, staging backend
    PRODUCTION;   // Live, production backend

    val defaultLogLevel: LogLevel
    val requiresApiKey: Boolean
    val requiresBaseURL: Boolean
}
```

| Aspect | Development | Staging | Production |
|--------|-------------|---------|------------|
| API Key Required | No | Yes | Yes |
| Base URL Required | No | Yes | Yes |
| Authentication | None | Token | Token |
| Telemetry | Local | Backend | Backend |
| Log Level | DEBUG | INFO | WARNING |

### 6. Capability Architecture

**Base Protocols:**
```kotlin
interface Capability<Config : ComponentConfiguration> {
    suspend fun configure(config: Config)
    suspend fun cleanup()
}

interface ModelLoadableCapability<Config> : Capability<Config> {
    val isModelLoaded: Boolean
    val currentModelId: String?
    suspend fun loadModel(modelId: String)
    suspend fun unload()
}

interface ServiceBasedCapability<Config> : Capability<Config> {
    val isReady: Boolean
    suspend fun initialize()
}

interface CompositeCapability : Capability<Unit> {
    val isReady: Boolean
}
```

**Feature Capabilities:**
- `STTCapability` - Speech-to-text (ModelLoadable)
- `LLMCapability` - Language model (ModelLoadable)
- `TTSCapability` - Text-to-speech (ModelLoadable)
- `VADCapability` - Voice activity detection (ServiceBased)
- `SpeakerDiarizationCapability` - Speaker identification (ServiceBased)
- `VoiceAgentCapability` - Composed pipeline (Composite)

### 7. Service Protocols

Each capability has a corresponding service protocol:

```kotlin
interface STTService {
    val inferenceFramework: InferenceFramework
    val isReady: Boolean
    val currentModel: String?
    val supportsStreaming: Boolean

    suspend fun initialize(modelPath: String?)
    suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput
    fun streamTranscribe(audioFlow: Flow<ByteArray>, options: STTOptions): Flow<String>
    suspend fun cleanup()
}

interface LLMService {
    val inferenceFramework: InferenceFramework
    val isReady: Boolean
    val currentModel: String?

    suspend fun initialize(modelPath: String?)
    suspend fun generate(prompt: String, options: LLMGenerationOptions): LLMGenerationResult
    fun generateStream(prompt: String, options: LLMGenerationOptions): Flow<LLMStreamingResult>
    suspend fun cancel()
    suspend fun cleanup()
}

// Similar for TTSService, VADService, SpeakerDiarizationService
```

---

## Initialization Sequence

### Phase 1: Core Initialization (Fast, ~1-5ms)

```
RunAnywhere.initialize()
  ├─ Validate parameters
  ├─ Set log level based on environment
  ├─ Store params (in-memory for dev, secure storage for prod/staging)
  ├─ Mark isInitialized = true
  └─ Launch Phase 2 in background
```

### Phase 2: Services Initialization (Async, ~100-500ms)

```
completeServicesInitialization()
  ├─ Setup API Client
  │   ├─ Development: Use Supabase/mock
  │   └─ Production/Staging: Authenticate with backend
  ├─ Create Core Services
  │   ├─ SyncCoordinator
  │   ├─ TelemetryRepository
  │   ├─ ModelInfoService
  │   └─ ModelAssignmentService
  ├─ Load Models (sync from remote + load from local)
  ├─ Initialize Analytics & EventPublisher
  └─ Register Device with Backend
```

---

## Module Registration Flow

```
External Module (WhisperKit, LlamaCPP, ONNX)
  │
  └─ Implements RunAnywhereModule interface
     │
     ├─ static { ModuleDiscovery.register(MyModule::class) }
     │
     └─ fun register(priority: Int) {
           // Called by ModuleRegistry when module is loaded
           ServiceRegistry.registerSTT(
               name = "WhisperKit",
               priority = priority,
               canHandle = { modelId -> modelId?.contains("whisper") == true },
               factory = { config ->
                   WhisperKitSTT().apply { initialize(config.modelPath) }
               }
           )

           // Optionally register storage/download strategies
           ModuleRegistry.registerStorageStrategy(
               framework = InferenceFramework.WHISPER_KIT,
               strategy = WhisperStorageStrategy()
           )
        }
```

---

## Event Flow

```
Feature Operation (e.g., stt.transcribe())
  │
  ├─ Feature-specific AnalyticsService (STTAnalyticsService)
  │   └─ Tracks metrics locally
  │
  └─ EventPublisher.publish(event)
      │
      ├─ EventBus (for public consumers)
      │   └─ RunAnywhere.events.collect { event -> ... }
      │
      └─ AnalyticsQueueManager (for backend)
          └─ Batches → Network → Backend
```

---

## Platform-Specific Code

Use `expect/actual` ONLY for:

1. **File System Paths**
   ```kotlin
   expect fun getModelsDirectory(): String
   expect fun getCacheDirectory(): String
   ```

2. **Device Info Collection**
   ```kotlin
   expect fun collectDeviceInfo(): DeviceInfo
   ```

3. **Secure Storage**
   ```kotlin
   expect class SecureStorage {
       suspend fun store(key: String, value: String)
       suspend fun get(key: String): String?
   }
   ```

4. **HTTP Client Creation**
   ```kotlin
   expect fun createHttpClient(): HttpClient
   ```

5. **Audio I/O** (if needed)
   ```kotlin
   expect fun createAudioRecorder(): AudioRecorder
   expect fun createAudioPlayer(): AudioPlayer
   ```

6. **Native Core Bridge** (jvmAndroidMain only)
   ```kotlin
   // JNI bindings to librunanywhere_jni.so
   object RunAnywhereBridge {
       fun loadLibrary()
       external fun nativeCreateBackend(backendName: String): Long
       external fun nativeSTTTranscribe(handle: Long, samples: FloatArray, sampleRate: Int, language: String?): String?
       // ... other JNI methods for STT, TTS, VAD, Embeddings, Text Generation
   }
   ```

---

## Core Bridge (RunAnywhere Core Integration)

The SDK integrates with the RunAnywhere Core C++ library via JNI for on-device ML inference.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kotlin Application                            │
├─────────────────────────────────────────────────────────────────┤
│  STTCapability | LLMCapability | TTSCapability | VADCapability  │
├─────────────────────────────────────────────────────────────────┤
│            ModuleRegistry + Service Providers                    │
│  (ONNXSTTProvider, LlamaCppLLMProvider, etc.)                   │
├─────────────────────────────────────────────────────────────────┤
│        ONNXCoreService | LlamaCppCoreService                    │
│           (implements NativeCoreService)                         │
├─────────────────────────────────────────────────────────────────┤
│                    RunAnywhereBridge                             │
│                (JNI external functions)                          │
├─────────────────────────────────────────────────────────────────┤
│              librunanywhere_jni.so (Native)                      │
│           (C++ with ONNX, LlamaCPP backends)                     │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

**NativeCoreService (commonMain)** - Abstract interface for native backends:
```kotlin
interface NativeCoreService {
    suspend fun initialize(configJson: String? = null)
    val isInitialized: Boolean
    val supportedCapabilities: List<NativeCapability>

    // STT
    suspend fun loadSTTModel(modelPath: String, modelType: String, configJson: String? = null)
    suspend fun transcribe(audioSamples: FloatArray, sampleRate: Int, language: String? = null): String

    // TTS
    suspend fun loadTTSModel(modelPath: String, modelType: String, configJson: String? = null)
    suspend fun synthesize(text: String, voiceId: String?, speedRate: Float, pitchShift: Float): NativeTTSSynthesisResult

    // VAD
    suspend fun processVAD(audioSamples: FloatArray, sampleRate: Int): NativeVADResult

    // Embeddings
    suspend fun embed(text: String): FloatArray

    fun destroy()
}
```

**Backend Implementations (jvmAndroidMain)**:
- `ONNXCoreService` - ONNX Runtime backend (STT, TTS, VAD, Embeddings)
- `LlamaCppCoreService` - LlamaCPP backend (Text Generation, Embeddings)

**Service Providers (jvmAndroidMain)**:
- `ONNXSTTProvider` - Registers ONNX-based STT with ModuleRegistry
- Additional providers for TTS, VAD, LLM can be added

### Usage Example

```kotlin
// Register provider at app startup
ModuleRegistry.registerSTT(ONNXSTTProvider())

// Use via capability API
RunAnywhere.stt.loadModel("whisper-base")
val result = RunAnywhere.stt.transcribe(audioData)
```

---

## Error Handling

**Error Hierarchy:**
```kotlin
sealed class RunAnywhereError : Exception() {
    data class InvalidConfiguration(override val message: String) : RunAnywhereError()
    data class InvalidAPIKey(override val message: String) : RunAnywhereError()
    data class NotInitialized(override val message: String) : RunAnywhereError()
    data class ValidationFailed(override val message: String) : RunAnywhereError()
}

sealed class CapabilityError : Exception() {
    data class NotInitialized(override val message: String) : CapabilityError()
    data class ResourceNotLoaded(override val message: String) : CapabilityError()
    data class LoadFailed(override val message: String, override val cause: Throwable?) : CapabilityError()
    data class OperationFailed(override val message: String, override val cause: Throwable?) : CapabilityError()
    data class ProviderNotFound(override val message: String) : CapabilityError()
}

// Feature-specific errors
sealed class STTError : Exception() { ... }
sealed class LLMError : Exception() { ... }
sealed class TTSError : Exception() { ... }
// etc.
```

---

## Threading Model

- Use Kotlin coroutines throughout
- All public API methods are `suspend` functions
- Streaming APIs return `Flow<T>`
- Thread safety via `Mutex` and `synchronized` blocks
- Default dispatcher: `Dispatchers.Default` for CPU work, `Dispatchers.IO` for I/O

---

## Key Design Principles

1. **iOS Alignment** - Architecture mirrors iOS SDK for consistency
2. **Kotlin Idiomatic** - Uses coroutines, Flow, sealed classes
3. **Minimal Platform Code** - >90% in commonMain
4. **Type Safety** - Structured types, no stringly-typed APIs
5. **Plugin Architecture** - External modules register services
6. **Event-Driven** - Single event protocol, dual-path delivery
7. **Lazy Initialization** - Services created on demand
8. **Two-Phase Init** - Fast sync phase + async services phase
