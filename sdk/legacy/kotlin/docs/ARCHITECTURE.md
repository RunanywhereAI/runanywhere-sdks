# RunAnywhere Kotlin SDK Architecture

This document describes the internal architecture, design principles, and implementation details of the RunAnywhere Kotlin SDK.

---

## Table of Contents

1. [Design Principles](#design-principles)
2. [High-Level Architecture](#high-level-architecture)
3. [Package Structure](#package-structure)
4. [Initialization Flow](#initialization-flow)
5. [Threading Model](#threading-model)
6. [Native Bridge Layer](#native-bridge-layer)
7. [Module System](#module-system)
8. [Public API Design](#public-api-design)
9. [Event System](#event-system)
10. [Model Management](#model-management)
11. [Error Handling](#error-handling)
12. [Testing Strategy](#testing-strategy)

---

## Design Principles

### 1. Single API Surface
Developers call one SDK; we abstract engine complexity. All AI capabilities (LLM, STT, TTS, VAD) are accessed through the unified `RunAnywhere` object.

### 2. Kotlin Multiplatform First
The SDK uses Kotlin Multiplatform (KMP) to share code across:
- **commonMain** - Platform-agnostic business logic and API definitions
- **jvmAndroidMain** - Shared JVM/Android code including JNI bridges
- **androidMain** - Android-specific implementations (permissions, audio, storage)
- **jvmMain** - Desktop JVM implementations

### 3. Async-First
All I/O operations (network, model loading, inference) are non-blocking:
- Uses Kotlin Coroutines and Flows
- Never blocks the main thread
- Streaming APIs for real-time output

### 4. Observability Built-In
Every operation records metadata (latency, device state, model info):
- Events emitted for analytics
- Generation results include full metrics
- Production debugging enabled by default

### 5. Memory-Conscious
Aggressive resource management for mobile devices:
- On-demand model loading
- Explicit unload APIs
- Native memory managed by C++ layer

### 6. Platform Parity
Mirrors the iOS RunAnywhere Swift SDK exactly:
- Same API signatures
- Same event types
- Same error codes

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Application Layer                              │
│                    (Your Android/JVM Application)                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        RunAnywhere Public API                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     RunAnywhere Object                          │   │
│  │  • initialize()/reset()                                         │   │
│  │  • isInitialized, areServicesReady                              │   │
│  │  • events (EventBus)                                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│  ┌────────────┬────────────┬────────────┬────────────┬────────────┐   │
│  │  LLM API   │  STT API   │  TTS API   │  VAD API   │ VoiceAgent │   │
│  │ (extension)│ (extension)│ (extension)│ (extension)│ (extension)│   │
│  └────────────┴────────────┴────────────┴────────────┴────────────┘   │
│                                    │                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Model Management API                        │   │
│  │  • registerModel(), downloadModel()                             │   │
│  │  • loadLLMModel(), loadSTTModel(), loadTTSVoice()               │   │
│  │  • availableModels(), deleteModel()                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Internal Layer                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       CppBridge                                 │   │
│  │  • JNI bindings to runanywhere-commons                          │   │
│  │  • Platform adapter registration                                │   │
│  │  • Callback bridges (events, telemetry)                         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Platform Services                            │   │
│  │  • StoragePlatform (file system access)                         │   │
│  │  • NetworkConnectivity                                          │   │
│  │  • SecureStorage (KeychainManager)                              │   │
│  │  • DeviceInfo                                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Native Layer (C++)                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                   runanywhere-commons                           │   │
│  │  • librac_commons.so - Core infrastructure                      │   │
│  │  • librunanywhere_jni.so - JNI bridge                           │   │
│  │  • Model registry, download management                          │   │
│  │  • Event system, telemetry                                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                          │                    │                          │
│              ┌───────────┴───────────┐       │                          │
│              ▼                       ▼       ▼                          │
│  ┌───────────────────────┐  ┌────────────────────────────────────┐     │
│  │ runanywhere-core-     │  │    runanywhere-core-onnx           │     │
│  │    llamacpp           │  │                                    │     │
│  │                       │  │  • libonnxruntime.so               │     │
│  │  • llama.cpp engine   │  │  • libsherpa-onnx-*.so             │     │
│  │  • LLM inference      │  │  • STT/TTS/VAD inference           │     │
│  └───────────────────────┘  └────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Package Structure

```
com.runanywhere.sdk/
├── public/                           # Public API (exported)
│   ├── RunAnywhere.kt               # Main SDK entry point
│   ├── events/
│   │   ├── EventBus.kt              # Event subscription system
│   │   └── SDKEvent.kt              # Event type definitions
│   └── extensions/
│       ├── RunAnywhere+TextGeneration.kt    # LLM APIs
│       ├── RunAnywhere+STT.kt               # Speech-to-text APIs
│       ├── RunAnywhere+TTS.kt               # Text-to-speech APIs
│       ├── RunAnywhere+VAD.kt               # Voice activity detection
│       ├── RunAnywhere+VoiceAgent.kt        # Voice pipeline orchestration
│       ├── RunAnywhere+ModelManagement.kt   # Model registration/download
│       ├── LLM/LLMTypes.kt                  # LLM type definitions
│       ├── STT/STTTypes.kt                  # STT type definitions
│       ├── TTS/TTSTypes.kt                  # TTS type definitions
│       ├── VAD/VADTypes.kt                  # VAD type definitions
│       ├── VoiceAgent/VoiceAgentTypes.kt    # Voice agent types
│       └── Models/ModelTypes.kt             # Model type definitions
│
├── core/                             # Core types and interfaces
│   ├── types/
│   │   └── ComponentTypes.kt        # SDKComponent, InferenceFramework
│   └── module/
│       └── SDKModule.kt             # Module registration interface
│
├── foundation/                       # Foundation utilities
│   ├── SDKLogger.kt                 # Logging system
│   ├── errors/
│   │   ├── SDKError.kt              # Error class
│   │   ├── ErrorCode.kt             # Error codes
│   │   └── ErrorCategory.kt         # Error categories
│   ├── device/
│   │   └── DeviceCapabilities.kt    # Device info
│   └── constants/
│       └── SDKConstants.kt          # SDK version, etc.
│
├── native/                           # Native bridge (internal)
│   └── bridge/
│       ├── NativeCoreService.kt     # JNI service interface
│       ├── BridgeResults.kt         # Native call results
│       └── Capability.kt            # Native capability types
│
├── data/                             # Data layer
│   ├── models/
│   │   └── ModelEntity.kt           # Model persistence
│   ├── network/
│   │   └── ApiClient.kt             # HTTP client
│   └── repositories/
│       └── ModelRepository.kt       # Model data access
│
├── storage/                          # Storage layer
│   ├── PlatformStorage.kt           # Cross-platform storage
│   └── FileSystem.kt                # File operations
│
├── platform/                         # Platform abstractions
│   ├── Checksum.kt                  # Hash verification
│   ├── NetworkConnectivity.kt       # Network state
│   └── StoragePlatform.kt           # Storage abstraction
│
└── utils/                            # Utilities
    ├── SDKConstants.kt              # Constants
    └── Extensions.kt                # Kotlin extensions
```

---

## Initialization Flow

The SDK uses a **two-phase initialization** pattern for optimal startup performance:

### Phase 1: Core Init (Synchronous, ~1-5ms)

```
RunAnywhere.initialize(environment)
    │
    ├─► Store environment
    │
    ├─► Set log level based on environment
    │
    └─► CppBridge.initialize()
         │
         ├─► Load JNI library (librunanywhere_jni.so)
         │
         ├─► Register PlatformAdapter (file I/O, logging, keychain)
         │
         ├─► Register Events callback (analytics)
         │
         └─► Initialize Device registration

    Result: isInitialized = true
```

### Phase 2: Services Init (Async, ~100-500ms)

```
RunAnywhere.completeServicesInitialization()
    │
    ├─► CppBridge.initializeServices()
    │    │
    │    ├─► Register ModelAssignment callbacks
    │    │
    │    └─► Register Platform service callbacks (LLM/TTS)
    │
    └─► Mark: areServicesReady = true
```

**Key Points:**
- Phase 1 is fast and synchronous - safe to call in `Application.onCreate()`
- Phase 2 is called automatically on first API call, or can be awaited explicitly
- Both phases are idempotent - safe to call multiple times

---

## Threading Model

| Operation | Thread | Notes |
|-----------|--------|-------|
| `RunAnywhere.initialize()` | Calling thread (main) | Fast, < 5ms |
| `completeServicesInitialization()` | Calling thread | Suspending function |
| `loadLLMModel()` / `loadSTTModel()` | Dispatchers.IO | Async, returns immediately |
| `generate()` / `transcribe()` | Dispatchers.Default | CPU-bound inference |
| `generateStream()` | Dispatchers.Default | Returns Flow, collects on Default |
| `downloadModel()` | Dispatchers.IO | Network I/O |
| Event emissions | Internal event loop | Delivered to collectors' context |

**Thread Safety:**
- All public APIs are thread-safe
- Internal state protected by `synchronized` blocks
- Native layer handles its own thread safety

---

## Native Bridge Layer

The SDK communicates with the C++ `runanywhere-commons` library via JNI:

### CppBridge Architecture

```kotlin
// Kotlin side (jvmAndroidMain)
object CppBridge {
    // Phase 1 initialization
    external fun nativeInitialize(environment: Int, apiKey: String?, baseUrl: String?): Int

    // Phase 2 services
    external fun nativeInitializeServices(): Int

    // LLM operations
    external fun nativeLoadModel(modelId: String, modelPath: String): Int
    external fun nativeGenerate(prompt: String, options: String): String
    external fun nativeGenerateStream(prompt: String, options: String, callback: StreamCallback): Int

    // STT operations
    external fun nativeTranscribe(audioData: ByteArray, options: String): String

    // TTS operations
    external fun nativeSynthesize(text: String, options: String): ByteArray

    // Shutdown
    external fun nativeShutdown()
}
```

### Platform Adapter Pattern

The SDK registers Kotlin callbacks with the C++ layer for platform-specific operations:

```kotlin
// Registered during Phase 1
object PlatformAdapter {
    // File operations (called from C++)
    fun readFile(path: String): ByteArray
    fun writeFile(path: String, data: ByteArray)
    fun fileExists(path: String): Boolean

    // Logging (called from C++)
    fun log(level: Int, tag: String, message: String)

    // Keychain (called from C++)
    fun secureStore(key: String, value: String)
    fun secureRetrieve(key: String): String?
}
```

---

## Module System

The SDK uses a modular architecture where AI backends are optional:

### Core SDK (Required)
- `com.runanywhere.sdk:runanywhere-kotlin`
- Contains: Public API, JNI bridge, model management
- Native: `librac_commons.so`, `librunanywhere_jni.so`

### LlamaCPP Module (Optional)
- `com.runanywhere.sdk:runanywhere-core-llamacpp`
- Provides: LLM text generation
- Native: `librunanywhere_llamacpp.so` (~34MB)
- Framework: `InferenceFramework.LLAMA_CPP`

### ONNX Module (Optional)
- `com.runanywhere.sdk:runanywhere-core-onnx`
- Provides: STT, TTS, VAD
- Native: `libonnxruntime.so`, `libsherpa-onnx-*.so` (~25MB)
- Framework: `InferenceFramework.ONNX`

### Module Detection

```kotlin
// Check which modules are available at runtime
val hasLLM = CppBridge.isCapabilityAvailable(SDKComponent.LLM)
val hasSTT = CppBridge.isCapabilityAvailable(SDKComponent.STT)
val hasTTS = CppBridge.isCapabilityAvailable(SDKComponent.TTS)
val hasVAD = CppBridge.isCapabilityAvailable(SDKComponent.VAD)
```

---

## Public API Design

### Extension Function Pattern

All feature-specific APIs are implemented as extension functions on `RunAnywhere`:

```kotlin
// Definition (in RunAnywhere+TextGeneration.kt)
expect suspend fun RunAnywhere.chat(prompt: String): String

// Implementation (in RunAnywhere+TextGeneration.jvmAndroid.kt)
actual suspend fun RunAnywhere.chat(prompt: String): String {
    requireInitialized()
    ensureServicesReady()
    return CppBridge.nativeChat(prompt)
}
```

**Benefits:**
- Clean separation of concerns
- Easy to add new features without modifying core
- Platform-specific implementations via expect/actual

### Result Types

All operations return rich result types with metadata:

```kotlin
data class LLMGenerationResult(
    val text: String,                    // Generated content
    val thinkingContent: String?,        // Reasoning (if model supports)
    val inputTokens: Int,                // Prompt tokens
    val tokensUsed: Int,                 // Output tokens
    val modelUsed: String,               // Model ID
    val latencyMs: Double,               // Total time
    val tokensPerSecond: Double,         // Generation speed
    val timeToFirstTokenMs: Double?,     // TTFT (streaming)
)
```

---

## Event System

### Event Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      C++ Event Producer                          │
│  (runanywhere-commons generates events)                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CppEventBridge (JNI)                          │
│  (Callback registered during Phase 1)                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        EventBus                                  │
│  SharedFlow-based event distribution                             │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐     │
│  │ llmEvents   │ sttEvents   │ ttsEvents   │ modelEvents │     │
│  │ (Flow)      │ (Flow)      │ (Flow)      │ (Flow)      │     │
│  └─────────────┴─────────────┴─────────────┴─────────────┘     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                      App Collectors
```

### Event Types

| Category | Events |
|----------|--------|
| SDK | `sdk.initialized`, `sdk.shutdown`, `sdk.error` |
| Model | `model.download_started`, `model.download_progress`, `model.download_completed`, `model.loaded`, `model.unloaded` |
| LLM | `llm.generation_started`, `llm.stream_token`, `llm.generation_completed`, `llm.generation_failed` |
| STT | `stt.transcription_started`, `stt.partial_result`, `stt.transcription_completed` |
| TTS | `tts.synthesis_started`, `tts.synthesis_completed`, `tts.playback_started` |

### Subscribing to Events

```kotlin
// Subscribe to LLM events
lifecycleScope.launch {
    RunAnywhere.events.llmEvents.collect { event ->
        Log.d("LLM", "Event: ${event.type}, Latency: ${event.latencyMs}ms")
    }
}

// Subscribe to all events
lifecycleScope.launch {
    RunAnywhere.events.allEvents.collect { event ->
        analytics.track(event.type, event.properties)
    }
}
```

---

## Model Management

### Model Lifecycle

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Register   │ ──► │  Download   │ ──► │    Load     │ ──► │   Unload    │
│  (metadata) │     │  (network)  │     │  (memory)   │     │  (cleanup)  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
   ModelInfo          DownloadProgress    Model in RAM        Memory freed
   in registry        events emitted      ready for use       model cached
```

### Model States

```kotlin
// 1. Registered but not downloaded
model.isDownloaded == false
model.localPath == null

// 2. Downloaded but not loaded
model.isDownloaded == true
model.localPath != null
RunAnywhere.isLLMModelLoaded() == false

// 3. Loaded and ready
model.isDownloaded == true
RunAnywhere.isLLMModelLoaded() == true
RunAnywhere.currentLLMModelId == model.id
```

### Download Flow

```kotlin
RunAnywhere.downloadModel(modelId)
    │
    ├─► Emit: ModelEvent.DOWNLOAD_STARTED
    │
    ├─► Fetch URL → Write chunks to temp file
    │    │
    │    └─► Emit: ModelEvent.DOWNLOAD_PROGRESS (0.0 → 1.0)
    │
    ├─► Extract if archive (tar.gz, zip)
    │
    ├─► Verify checksum (if provided)
    │
    ├─► Move to final location
    │
    ├─► Update model.localPath
    │
    └─► Emit: ModelEvent.DOWNLOAD_COMPLETED
```

---

## Error Handling

### Error Structure

```kotlin
data class SDKError(
    val code: ErrorCode,          // Specific error type
    val category: ErrorCategory,  // Error group
    val message: String,          // Human-readable
    val cause: Throwable?         // Underlying exception
) : Exception(message, cause)
```

### Error Categories

| Category | Description | Example Errors |
|----------|-------------|----------------|
| `INITIALIZATION` | SDK startup | `NOT_INITIALIZED`, `ALREADY_INITIALIZED` |
| `MODEL` | Model operations | `MODEL_NOT_FOUND`, `MODEL_LOAD_FAILED` |
| `LLM` | Text generation | `LLM_GENERATION_FAILED` |
| `STT` | Speech-to-text | `STT_TRANSCRIPTION_FAILED` |
| `TTS` | Text-to-speech | `TTS_SYNTHESIS_FAILED` |
| `NETWORK` | Network issues | `NETWORK_UNAVAILABLE`, `TIMEOUT` |
| `STORAGE` | Storage issues | `INSUFFICIENT_STORAGE`, `FILE_NOT_FOUND` |

### Error Factory Pattern

```kotlin
// Create errors with factory methods
throw SDKError.modelNotFound(modelId)
throw SDKError.llmGenerationFailed("Context length exceeded")
throw SDKError.networkUnavailable()

// From C++ error codes
val error = SDKError.fromRawValue(cppErrorCode, message)
```

---

## Testing Strategy

### Unit Tests

Test business logic without native libraries:

```kotlin
@Test
fun testModelRegistration() {
    val modelInfo = createTestModelInfo()

    // Test URL parsing
    assertEquals("qwen-0.5b", generateModelIdFromUrl(modelInfo.downloadURL))

    // Test format detection
    assertEquals(ModelFormat.GGUF, detectFormatFromUrl(modelInfo.downloadURL))
}
```

### Integration Tests

Test with mocked native layer:

```kotlin
@Test
fun testGenerationFlow() = runTest {
    // Mock CppBridge
    mockkObject(CppBridge)
    every { CppBridge.nativeGenerate(any(), any()) } returns """
        {"text": "Hello", "tokensUsed": 5, "latencyMs": 100}
    """

    // Test generation
    val result = RunAnywhere.generate("Hi")
    assertEquals("Hello", result.text)
}
```

### Instrumented Tests

Test on real devices with actual models:

```kotlin
@Test
fun testRealInference() = runTest {
    // Initialize SDK
    RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

    // Load a small test model
    RunAnywhere.loadLLMModel("test-tiny-model")

    // Run inference
    val result = RunAnywhere.generate("2+2=")
    assertNotNull(result.text)
    assertTrue(result.latencyMs > 0)
}
```

---

## Performance Characteristics

### Typical Latencies (Pixel 7, 8GB RAM)

| Operation | Latency | Notes |
|-----------|---------|-------|
| SDK Initialize (Phase 1) | 1-5ms | Synchronous |
| SDK Initialize (Phase 2) | 50-100ms | Async |
| Model Load (0.5B) | 500-800ms | First time, cached after |
| Inference (50 tokens) | 150-300ms | Depends on model size |
| Streaming TTFT | 50-100ms | Time to first token |
| STT Transcribe (5s audio) | 200-400ms | Whisper tiny |
| TTS Synthesize (100 chars) | 100-200ms | Sherpa ONNX |

### Memory Footprint

| Component | Memory |
|-----------|--------|
| SDK (no models) | ~5MB |
| 0.5B LLM (Q8) | ~500MB |
| 0.5B LLM (Q4) | ~300MB |
| Whisper Tiny | ~75MB |
| TTS Voice | ~50MB |

---

## Future Considerations

1. **iOS Parity** - Continue aligning with Swift SDK APIs
2. **Kotlin Native** - Potential native targets (iOS, macOS, Linux)
3. **Model Caching** - LRU eviction for multi-model scenarios
4. **Background Processing** - WorkManager integration for downloads
5. **Hybrid Routing** - Cloud fallback when on-device unavailable

---

## References

- [RunAnywhere Swift SDK](../runanywhere-swift/) - iOS implementation
- [runanywhere-commons](../runanywhere-commons/) - C++ core library
- [Sample App](../../examples/android/RunAnywhereAI/) - Reference implementation
