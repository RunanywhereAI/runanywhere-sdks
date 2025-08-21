# Voice Pipeline Architecture - RunAnywhere Swift SDK

## Overview

The Voice Pipeline in the RunAnywhere Swift SDK provides comprehensive voice processing capabilities including Voice Activity Detection (VAD), Speech-to-Text (STT), Large Language Model processing (LLM), Text-to-Speech (TTS), and Speaker Diarization. The architecture follows the SDK's standard 5-layer pattern for maximum modularity, testability, and maintainability.

## Table of Contents
1. [Architecture Layers](#🏗️-architecture-layers)
2. [Voice Processing Pipeline](#🔄-voice-processing-pipeline)
3. [Configuration System](#🎛️-configuration-system)
4. [Event System](#📊-event-system)
5. [Service Integration](#🔌-service-integration)
6. [Testing Strategy](#🧪-testing-strategy)
7. [Analytics & Monitoring](#📈-analytics--monitoring)
8. [Usage Examples](#🚀-usage-examples)
9. [Platform Support](#🔧-platform-support)
10. [Migration Guide](#🏁-migration-guide)

## 🏗️ Architecture Layers

### 1. Foundation Layer
**Location**: `Sources/RunAnywhere/Foundation/`

**Components**:
- **ServiceContainer.swift**: Dependency injection container with voice capability integration
- **AdapterRegistry.swift**: Registration and discovery of voice adapters

**Responsibilities**:
- Dependency injection for voice components
- Service discovery and lifecycle management
- Cross-cutting concerns like logging and configuration

### 2. Infrastructure Layer
**Location**: `Sources/RunAnywhere/Infrastructure/Voice/`

**Platform Audio Management**:
```
Infrastructure/Voice/Platform/
├── iOSAudioSession.swift          # iOS-specific audio session management
└── macOSAudioSession.swift        # macOS-specific audio session management
```

**Service Adapters**:
```
Infrastructure/Voice/Adapters/
└── SystemTTSAdapter.swift         # System Text-to-Speech implementation
```

**Responsibilities**:
- Platform-specific audio session configuration
- Audio permissions and interruption handling
- System service integrations (TTS, audio I/O)
- Hardware abstraction layer

### 3. Core Layer
**Location**: `Sources/RunAnywhere/Core/`

**Service Protocols**:
```
Core/Protocols/Voice/
├── VoiceService.swift              # Main voice service interface + VoiceError enum
├── TextToSpeechService.swift       # TTS service contract
├── VADService.swift               # Voice Activity Detection contract
├── SpeakerDiarizationProtocol.swift # Speaker identification contract
└── WakeWordDetector.swift         # Wake word detection interface
```

**Responsibilities**:
- Protocol definitions for voice services
- Core error handling (`VoiceError` enum)
- Service contracts and interfaces
- Framework-agnostic abstractions

### 4. Capabilities Layer
**Location**: `Sources/RunAnywhere/Capabilities/Voice/`

**Main Services**:
```
Capabilities/Voice/Services/
├── VoiceCapabilityService.swift    # Main voice capability orchestrator
├── VoicePipelineManager.swift      # Modular pipeline manager (was ModularVoicePipeline)
├── VoiceAnalyticsService.swift     # Voice processing analytics
├── VoiceSessionManager.swift       # Session lifecycle management
└── DefaultSpeakerDiarization.swift # Default speaker diarization implementation
```

**Processing Handlers**:
```
Capabilities/Voice/Handlers/
├── VADHandler.swift               # Voice Activity Detection processing
├── STTHandler.swift               # Speech-to-Text processing
├── LLMHandler.swift               # LLM processing and streaming
├── TTSHandler.swift               # Text-to-Speech processing
└── SpeakerDiarizationHandler.swift # Speaker identification processing
```

**Specialized Operations**:
```
Capabilities/Voice/Operations/
└── StreamingTTSOperation.swift    # Streaming TTS for real-time speech
```

**Processing Strategies**:
```
Capabilities/Voice/Strategies/
├── VAD/
│   └── SimpleEnergyVAD.swift      # Energy-based voice activity detection
└── AudioSegmentation/
    └── AudioSegmentationStrategy.swift # Audio segmentation strategies
```

**Factories**:
```
Capabilities/Voice/Factories/
└── DiarizationFactory.swift      # Speaker diarization factory
```

**Data Models**:
```
Capabilities/Voice/Models/
└── VoiceSession.swift             # Voice session data model
```

**Responsibilities**:
- Voice capability orchestration and coordination
- Pipeline flow management and component delegation
- Processing handlers for each pipeline stage
- Analytics and performance monitoring
- Session management and state tracking

### 5. Public Layer
**Location**: `Sources/RunAnywhere/Public/`

**Public API**:
```
Public/Extensions/
└── RunAnywhereSDK+Voice.swift     # Public voice API surface
```

**Configuration Models**:
```
Public/Models/Voice/
├── ModularPipelineConfig.swift    # ✅ NEW: Modern modular configuration
├── ModularPipelineEvent.swift     # ✅ NEW: Modular pipeline events
├── VoicePipelineEvent.swift       # Pipeline events
├── VoiceProcessingMode.swift      # Audio processing modes
├── VoiceSTTConfig.swift           # Speech-to-Text configuration
├── VoiceLLMConfig.swift           # LLM configuration
├── VoiceTTSConfig.swift           # Text-to-Speech configuration
└── VADConfig.swift               # Voice Activity Detection configuration
```

**Audio & Transcription Models**:
```
Public/Models/Voice/
├── AudioChunk.swift               # Audio data structures
├── TranscriptionOptions.swift     # Transcription configuration
├── TranscriptionResult.swift      # Transcription results
└── TranscriptionSegment.swift     # Transcription segments
```

**Responsibilities**:
- User-facing API surface
- Configuration and event models
- Public type definitions
- API documentation and examples

## 🔄 Voice Processing Pipeline

### Pipeline Flow
```
Audio Input → VAD → STT → LLM → TTS → Audio Output
              ↓     ↓     ↓     ↓
            Events Events Events Events
```

### Component Interaction
```
VoiceCapabilityService
├── Creates → VoicePipelineManager
├── Manages → VoiceSessionManager
└── Tracks → VoiceAnalyticsService

VoicePipelineManager
├── Delegates → VADHandler
├── Delegates → STTHandler
├── Delegates → LLMHandler
├── Delegates → TTSHandler
└── Delegates → SpeakerDiarizationHandler

Each Handler
├── Uses → Platform Services (via ServiceContainer)
├── Emits → ModularPipelineEvent
└── Processes → Specific pipeline stage
```

### Data Flow
1. **Audio Input**: Raw audio chunks from microphone/file
2. **VAD Processing**: Voice activity detection and speech segmentation
3. **STT Processing**: Speech-to-text conversion with optional speaker diarization
4. **LLM Processing**: Language model processing for conversational AI
5. **TTS Processing**: Text-to-speech synthesis for responses
6. **Event Emission**: Real-time events for UI updates and monitoring

## 🎛️ Configuration System

### Modern Configuration (ModularPipelineConfig)
```swift
let config = ModularPipelineConfig(
    components: [.vad, .stt, .llm, .tts],
    vad: VADConfig(energyThreshold: 0.02),
    stt: VoiceSTTConfig(modelId: "whisper-base", language: "en"),
    llm: VoiceLLMConfig(modelId: "llama-7b"),
    tts: VoiceTTSConfig(voice: "system"),
    streamingEnabled: true
)
```

### Component Selection
Components can be mixed and matched:
- **Transcription Only**: `[.stt]`
- **Transcription with VAD**: `[.vad, .stt]`
- **Conversational (No TTS)**: `[.vad, .stt, .llm]`
- **Full Pipeline**: `[.vad, .stt, .llm, .tts]`

### Convenience Builders
```swift
// Quick configurations
ModularPipelineConfig.transcriptionOnly()
ModularPipelineConfig.transcriptionWithVAD()
ModularPipelineConfig.conversationalNoTTS()
ModularPipelineConfig.fullPipeline()
```

## 📊 Event System

### Event Types
```swift
public enum ModularPipelineEvent {
    // VAD events
    case vadSpeechStart, vadSpeechEnd
    case vadAudioLevel(Float)

    // STT events
    case sttPartialTranscript(String)
    case sttFinalTranscript(String)
    case sttLanguageDetected(String)

    // STT with Speaker Diarization
    case sttPartialTranscriptWithSpeaker(String, SpeakerInfo)
    case sttFinalTranscriptWithSpeaker(String, SpeakerInfo)
    case sttNewSpeakerDetected(SpeakerInfo)

    // LLM events
    case llmThinking, llmStreamStarted
    case llmPartialResponse(String)
    case llmFinalResponse(String)
    case llmStreamToken(String)

    // TTS events
    case ttsStarted, ttsCompleted
    case ttsAudioChunk(Data)

    // Pipeline events
    case pipelineStarted, pipelineCompleted
    case pipelineError(Error)

    // Component lifecycle
    case componentInitializing(String)
    case componentInitialized(String)
    case componentInitializationFailed(String, Error)
    case allComponentsInitialized
}
```

### Event Handling
```swift
extension MyViewModel: VoicePipelineManagerDelegate {
    func pipeline(_ pipeline: VoicePipelineManager, didReceiveEvent event: ModularPipelineEvent) {
        switch event {
        case .sttFinalTranscript(let text):
            // Handle transcription
        case .llmPartialResponse(let response):
            // Handle LLM streaming
        case .ttsStarted:
            // Handle TTS start
        // ... other events
        }
    }
}
```

## 🔌 Service Integration

### Service Discovery
The voice capability integrates with the SDK's service discovery system:

```swift
// Automatic service discovery
let voiceService = serviceContainer.voiceCapabilityService.findVoiceService(for: "whisper-base")
let llmService = serviceContainer.voiceCapabilityService.findLLMService(for: "llama-7b")
let ttsService = serviceContainer.textToSpeechService
```

### Dependency Injection
All components receive dependencies through the ServiceContainer:
- Voice services (STT models)
- LLM services (language models)
- TTS services (text-to-speech)
- Audio session management
- Analytics and monitoring

## 🧪 Testing Strategy

### Unit Testing
Each component can be tested independently:
```swift
// Handler testing
let vadHandler = VADHandler()
let mockVADService = MockVADService()
let result = vadHandler.processAudio(chunk, vad: mockVADService)

// Service testing
let voiceCapability = VoiceCapabilityService()
let pipeline = voiceCapability.createPipeline(config: testConfig)
```

### Integration Testing
```swift
// Full pipeline testing
let sdk = RunAnywhereSDK.shared
let pipeline = sdk.createVoicePipeline(config: ModularPipelineConfig.fullPipeline())
pipeline.delegate = testDelegate
// Test audio processing flow
```

### Mocking
Each layer can be mocked independently:
- Mock voice services for STT testing
- Mock LLM services for conversation testing
- Mock audio sessions for platform testing

## 📈 Analytics & Monitoring

### Voice Analytics
```swift
public struct VoiceMetrics {
    public let totalTranscriptions: Int
    public let averageTranscriptionTime: TimeInterval
    public let totalSpeechDuration: TimeInterval
    public let errorRate: Float
    public let pipelineMetrics: [PipelineMetric]
}
```

### Performance Tracking
- Component initialization times
- Processing latencies per stage
- Memory usage monitoring
- Error rate tracking
- User engagement metrics

## 🚀 Usage Examples

### Basic Transcription
```swift
import RunAnywhereSDK

let sdk = RunAnywhereSDK.shared
let config = ModularPipelineConfig.transcriptionOnly()
let pipeline = sdk.createVoicePipeline(config: config)
pipeline.delegate = self

// Start transcription
let audioStream = createAudioStream()
for await event in sdk.processVoice(audioStream: audioStream, config: config) {
    switch event {
    case .sttFinalTranscript(let text):
        print("Transcribed: \(text)")
    default:
        break
    }
}
```

### Conversational AI
```swift
let config = ModularPipelineConfig.fullPipeline(
    sttModel: "whisper-base",
    llmModel: "llama-7b",
    ttsVoice: "system"
)

let pipeline = sdk.createVoicePipeline(config: config)
pipeline.delegate = self

// Full conversational flow with TTS responses
pipeline.startContinuousMode()
```

### Speaker Diarization
```swift
let diarization = try DiarizationFactory.createFluidAudioDiarization()
let config = ModularPipelineConfig.transcriptionWithVAD()

let pipeline = sdk.createVoicePipeline(
    config: config,
    speakerDiarization: diarization
)

// Receive speaker-aware transcripts
func pipeline(_ pipeline: VoicePipelineManager, didReceiveEvent event: ModularPipelineEvent) {
    switch event {
    case .sttFinalTranscriptWithSpeaker(let text, let speaker):
        print("Speaker \(speaker.id): \(text)")
    case .sttNewSpeakerDetected(let speaker):
        print("New speaker detected: \(speaker.id)")
    default:
        break
    }
}
```

## 🔧 Platform Support

### iOS Features
- AVAudioSession integration
- Background audio processing
- Interruption handling
- Microphone permissions

### macOS Features
- AVAudioEngine integration
- Input device selection
- Audio level monitoring
- System audio routing

### Cross-Platform
- Unified API surface
- Platform-specific optimizations
- Consistent behavior across platforms

## 🏁 Migration Guide

### From Legacy ModularVoicePipeline
```swift
// OLD (no longer supported)
let oldPipeline = ModularVoicePipeline(config: legacyConfig)

// NEW
let newPipeline = sdk.createVoicePipeline(config: modularConfig)
```

### Configuration Migration
```swift
// OLD VoicePipelineConfig (REMOVED)
// This configuration format is no longer supported

// NEW ModularPipelineConfig
let newConfig = ModularPipelineConfig(
    components: [.vad, .stt, .llm, .tts],
    stt: VoiceSTTConfig(modelId: "whisper-base"),
    llm: VoiceLLMConfig(modelId: "llama-7b"),
    tts: VoiceTTSConfig(voice: "system")
)
```

### Delegate Migration
```swift
// OLD
extension MyClass: ModularVoicePipelineDelegate { ... }

// NEW
extension MyClass: VoicePipelineManagerDelegate {
    func pipeline(_ pipeline: VoicePipelineManager, didReceiveEvent event: ModularPipelineEvent) {
        // Handle events (same event types)
    }
}
```

## 🔍 Troubleshooting

### Common Issues

**Pipeline Creation Fails**
- Verify model availability through service discovery
- Check configuration component dependencies
- Ensure proper ServiceContainer initialization

**Audio Processing Issues**
- Check microphone permissions
- Verify audio session configuration
- Monitor audio interruption events

**Performance Issues**
- Use VoiceAnalyticsService to identify bottlenecks
- Consider reducing component complexity
- Monitor memory usage during long sessions

### Debug Logging
```swift
// Enable voice logging
SDKLogger.setLevel(.debug, for: "VoicePipelineManager")
SDKLogger.setLevel(.debug, for: "VoiceCapabilityService")
SDKLogger.setLevel(.debug, for: "VADHandler")
```

## 🧹 Cleanup Required

### Legacy Components (To Be Removed)
The following files contain old logic and should be deleted:

1. **`Core/Protocols/Voice/VoiceOrchestrator.swift`** - ❌ UNUSED
2. **`Core/Services/Voice/DefaultVoiceOrchestrator.swift`** - ❌ UNUSED
3. **`Core/Protocols/Voice/VoiceActivityDetector.swift`** - ❌ UNUSED
4. **`Core/Protocols/Voice/VoicePerformanceMonitor.swift`** - ❌ UNUSED
5. **`Public/Models/Voice/VoicePipelineConfig.swift`** - ❌ OLD CONFIG

### ServiceContainer Cleanup
Remove the unused `voiceOrchestrator` property from ServiceContainer.swift that creates DefaultVoiceOrchestrator but is never used.

## 📚 Related Documentation

- [SDK Architecture Overview](./ARCHITECTURE_V2.md)
- [Service Container Guide](./SERVICE_CONTAINER.md)
- [Model Management](./MODEL_MANAGEMENT.md)
- [Speaker Diarization Integration](./SPEAKER_DIARIZATION.md)

---

*This architecture documentation reflects the completed voice capability refactoring that transformed the monolithic ModularVoicePipeline into a clean, modular, 5-layer architecture following SOLID principles and the SDK's standard patterns.*
