# RunAnywhere React Native SDK Architecture

Overview of the RunAnywhere React Native SDK architecture, including system design, data flow, threading model, and native integration.

---

## Table of Contents

- [System Overview](#system-overview)
- [Multi-Package Structure](#multi-package-structure)
- [Layer Architecture](#layer-architecture)
- [Data Flow](#data-flow)
- [Threading & Performance](#threading--performance)
- [Native Integration](#native-integration)
- [Memory Management](#memory-management)
- [Offline & Resilience](#offline--resilience)
- [Security & Privacy](#security--privacy)
- [Event System](#event-system)
- [Error Handling](#error-handling)

---

## System Overview

The RunAnywhere React Native SDK is a modular, multi-package SDK for on-device AI in React Native applications. It provides:

- **LLM Text Generation** via LlamaCPP (GGUF models)
- **Speech-to-Text** via ONNX Runtime (Whisper models)
- **Text-to-Speech** via ONNX Runtime (Piper TTS)
- **Voice Activity Detection** via Silero VAD

### Design Principles

1. **Modularity** — Only install what you need (core, llamacpp, onnx)
2. **Privacy-First** — All inference runs on-device by default
3. **Performance** — JSI/Nitro for synchronous native calls, C++ for inference
4. **Cross-Platform** — Single TypeScript API for iOS and Android
5. **Consistency** — API matches Swift and Kotlin SDKs

---

## Multi-Package Structure

The SDK is organized as a Yarn workspaces monorepo with three packages:

```
sdk/runanywhere-react-native/
├── packages/
│   ├── core/                    # @runanywhere/core
│   │   ├── src/                 # TypeScript source
│   │   │   ├── Public/          # RunAnywhere main API
│   │   │   ├── Foundation/      # Error types, logging, DI
│   │   │   ├── Infrastructure/  # Events, native bridge
│   │   │   ├── Features/        # Voice session, audio
│   │   │   ├── services/        # Model registry, download, network
│   │   │   └── types/           # TypeScript interfaces
│   │   ├── cpp/                 # C++ HybridObject bridges
│   │   ├── ios/                 # Swift native module
│   │   ├── android/             # Kotlin native module
│   │   └── nitrogen/            # Generated Nitro specs
│   │
│   ├── llamacpp/                # @runanywhere/llamacpp
│   │   ├── src/                 # LlamaCPP module wrapper
│   │   ├── cpp/                 # LlamaCPP native bridge
│   │   ├── ios/                 # iOS podspec, frameworks
│   │   └── android/             # Android gradle, jniLibs
│   │
│   └── onnx/                    # @runanywhere/onnx
│       ├── src/                 # ONNX module wrapper
│       ├── cpp/                 # ONNX native bridge
│       ├── ios/                 # iOS podspec, frameworks
│       └── android/             # Android gradle, jniLibs
│
├── scripts/
│   └── build-react-native.sh    # Build script for native binaries
│
└── package.json                 # Root monorepo config
```

### Package Dependencies

```
@runanywhere/core (required)
    ├── react-native-nitro-modules (JSI bridge)
    ├── react-native-fs (file system)
    ├── react-native-blob-util (downloads)
    └── react-native-device-info (device metrics)

@runanywhere/llamacpp
    └── @runanywhere/core (peer dependency)

@runanywhere/onnx
    └── @runanywhere/core (peer dependency)
```

---

## Layer Architecture

The SDK follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      LAYER 1: TypeScript API                             │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ RunAnywhere (Public API Singleton)                                  │ │
│  │   • initialize(), generate(), chat(), loadModel()                   │ │
│  │   • transcribe(), transcribeFile()                                  │ │
│  │   • synthesize(), speak()                                           │ │
│  │   • Event subscriptions via EventBus                                │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────────────┐ │
│  │ LlamaCPP   │ │   ONNX     │ │ EventBus   │ │  ModelRegistry       │ │
│  │ (LLM)      │ │ (STT/TTS)  │ │ (Events)   │ │  (Model Metadata)    │ │
│  └────────────┘ └────────────┘ └────────────┘ └──────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────┤
│                      LAYER 2: Service Layer                              │
│  ┌────────────┐ ┌──────────────┐ ┌────────────────┐ ┌────────────────┐ │
│  │ Download   │ │ FileSystem   │ │ HTTPService    │ │ Telemetry      │ │
│  │ Service    │ │ (react-native│ │ (axios-based)  │ │ Service        │ │
│  │            │ │   -fs)       │ │                │ │                │ │
│  └────────────┘ └──────────────┘ └────────────────┘ └────────────────┘ │
├─────────────────────────────────────────────────────────────────────────┤
│                      LAYER 3: Native Bridge (Nitro/JSI)                  │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ HybridRunAnywhereCore                                               │ │
│  │   • Nitrogen-generated C++ ↔ TypeScript bindings                    │ │
│  │   • Synchronous JSI calls (no async bridge overhead)                │ │
│  │   • Direct memory sharing between JS and native                     │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────┐              ┌─────────────────────────────┐   │
│  │ HybridRunAnywhere  │              │ HybridRunAnywhereONNX       │   │
│  │ Llama              │              │   • STT inference           │   │
│  │   • LLM inference  │              │   • TTS synthesis           │   │
│  │   • Token stream   │              │   • VAD processing          │   │
│  └────────────────────┘              └─────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────┤
│                      LAYER 4: Native Code                                │
│                                                                          │
│  ┌─────────────────────────────┐    ┌─────────────────────────────────┐│
│  │ iOS (Swift + Obj-C)         │    │ Android (Kotlin + JNI)          ││
│  │  • PlatformAdapter          │    │  • PlatformAdapter              ││
│  │  • KeychainManager          │    │  • EncryptedSharedPreferences   ││
│  │  • SDKLogger                │    │  • SDKLogger                    ││
│  │  • AudioDecoder             │    │  • AudioDecoder                 ││
│  └─────────────────────────────┘    └─────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────────────┤
│                      LAYER 5: C++ Core (runanywhere-commons)             │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ RACommons                                                           │ │
│  │   • Model loading & management                                      │ │
│  │   • Device registration                                             │ │
│  │   • Telemetry collection                                            │ │
│  │   • Secure storage                                                  │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────┐              ┌─────────────────────────────┐   │
│  │ RABackendLLAMACPP  │              │ RABackendONNX               │   │
│  │   • llama.cpp      │              │   • sherpa-onnx             │   │
│  │   • GGUF loader    │              │   • Whisper STT             │   │
│  │   • Token sampler  │              │   • Piper TTS               │   │
│  └────────────────────┘              └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Layer | Responsibility |
|-----------|-------|----------------|
| `RunAnywhere` | TypeScript | Public API singleton, state management |
| `EventBus` | TypeScript | Event subscription and dispatch |
| `ModelRegistry` | TypeScript | Model metadata and discovery |
| `LlamaCPP` | TypeScript | LLM module registration and model declaration |
| `ONNX` | TypeScript | STT/TTS module registration and model declaration |
| `DownloadService` | TypeScript | Model downloads with progress and resume |
| `FileSystem` | TypeScript | Cross-platform file operations |
| `HybridRunAnywhereCore` | Native Bridge | Core native bindings (Nitrogen/JSI) |
| `HybridRunAnywhereLlama` | Native Bridge | LLM inference bindings |
| `HybridRunAnywhereONNX` | Native Bridge | STT/TTS inference bindings |
| `RACommons` | C++ | Core infrastructure, registries |
| `RABackendLLAMACPP` | C++ | LLM inference engine |
| `RABackendONNX` | C++ | STT/TTS/VAD inference engine |

---

## Data Flow

### Text Generation Flow

```
User calls RunAnywhere.generate(prompt, options)
    │
    ├─► [TypeScript] RunAnywhere+TextGeneration.ts
    │       • Validates input, checks model loaded
    │       • Builds generation config JSON
    │
    ├─► [JSI Bridge] HybridRunAnywhereLlama
    │       • Synchronous call to native
    │       • Direct memory access (no serialization)
    │
    ├─► [C++] RABackendLLAMACPP
    │       • llama_model_load (if not loaded)
    │       • llama_tokenize (prompt → tokens)
    │       • llama_decode (inference)
    │       • llama_sample (sampling loop)
    │
    ├─► [Callback] Token streaming (optional)
    │       • Each token sent via JSI callback
    │       • UI updates in real-time
    │
    └─► [Return] GenerationResult
            • text: generated response
            • tokensUsed: total tokens
            • latencyMs: wall time
            • performanceMetrics: tok/s, TTFT
```

### Speech-to-Text Flow

```
User calls RunAnywhere.transcribeFile(audioPath, options)
    │
    ├─► [TypeScript] RunAnywhere+STT.ts
    │       • Validates audio file exists
    │       • Checks STT model loaded
    │
    ├─► [JSI Bridge] HybridRunAnywhereONNX
    │       • Reads audio file
    │       • Decodes to float32 samples
    │
    ├─► [C++] RABackendONNX (Sherpa-ONNX)
    │       • Create recognizer
    │       • Feed audio samples
    │       • Get transcription result
    │
    └─► [Return] STTResult
            • text: transcription
            • segments: word timestamps
            • confidence: overall score
```

### Model Download Flow

```
User calls RunAnywhere.downloadModel(modelId, onProgress)
    │
    ├─► [TypeScript] DownloadService.ts
    │       • Creates download task
    │       • Validates URL, checks storage
    │
    ├─► [Native] react-native-blob-util
    │       • HTTP GET with progress
    │       • Background download support
    │       • Resume capability
    │
    ├─► [Callback] Progress updates
    │       • bytesDownloaded, bytesTotal
    │       • onProgress callback invoked
    │
    ├─► [TypeScript] Archive extraction
    │       • .tar.gz, .tar.bz2, .zip support
    │       • Uses react-native-zip-archive
    │
    └─► [TypeScript] ModelRegistry update
            • localPath set
            • isDownloaded = true
```

---

## Threading & Performance

### JavaScript Thread

- All TypeScript API calls originate here
- Event subscriptions and callbacks execute here
- UI updates must be dispatched to main thread (React handles this)

### JSI Thread (Native)

- Nitrogen/Nitro HybridObjects execute synchronously
- Direct memory access between JS and native
- No JSON serialization overhead
- Blocking calls should be avoided for long operations

### Inference Thread (C++)

- LLM inference runs on dedicated background thread
- Prevents blocking the JS thread
- Token streaming yields back to JS thread per token
- STT/TTS inference also runs on background thread

### Thread Safety

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   JS Thread     │     │   JSI Thread    │     │ Inference Thread│
│   (React)       │────►│   (Nitro)       │────►│   (C++)         │
│                 │     │                 │     │                 │
│ • UI updates    │     │ • Native calls  │     │ • Model loading │
│ • Event handlers│     │ • Memory access │     │ • Token sampling│
│ • State mgmt    │     │ • Callbacks     │     │ • Audio decode  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Performance Optimizations

1. **JSI/Nitro** — No async bridge overhead for native calls
2. **Streaming** — Tokens streamed in real-time, not batched
3. **Background threads** — Long operations don't block UI
4. **Model caching** — Models kept in memory between calls
5. **Lazy loading** — Download to disk, load on first use

---

## Native Integration

### iOS (Swift)

```
packages/core/ios/
├── PlatformAdapter.swift          # Platform abstraction
├── PlatformAdapterBridge.m        # Obj-C bridge
├── KeychainManager.swift          # Secure storage
├── SDKLogger.swift                # Logging
├── AudioDecoder.m                 # Audio file decoding
├── ArchiveUtility.swift           # Tar/zip extraction
└── Binaries/
    └── RACommons.xcframework      # Core C++ framework

packages/llamacpp/ios/
└── Frameworks/
    └── RABackendLLAMACPP.xcframework

packages/onnx/ios/
└── Frameworks/
    ├── RABackendONNX.xcframework
    └── onnxruntime.xcframework
```

### Android (Kotlin)

```
packages/core/android/
├── src/main/java/.../
│   ├── PlatformAdapter.kt         # Platform abstraction
│   ├── KeychainManager.kt         # EncryptedSharedPreferences
│   ├── SDKLogger.kt               # Logging
│   └── AudioDecoder.kt            # Audio file decoding
├── src/main/jniLibs/
│   ├── arm64-v8a/
│   │   ├── librac_commons.so
│   │   ├── librunanywhere_jni.so
│   │   └── libc++_shared.so
│   └── armeabi-v7a/
│       └── ...

packages/llamacpp/android/
└── src/main/jniLibs/
    └── arm64-v8a/
        └── librunanywhere_llamacpp.so

packages/onnx/android/
└── src/main/jniLibs/
    └── arm64-v8a/
        ├── librunanywhere_onnx.so
        └── libonnxruntime.so
```

### Nitrogen/Nitro Code Generation

The native bridge uses Nitrogen (Nitro's code generator) to create C++ HybridObjects:

```
nitro.json → nitrogen generate → Generated bindings

packages/core/nitrogen/generated/
├── HybridRunAnywhereCoreSpec.hpp    # C++ interface
├── HybridRunAnywhereCoreSpec.swift  # Swift implementation
└── ...

packages/llamacpp/nitrogen/generated/
├── HybridRunAnywhereLlamaSpec.hpp
└── ...

packages/onnx/nitrogen/generated/
├── HybridRunAnywhereONNXSpec.hpp
└── ...
```

---

## Memory Management

### Model Memory

- **LLM models**: 500MB–8GB depending on size/quantization
- **STT models**: 50–200MB for Whisper
- **TTS voices**: 20–100MB for Piper

### Memory Lifecycle

```
1. Download     → Model saved to disk (app Documents directory)
2. loadModel()  → Model loaded into RAM (C++ heap)
3. generate()   → Context window allocated
4. unloadModel() → Model freed from RAM
5. deleteModel() → Model removed from disk
```

### Automatic Memory Management

- Models are reference-counted in C++
- Unload on app backgrounding (iOS)
- Low-memory warnings trigger cleanup
- React Native lifecycle callbacks integrated

### Best Practices

```typescript
// Unload when not needed
await RunAnywhere.unloadModel();

// Check available memory before loading large models
const storage = await RunAnywhere.getStorageInfo();
const modelInfo = await RunAnywhere.getModelInfo(modelId);

if (storage.freeSpace > (modelInfo?.memoryRequired ?? 0)) {
  await RunAnywhere.loadModel(modelInfo.localPath);
}
```

---

## Offline & Resilience

### Offline Capabilities

| Feature | Works Offline | Notes |
|---------|---------------|-------|
| LLM Generation | Yes | Requires downloaded model |
| Speech-to-Text | Yes | Requires downloaded model |
| Text-to-Speech | Yes | Requires downloaded model |
| Model Download | No | Requires network |
| Device Registration | No | Queued for when online |
| Telemetry | No | Buffered, sent when online |

### Download Resilience

- **Resume support**: Downloads can be resumed after interruption
- **Retry logic**: Automatic retry on transient failures
- **Storage check**: Validates free space before download
- **Extraction**: Archives extracted in temp dir, moved on success

### Network Recovery

```
Network unavailable → Download paused
Network restored    → Download resumes automatically
App backgrounded    → Download continues (platform-dependent)
App terminated      → Download state persisted, resume on launch
```

---

## Security & Privacy

### Data Privacy

1. **On-Device Processing**: All inference runs locally
2. **No Data Upload**: Prompts and responses never leave device
3. **Optional Telemetry**: Only anonymous metrics (latency, errors)
4. **User Control**: Telemetry can be disabled

### Secure Storage

| Platform | Implementation | Used For |
|----------|----------------|----------|
| iOS | Keychain Services | Device ID, API tokens |
| Android | EncryptedSharedPreferences | Device ID, API tokens |

### API Authentication (Production)

```typescript
// Production mode authentication flow
await RunAnywhere.initialize({
  apiKey: '<YOUR_API_KEY>',
  environment: SDKEnvironment.Production,
});

// SDK authenticates with backend
// JWT tokens stored securely
// Tokens refreshed automatically
```

### Model Integrity

- Models downloaded over HTTPS
- SHA256 checksum verification (optional)
- Models stored in app sandbox (not accessible by other apps)

---

## Event System

### EventBus Architecture

The SDK uses a publish-subscribe pattern for events:

```typescript
// Event categories
enum EventCategory {
  Initialization = 'initialization',
  Generation = 'generation',
  Model = 'model',
  Voice = 'voice',
  Storage = 'storage',
  Network = 'network',
  Error = 'error',
}

// Subscribe to events
const unsubscribe = EventBus.on('Generation', (event) => {
  // Handle event
});

// Publish events (internal)
EventBus.publish('Generation', { type: 'started', ... });
```

### Event Types

| Category | Events |
|----------|--------|
| Initialization | `started`, `completed`, `failed` |
| Generation | `started`, `tokenGenerated`, `completed`, `failed`, `cancelled` |
| Model | `downloadStarted`, `downloadProgress`, `downloadCompleted`, `loadStarted`, `loadCompleted` |
| Voice | `sttStarted`, `sttCompleted`, `ttsStarted`, `ttsCompleted` |
| Storage | `cleared`, `modelDeleted` |

### Native Event Bridge

Native events are forwarded to TypeScript via NativeEventEmitter:

```
C++ Event → Native Bridge → NativeEventEmitter → EventBus → Subscribers
```

---

## Error Handling

### SDKError Structure

```typescript
interface SDKError extends Error {
  code: SDKErrorCode;          // Unique error code
  category: ErrorCategory;      // Error category
  underlyingError?: Error;      // Original error (if wrapped)
  context?: ErrorContext;       // Additional context
  recoverySuggestion?: string;  // How to fix
}
```

### Error Codes

| Code | Category | Description |
|------|----------|-------------|
| `notInitialized` | General | SDK not initialized |
| `alreadyInitialized` | General | SDK already initialized |
| `invalidInput` | General | Invalid input parameters |
| `modelNotFound` | Model | Model not found in registry |
| `modelLoadFailed` | Model | Failed to load model |
| `modelNotLoaded` | Model | Model not loaded into memory |
| `downloadFailed` | Download | Model download failed |
| `insufficientStorage` | Storage | Not enough disk space |
| `insufficientMemory` | Memory | Not enough RAM |
| `generationFailed` | LLM | Text generation failed |
| `sttFailed` | STT | Speech transcription failed |
| `ttsFailed` | TTS | Speech synthesis failed |
| `networkUnavailable` | Network | No network connection |
| `authenticationFailed` | Auth | Invalid API key |

### Error Recovery

```typescript
try {
  await RunAnywhere.generate(prompt);
} catch (error) {
  if (isSDKError(error)) {
    switch (error.code) {
      case SDKErrorCode.modelNotLoaded:
        // Load model and retry
        await RunAnywhere.loadModel(modelPath);
        return RunAnywhere.generate(prompt);

      case SDKErrorCode.insufficientMemory:
        // Unload unused models and retry
        await RunAnywhere.unloadModel();
        return RunAnywhere.generate(prompt);

      default:
        throw error;
    }
  }
}
```

---

## Appendix: File Structure Reference

### Core Package (`@runanywhere/core`)

```
packages/core/src/
├── Public/
│   ├── RunAnywhere.ts               # Main API singleton
│   ├── Events/
│   │   └── EventBus.ts              # Event pub/sub
│   └── Extensions/
│       ├── RunAnywhere+TextGeneration.ts
│       ├── RunAnywhere+STT.ts
│       ├── RunAnywhere+TTS.ts
│       ├── RunAnywhere+VAD.ts
│       ├── RunAnywhere+Models.ts
│       ├── RunAnywhere+Storage.ts
│       ├── RunAnywhere+VoiceAgent.ts
│       ├── RunAnywhere+VoiceSession.ts
│       ├── RunAnywhere+StructuredOutput.ts
│       └── RunAnywhere+Logging.ts
├── Foundation/
│   ├── ErrorTypes/                  # SDKError, error codes
│   ├── Initialization/              # Init state machine
│   ├── Security/                    # Secure storage, device ID
│   ├── Logging/                     # SDKLogger, log levels
│   ├── DependencyInjection/         # ServiceRegistry, ServiceContainer
│   └── Constants/                   # SDK constants
├── Infrastructure/
│   └── Events/                      # Event publishing internals
├── Features/
│   └── VoiceSession/                # Voice session management
├── services/
│   ├── ModelRegistry.ts             # Model metadata store
│   ├── DownloadService.ts           # Model downloads
│   ├── FileSystem.ts                # File operations
│   ├── SystemTTSService.ts          # Platform TTS
│   └── Network/
│       ├── HTTPService.ts           # HTTP client
│       ├── TelemetryService.ts      # Analytics
│       └── APIEndpoints.ts          # API routes
├── types/
│   ├── enums.ts                     # SDK enumerations
│   ├── models.ts                    # Data interfaces
│   ├── events.ts                    # Event types
│   ├── LLMTypes.ts                  # LLM-specific types
│   ├── STTTypes.ts                  # STT-specific types
│   ├── TTSTypes.ts                  # TTS-specific types
│   └── VADTypes.ts                  # VAD-specific types
└── native/
    └── NativeRunAnywhereCore.ts     # Native module accessor
```

### LlamaCPP Package (`@runanywhere/llamacpp`)

```
packages/llamacpp/src/
├── index.ts                         # Package exports
├── LlamaCPP.ts                      # Module API (register, addModel)
├── LlamaCppProvider.ts              # Backend provider registration
├── native/
│   └── NativeRunAnywhereLlama.ts    # Native module accessor
└── specs/
    └── RunAnywhereLlama.nitro.ts    # Nitrogen spec
```

### ONNX Package (`@runanywhere/onnx`)

```
packages/onnx/src/
├── index.ts                         # Package exports
├── ONNX.ts                          # Module API (register, addModel)
├── ONNXProvider.ts                  # Backend provider registration
├── native/
│   └── NativeRunAnywhereONNX.ts     # Native module accessor
└── specs/
    └── RunAnywhereONNX.nitro.ts     # Nitrogen spec
```

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-14 | Initial architecture document |
