# RunAnywhere SDK Voice Architecture v2.0
## Simplified Architecture with Voice Capabilities

---

## 🚀 Implementation Status Summary

### Current Status: **MVP Foundation Complete** ✅

#### ✅ **Completed** (Phase 1)
- SDK Core voice infrastructure
- Voice protocols and models
- Framework adapter pattern
- Public API extensions
- Basic WhisperKit adapter structure

#### 🚧 **In Progress** (Phase 2)
- WhisperKit module implementation in sample app
- Basic voice service with simulated transcription

#### 📝 **Planned Next Steps (For Complete Voice Pipeline)**
1. **Audio Input** (Microphone Capture)
   - Implement `AudioCapture` class with AVAudioEngine
   - Add microphone permissions to Info.plist
   - Create audio buffer management

2. **WhisperKit Integration** (Speech-to-Text)
   - Add WhisperKit dependency to Package.swift
   - Replace simulated transcription with actual WhisperKit
   - Download and manage Whisper models

3. **Text Generation** (Already Complete ✅)
   - Use existing `RunAnywhereSDK.generate()` method
   - Already integrated in `processVoiceQuery()`

4. **TTS Implementation** (Text-to-Speech)
   - Implement `SystemTTSService` using AVSpeechSynthesizer
   - Add audio playback capability
   - Create voice selection options

5. **Complete Pipeline Integration**
   - Wire up full flow: Audio → STT → LLM → TTS → Audio
   - Add UI for voice interaction
   - Test end-to-end voice conversation

#### ⏭️ **Future Enhancements**
- VAD (Voice Activity Detection)
- TTS (Text-to-Speech)
- Streaming transcription
- Voice session management
- Performance monitoring

### Legend:
- ✅ Completed
- 🚧 In Progress
- 📝 Planned (Next Priority)
- ⏭️ Future (Long-term)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Philosophy](#architecture-philosophy)
3. [Voice Integration Design](#voice-integration-design)
4. [Reusing Existing Components](#reusing-existing-components)
5. [Minimal New Components](#minimal-new-components)
6. [WhisperKit Module Architecture](#whisperkit-module-architecture)
7. [API Design](#api-design)
8. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

This document outlines a simplified, minimal approach to adding voice capabilities to the RunAnywhere SDK. The design maximally reuses existing infrastructure while maintaining the SDK's framework-agnostic nature. Voice support is added through a clean adapter pattern, exactly mirroring the existing LLMSwift integration.

### Core Principles

- **Framework Agnostic**: SDK remains independent of any specific voice framework
- **Maximum Reuse**: 90% of existing components used as-is
- **Minimal Addition**: Only voice-specific protocols and adapters added
- **Clean Separation**: WhisperKit lives in a separate module (like LLMSwift)
- **GPT-4o Voice-like Experience**: Simple question-answering with voice I/O

---

## Architecture Philosophy

### Framework-Agnostic Design

The RunAnywhere SDK maintains complete independence from any specific ML framework. Voice capabilities follow this same philosophy:

1. **SDK Core**: Defines protocols and interfaces for voice capabilities
2. **Framework Adapters**: Bridge between SDK and specific implementations (WhisperKit, OpenAI, etc.)
3. **External Modules**: Actual framework implementations live outside the SDK (like LLMSwift)

### Integration Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
│  (Sample App / Consumer App)                               │
│                                                             │
│  ┌─────────────────────┐  ┌──────────────────────────┐   │
│  │  WhisperKit Module   │  │    LLMSwift Module      │   │
│  │  (Separate Package)  │  │   (Separate Package)    │   │
│  │  • WhisperKitService │  │   • LLMSwiftService    │   │
│  │  • AudioCapture      │  │   • ModelAdapter       │   │
│  │  • SystemTTS         │  │                        │   │
│  └──────────┬──────────┘  └───────────┬──────────────┘   │
│             │                          │                    │
│  ┌──────────▼──────────────────────────▼──────────────┐   │
│  │              Framework Adapters                     │   │
│  │  WhisperKitAdapter    LLMSwiftAdapter              │   │
│  └──────────┬──────────────────────────┬──────────────┘   │
└─────────────┼──────────────────────────┼───────────────────┘
              │                          │
┌─────────────▼──────────────────────────▼───────────────────┐
│                  RunAnywhere SDK Core                       │
│                                                             │
│  ┌───────────────────────────────────────────────────┐     │
│  │              Voice Components (New)                │     │
│  │  Protocols: VoiceService • VoiceFrameworkAdapter  │     │
│  │            VAD • TTS • WakeWord (future)          │     │
│  │  Models: TranscriptionResult • AudioChunk         │     │
│  │         VoiceSession • VADResult                  │     │
│  │  Infrastructure: VoiceAdapterRegistry             │     │
│  │                 VoicePerformanceMonitor           │     │
│  └───────────────────────────────────────────────────┘     │
│                                                             │
│  ┌───────────────────────────────────────────────────┐     │
│  │         Existing Infrastructure (100% Reused)     │     │
│  │  ModelLoading • Downloading • Storage • Memory   │     │
│  │  Hardware Detection • Monitoring • Registry      │     │
│  └───────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

## Voice Integration Design

### Minimal SDK Additions

The SDK only needs to add voice-specific protocols, models, and infrastructure. Everything else reuses existing components:

```
SDK Core Additions:
├── Core/
│   ├── Protocols/Voice/
│   │   ├── VoiceService.swift              # Voice service protocol
│   │   ├── VoiceFrameworkAdapter.swift     # Voice adapter protocol
│   │   ├── VoiceActivityDetector.swift     # VAD protocol
│   │   ├── TextToSpeechService.swift       # TTS protocol
│   │   └── WakeWordDetector.swift          # Wake word protocol (future)
│   │
│   └── Foundation/DependencyInjection/
│       └── VoiceAdapterRegistry.swift      # Voice adapter registry
│
├── Public/
│   ├── Models/Voice/
│   │   ├── TranscriptionResult.swift       # Transcription output
│   │   ├── TranscriptionOptions.swift      # Transcription settings
│   │   ├── AudioChunk.swift                # Audio data wrapper
│   │   ├── TranscriptionSegment.swift      # Streaming segment
│   │   ├── VoiceSessionState.swift         # Session state enum
│   │   ├── VoiceSession.swift              # Session management
│   │   └── VADResult.swift                 # VAD detection results
│   │
│   └── Extensions/
│       ├── RunAnywhereSDK+Voice.swift      # Voice API extensions
│       └── RunAnywhereSDK+VoiceSession.swift # Session management APIs
│
└── Core/Monitoring/
    └── VoicePerformanceMonitor.swift       # Voice performance tracking
```

### Voice Service Protocol

```swift
// Core/Protocols/Voice/VoiceService.swift
public protocol VoiceService: AnyObject {
    /// Initialize the voice service with model path
    func initialize(modelPath: String?) async throws

    /// Transcribe audio to text
    func transcribe(
        audio: Data,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult

    /// Stream transcription with real-time audio
    func transcribeStream(
        audioStream: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionSegment, Error>

    /// Detect language from audio
    func detectLanguage(audio: Data) async throws -> String

    /// Get supported languages
    func supportedLanguages() -> [String]

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model info
    var currentModel: String? { get }

    /// Cleanup resources
    func cleanup() async
}
```

### Voice Framework Adapter Protocol

```swift
// Core/Protocols/Voice/VoiceFrameworkAdapter.swift
public protocol VoiceFrameworkAdapter {
    /// Framework identifier
    var framework: LLMFramework { get }

    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }

    /// Check if adapter can handle model
    func canHandle(model: ModelInfo) -> Bool

    /// Create voice service instance
    func createService() -> VoiceService

    /// Load model and return service
    func loadModel(_ model: ModelInfo) async throws -> VoiceService
}
```

---

## Reusing Existing Components

### Components Used As-Is (100% Reuse)

All existing SDK components are reused without modification:

| Component | Usage for Voice |
|-----------|----------------|
| **ModelLoadingService** | Load Whisper/TTS models using existing pipeline |
| **RegistryService** | Register and discover voice models |
| **AlamofireDownloadService** | Download voice models with progress tracking |
| **SimplifiedFileManager** | Store voice models in framework-specific folders |
| **MemoryService** | Manage memory for voice models |
| **HardwareDetectionService** | Optimize voice processing for hardware |
| **PerformanceMonitor** | Track voice transcription/synthesis performance |
| **GenerationService** | Generate text responses for voice queries |
| **StreamingService** | Stream voice responses (reuse streaming patterns) |
| **ErrorRecoveryService** | Handle voice-specific errors |
| **ConfigurationService** | Manage voice configuration |
| **ValidationService** | Validate voice model formats |

### Example: Loading a Whisper Model

```swift
// Using existing ModelLoadingService - no changes needed!
let whisperModel = ModelInfo(
    id: "whisper-large-v3",
    name: "Whisper Large v3",
    format: .coreML,
    compatibleFrameworks: [.whisperKit],
    estimatedMemory: 1_060_000_000
)

// Register model in existing registry
await serviceContainer.modelRegistry.registerModel(whisperModel)

// Download using existing service
let downloadTask = try await serviceContainer.downloadService.downloadModel(
    whisperModel,
    progressHandler: { progress in
        print("Downloading: \(progress)%")
    }
)

// Load using existing loading service
let loadedModel = try await serviceContainer.modelLoadingService.loadModel("whisper-large-v3")

// Memory managed automatically by existing MemoryService
// Hardware optimization by existing HardwareDetectionService
// Performance tracked by existing PerformanceMonitor
```

---

## Minimal New Components

### What We Actually Need to Add

Only these minimal components are needed in the SDK:

1. **Voice Protocols** (5 files)
   - `VoiceService.swift` - Protocol for voice operations
   - `VoiceFrameworkAdapter.swift` - Protocol for voice framework adapters
   - `VoiceActivityDetector.swift` - Protocol for VAD operations
   - `TextToSpeechService.swift` - Protocol for TTS operations
   - `WakeWordDetector.swift` - Wake word detection protocol (future)

2. **Voice Models** (7 files)
   - `TranscriptionResult.swift` - Output from speech recognition
   - `TranscriptionOptions.swift` - Configuration for transcription
   - `AudioChunk.swift` - Audio data wrapper
   - `TranscriptionSegment.swift` - Streaming segment model
   - `VoiceSessionState.swift` - Voice session state management
   - `VoiceSession.swift` - Voice session management
   - `VADResult.swift` - VAD detection results

3. **Voice Infrastructure** (2 files)
   - `VoiceAdapterRegistry.swift` - Registry for voice adapters
   - `VoicePerformanceMonitor.swift` - Voice-specific performance tracking

4. **API Extensions** (2 files)
   - `RunAnywhereSDK+Voice.swift` - Public voice APIs
   - `RunAnywhereSDK+VoiceSession.swift` - Voice session management APIs

5. **Enum Updates** (2 existing files)
   ```swift
   // Add to existing LLMFramework enum
   case whisperKit = "WhisperKit"
   case openAIWhisper = "OpenAIWhisper"

   // Add to existing ModelArchitecture enum
   case whisper = "whisper"
   case wav2vec2 = "wav2vec2"
   ```

### Simple Voice Flow - Complete Pipeline

```
Audio Input → WhisperKit Module → Text → Existing Generation Service → Text → TTS Module → Audio Output
```

#### Pipeline Components Status:

| Component | Status | Implementation | Notes |
|-----------|--------|---------------|-------|
| **1. Audio Input** | 📝 Planned | `AudioCapture.swift` | Microphone capture with AVAudioEngine |
| **2. WhisperKit STT** | 🚧 In Progress | `WhisperKitService.swift` | Structure ready, needs WhisperKit library |
| **3. Text Generation** | ✅ Complete | `RunAnywhereSDK.generate()` | Existing service works |
| **4. TTS Output** | 📝 Planned | `SystemTTSService.swift` | AVSpeechSynthesizer wrapper |
| **5. Audio Output** | 📝 Planned | Built into TTS | Audio playback via speaker |

#### Detailed Pipeline Implementation Plan:

**1. Audio Input Module** (Not yet implemented)
```swift
// AudioCapture.swift - Needs implementation
class AudioCapture {
    - AVAudioEngine setup
    - 16kHz mono recording
    - Real-time audio streaming
    - Permission handling
}
```

**2. WhisperKit Processing** (Structure ready)
```swift
// WhisperKitService.swift - Currently simulated
- Needs: WhisperKit dependency
- Needs: Model download
- Ready: Service structure
```

**3. LLM Processing** (✅ Already working)
```swift
// RunAnywhereSDK+Voice.swift - processVoiceQuery()
- Transcription → generate() → Response
- Already implemented and working
```

**4. TTS Output** (Not yet implemented)
```swift
// SystemTTSService.swift - Needs implementation
class SystemTTSService: TextToSpeechService {
    - AVSpeechSynthesizer setup
    - Voice selection
    - Audio playback
}
```

The entire voice pipeline reuses existing infrastructure:

1. **Model Loading**: Existing `ModelLoadingService` loads voice models
2. **Downloading**: Existing `AlamofireDownloadService` downloads models
3. **Storage**: Existing `SimplifiedFileManager` stores models
4. **Memory**: Existing `MemoryService` manages voice model memory
5. **Generation**: Existing `GenerationService` handles text responses

---

## WhisperKit Module Architecture

### Separate WhisperKit Module (Like LLMSwift)

The WhisperKit implementation lives in a separate module in the sample app, NOT in the SDK:

```
examples/ios/RunAnywhereAI/Core/Services/
├── WhisperKit/
│   ├── WhisperKitAdapter.swift          # Implements VoiceFrameworkAdapter
│   ├── WhisperKitService.swift          # Implements VoiceService
│   ├── WhisperKitConfiguration.swift    # WhisperKit-specific config
│   └── WhisperModelManager.swift        # Model download and management
│
├── Audio/
│   ├── AudioCapture.swift               # Microphone audio capture
│   ├── AudioProcessor.swift             # Audio processing pipeline
│   ├── SimpleVAD.swift                  # Voice activity detection
│   └── StreamingTranscriber.swift       # Real-time transcription
│
└── TTS/
    ├── SystemTTSService.swift           # AVSpeechSynthesizer wrapper
    ├── TTSConfiguration.swift           # TTS settings
    └── VoiceManager.swift               # Voice selection and management
```

### WhisperKit Adapter Implementation

```swift
// In Sample App, NOT in SDK
import RunAnywhere
import WhisperKit

public class WhisperKitAdapter: VoiceFrameworkAdapter {
    public let framework: LLMFramework = .whisperKit
    public let supportedFormats: [ModelFormat] = [.coreML, .mlmodel]

    public func canHandle(model: ModelInfo) -> Bool {
        return model.compatibleFrameworks.contains(.whisperKit)
    }

    public func createService() -> VoiceService {
        return WhisperKitService()
    }

    public func loadModel(_ model: ModelInfo) async throws -> VoiceService {
        let service = WhisperKitService()
        try await service.loadWhisperModel(model.localPath?.path ?? "")
        return service
    }
}
```

### WhisperKit Service Implementation

```swift
// In Sample App, NOT in SDK
import RunAnywhere
import WhisperKit
import AVFoundation

public class WhisperKitService: VoiceService {
    private var whisperKit: WhisperKit?
    private var currentModelPath: String?

    public func initialize(modelPath: String?) async throws {
        // Initialize WhisperKit with specific model
        let model = modelPath ?? "openai_whisper-base"
        self.whisperKit = try await WhisperKit(
            model: model,
            computeOptions: ModelComputeOptions(
                computeUnits: .cpuAndNeuralEngine
            )
        )
        self.currentModelPath = model
    }

    public func transcribe(
        audio: Data,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        guard let whisperKit = whisperKit else {
            throw RunAnywhereError.serviceNotInitialized
        }

        // Convert audio to float array (16kHz)
        let audioArray = audio.toFloatArray()

        // Transcribe with options
        let result = try await whisperKit.transcribe(
            audioArray: audioArray,
            decodeOptions: DecodingOptions(
                language: options.language?.rawValue,
                task: options.task == .translate ? "translate" : "transcribe",
                wordTimestamps: options.enableWordTimestamps
            )
        )

        // Map to RunAnywhere types
        return TranscriptionResult(
            text: result.text,
            segments: mapSegments(result.segments),
            language: result.language,
            confidence: result.avgLogprob ?? 0,
            duration: TimeInterval(audioArray.count) / 16000.0
        )
    }

    public func transcribeStream(
        audioStream: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionSegment, Error> {
        // Implementation for streaming transcription
        // This would use WhisperKit's AudioStreamTranscriber
        AsyncThrowingStream { continuation in
            // Streaming implementation
        }
    }

    public func detectLanguage(audio: Data) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw RunAnywhereError.serviceNotInitialized
        }
        let result = try await whisperKit.detectLanguage(
            audioArray: audio.toFloatArray()
        )
        return result.bestLanguage?.key ?? "unknown"
    }

    public func supportedLanguages() -> [String] {
        return ["en", "es", "fr", "de", "it", "pt", "ru", "zh", "ja", "ko"]
    }

    public var isReady: Bool {
        return whisperKit != nil
    }

    public var currentModel: String? {
        return currentModelPath
    }

    public func cleanup() async {
        whisperKit = nil
        currentModelPath = nil
    }
}
```

### Audio Capture Implementation (Required for Pipeline)

```swift
// In Sample App - Audio capture for voice input
import AVFoundation

public class AudioCapture {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode
    private var audioFormat: AVAudioFormat
    private var audioBuffer: [Float] = []

    public init() {
        inputNode = audioEngine.inputNode
        // 16kHz mono for Whisper
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
    }

    // For non-streaming recording (MVP approach)
    public func recordAudio(duration: TimeInterval) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            var recordedData = Data()

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: audioFormat
            ) { buffer, _ in
                let data = self.bufferToData(buffer)
                recordedData.append(data)
            }

            do {
                try audioEngine.start()

                // Stop after duration
                Task {
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    self.audioEngine.stop()
                    self.inputNode.removeTap(onBus: 0)
                    continuation.resume(returning: recordedData)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let audioBuffer = buffer.floatChannelData![0]
        let frameLength = Int(buffer.frameLength)
        return Data(bytes: audioBuffer, count: frameLength * MemoryLayout<Float>.size)
    }

    // Request microphone permission
    public static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
```

---

## API Design

### Simple Public Voice API

```swift
// RunAnywhereSDK+Voice.swift
public extension RunAnywhereSDK {

    // MARK: - Framework Registration (like existing pattern)

    /// Register a voice framework adapter
    func registerVoiceFrameworkAdapter(_ adapter: VoiceFrameworkAdapter) {
        serviceContainer.voiceAdapterRegistry.register(adapter)
    }

    // MARK: - Simple Voice Operations

    /// Transcribe audio to text
    func transcribe(
        audio: Data,
        modelId: String = "whisper-large-v3"
    ) async throws -> TranscriptionResult {
        try await ensureInitialized()

        // Load model using existing infrastructure
        let loadedModel = try await serviceContainer.modelLoadingService.loadModel(modelId)

        // Get voice service from loaded model
        guard let voiceService = loadedModel.service as? VoiceService else {
            throw RunAnywhereError.incompatibleModel
        }

        // Transcribe
        return try await voiceService.transcribe(
            audio: audio,
            options: TranscriptionOptions()
        )
    }

    // MARK: - Voice + Generation Pipeline

    /// Process voice query (STT → LLM → TTS)
    func processVoiceQuery(
        audio: Data,
        voiceModelId: String = "whisper-large-v3",
        llmModelId: String? = nil  // Uses current loaded model if nil
    ) async throws -> VoiceResponse {
        try await ensureInitialized()

        // 1. Transcribe audio to text
        let transcription = try await transcribe(audio: audio, modelId: voiceModelId)

        // 2. Generate response using existing generation service
        let textResponse = try await generate(
            prompt: transcription.text,
            options: GenerationOptions()
        )

        // 3. Return combined response (TTS optional for MVP)
        return VoiceResponse(
            inputText: transcription.text,
            outputText: textResponse.text,
            outputAudio: nil  // TTS can be added later
        )
    }
}

// Simple Voice Response Model
public struct VoiceResponse {
    public let inputText: String
    public let outputText: String
    public let outputAudio: Data?  // Optional TTS output
}
```

### Complete End-to-End Voice Pipeline Example

```swift
// In Sample App - Complete Voice Conversation Loop
import RunAnywhere
import AVFoundation

class VoiceConversationManager {
    let sdk = RunAnywhereSDK.shared
    let audioCapture = AudioCapture()
    let ttsService = SystemTTSService()

    init() {
        // Register WhisperKit adapter at startup
        sdk.registerVoiceFrameworkAdapter(WhisperKitAdapter())
    }

    // Complete voice conversation flow
    func startVoiceConversation() async throws {
        // 1. REQUEST MICROPHONE PERMISSION
        guard await AudioCapture.requestMicrophonePermission() else {
            throw VoiceError.microphonePermissionDenied
        }

        // 2. AUDIO INPUT - Record user's voice
        print("🎤 Recording...")
        let audioData = try await audioCapture.recordAudio(duration: 5.0)

        // 3. WHISPERKIT STT - Convert speech to text
        print("🔄 Transcribing...")
        let transcription = try await sdk.transcribe(
            audio: audioData,
            modelId: "whisper-base"
        )
        print("📝 User said: \(transcription.text)")

        // 4. LLM PROCESSING - Generate response
        print("🤖 Generating response...")
        let response = try await sdk.generate(
            prompt: transcription.text,
            options: GenerationOptions()
        )
        print("💬 Assistant: \(response.text)")

        // 5. TTS OUTPUT - Convert response to speech
        print("🔊 Speaking response...")
        await ttsService.speak(text: response.text, voice: "en-US")

        print("✅ Conversation complete!")
    }

    // Alternative: Using processVoiceQuery for integrated flow
    func processVoiceQueryWithTTS() async throws {
        // Record audio
        let audioData = try await audioCapture.recordAudio(duration: 5.0)

        // Process through complete pipeline
        let voiceResponse = try await sdk.processVoiceQuery(
            audio: audioData,
            voiceModelId: "whisper-base"
        )

        // Speak the response
        await ttsService.speak(text: voiceResponse.outputText, voice: "en-US")
    }
}

// Usage in SwiftUI View
struct VoiceAssistantView: View {
    @State private var isRecording = false
    @State private var transcription = ""
    @State private var response = ""
    let voiceManager = VoiceConversationManager()

    var body: some View {
        VStack {
            Text("Transcription: \(transcription)")
            Text("Response: \(response)")

            Button(action: startConversation) {
                Image(systemName: isRecording ? "stop.circle" : "mic.circle")
                    .font(.system(size: 60))
                    .foregroundColor(isRecording ? .red : .blue)
            }
        }
    }

    func startConversation() {
        Task {
            do {
                try await voiceManager.startVoiceConversation()
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
```

### Pipeline Data Flow

```
1. Audio Input (AudioCapture)
   ↓ Data (PCM 16kHz mono)
2. WhisperKit STT (WhisperKitService)
   ↓ String (transcribed text)
3. LLM Processing (RunAnywhereSDK.generate)
   ↓ String (generated response)
4. TTS Output (SystemTTSService)
   ↓ Audio (synthesized speech)
5. Speaker Output (AVSpeechSynthesizer)
```

---

## Implementation Roadmap

### Phase 1: SDK Voice Protocols & Models (Week 1) ✅ **COMPLETED**
**Core SDK additions - protocols, models, and infrastructure**

- [x] ✅ Add `whisperKit` and `openAIWhisper` cases to `LLMFramework` enum
- [x] ✅ Add `whisper` and `wav2vec2` cases to `ModelArchitecture` enum
- [x] ✅ Create voice protocols:
  - [x] ✅ `VoiceService` protocol
  - [x] ✅ `VoiceFrameworkAdapter` protocol
  - [ ] ⏭️ `VoiceActivityDetector` protocol (FUTURE)
  - [ ] ⏭️ `TextToSpeechService` protocol (FUTURE)
  - [ ] ⏭️ `WakeWordDetector` protocol (FUTURE)
- [x] ✅ Create voice models:
  - [x] ✅ `TranscriptionResult`, `TranscriptionOptions` (IMPLEMENTED)
  - [ ] ⏭️ `AudioChunk` (FUTURE - for streaming)
  - [ ] ⏭️ `TranscriptionSegment`, `VoiceSessionState` (FUTURE)
  - [ ] ⏭️ `VoiceSession`, `VADResult` (FUTURE)
- [x] ✅ Create infrastructure components:
  - [x] ✅ `VoiceAdapterRegistry` implementation (simplified for MVP)
  - [ ] ⏭️ `VoicePerformanceMonitor` implementation (FUTURE)
- [x] ✅ Create API extensions:
  - [x] ✅ `RunAnywhereSDK+Voice.swift` extension
  - [ ] ⏭️ `RunAnywhereSDK+VoiceSession.swift` extension (FUTURE)
- [x] ✅ Update SDK with voice adapter storage

### Phase 2: Complete Voice Pipeline Implementation 🚧 **IN PROGRESS**
**End-to-end voice flow: Audio Input → STT → LLM → TTS → Audio Output**

#### Audio Input (Microphone Capture)
- [ ] 📝 `AudioCapture` class implementation:
  - [ ] 📝 AVAudioEngine setup for recording
  - [ ] 📝 16kHz mono audio format configuration
  - [ ] 📝 Audio buffer to Data conversion
  - [ ] 📝 Microphone permission handling
- [ ] 📝 Add `NSMicrophoneUsageDescription` to Info.plist

#### WhisperKit Integration (Speech-to-Text)
- [x] ✅ `WhisperKitAdapter` (implements `VoiceFrameworkAdapter`)
- [x] ✅ `WhisperKitService` (structure ready, simulated transcription)
- [ ] 📝 Add WhisperKit dependency to Package.swift
- [ ] 📝 Replace simulated transcription with actual WhisperKit
- [ ] 📝 Implement Whisper model download and management
- [ ] 📝 Test with various audio formats and languages

#### Text Generation (LLM Processing)
- [x] ✅ Integration in `processVoiceQuery()` method
- [x] ✅ Uses existing `RunAnywhereSDK.generate()` service
- [x] ✅ Text → LLM → Response flow complete

#### TTS Implementation (Text-to-Speech)
- [ ] 📝 Create `TextToSpeechService` protocol (already defined in Phase 1)
- [ ] 📝 `SystemTTSService` implementation:
  - [ ] 📝 AVSpeechSynthesizer setup
  - [ ] 📝 Voice selection and configuration
  - [ ] 📝 Speech rate and pitch controls
  - [ ] 📝 Audio playback handling
- [ ] 📝 Update `processVoiceQuery()` to include TTS output
- [ ] 📝 Add `VoiceResponse` with audio output support

#### Complete Pipeline Integration
- [ ] 📝 Wire up full flow in sample app
- [ ] 📝 Create voice conversation loop
- [ ] 📝 Add error handling for each stage
- [ ] 📝 Test end-to-end voice interaction

### Phase 3: TTS & Complete Voice Loop (Week 4) ⏭️ **FUTURE**
**Text-to-speech and full voice interaction**

- [ ] ⏭️ Implement TTS components:
  - [ ] ⏭️ `SystemTTSService` (AVSpeechSynthesizer)
  - [ ] ⏭️ `TTSConfiguration` for voice settings
  - [ ] ⏭️ `VoiceManager` for voice selection
- [ ] ⏭️ Complete voice pipeline:
  - [ ] ⏭️ Audio capture → VAD → STT
  - [ ] ⏭️ LLM processing integration
  - [ ] ⏭️ TTS → Audio playback
- [ ] ⏭️ Implement voice session management
- [ ] ⏭️ Add performance monitoring hooks

### Phase 4: Sample App Integration (Week 5) 📝 **PLANNED**
**UI and user experience**

- [ ] 📝 Create voice UI components:
  - [ ] 📝 Voice recording button
  - [ ] 📝 Transcription display
  - [ ] 📝 Voice settings panel
- [ ] 📝 Implement voice view model
- [ ] 📝 Add microphone permissions handling
- [ ] 📝 Create voice session examples
- [ ] ⏭️ Add streaming transcription demo (FUTURE)
- [ ] 📝 Test end-to-end voice interactions

### Phase 5: Testing & Optimization (Week 6) 📝 **PLANNED**
**Quality assurance and performance**

- [ ] 📝 Unit tests for all voice components
- [ ] 📝 Integration tests for voice pipeline
- [ ] ⏭️ Performance benchmarks:
  - [ ] ⏭️ Transcription RTF < 1.0
  - [ ] ⏭️ End-to-end latency < 700ms
  - [ ] ⏭️ Memory usage optimization
- [ ] ⏭️ Device-specific optimizations
- [ ] 📝 Error handling and recovery
- [ ] 📝 Documentation and examples

### TTS Implementation (Required for Complete Pipeline)

```swift
// Core/Protocols/Voice/TextToSpeechService.swift
public protocol TextToSpeechService: AnyObject {
    func speak(text: String, voice: String?) async
    func stop()
    var isSpeaking: Bool { get }
    var availableVoices: [String] { get }
}

// In Sample App - System TTS Implementation
import AVFoundation

public class SystemTTSService: NSObject, TextToSpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(text: String, voice: String?) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let utterance = AVSpeechUtterance(string: text)

            // Configure voice
            if let voiceIdentifier = voice {
                utterance.voice = AVSpeechSynthesisVoice(language: voiceIdentifier)
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            }

            // Configure speech parameters
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0

            // Start speaking
            synthesizer.speak(utterance)
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    public var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }

    public var availableVoices: [String] {
        return AVSpeechSynthesisVoice.speechVoices()
            .map { $0.language }
            .unique() // Remove duplicates
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SystemTTSService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                 didFinish utterance: AVSpeechUtterance) {
        continuation?.resume()
        continuation = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                 didCancel utterance: AVSpeechUtterance) {
        continuation?.resume()
        continuation = nil
    }
}
```

## Additional Voice Components

### Voice Adapter Registry Implementation

```swift
// Core/Foundation/DependencyInjection/VoiceAdapterRegistry.swift
internal protocol VoiceAdapterRegistry {
    func register(_ adapter: VoiceFrameworkAdapter)
    func getAdapter(for framework: LLMFramework) -> VoiceFrameworkAdapter?
    func findBestAdapter(for model: ModelInfo) -> VoiceFrameworkAdapter?
    func getAvailableVoiceFrameworks() -> [LLMFramework]
}

internal class VoiceAdapterRegistryImpl: VoiceAdapterRegistry {
    private var adapters: [LLMFramework: VoiceFrameworkAdapter] = [:]

    func register(_ adapter: VoiceFrameworkAdapter) {
        adapters[adapter.framework] = adapter
    }

    func getAdapter(for framework: LLMFramework) -> VoiceFrameworkAdapter? {
        return adapters[framework]
    }

    func findBestAdapter(for model: ModelInfo) -> VoiceFrameworkAdapter? {
        // Try compatible frameworks
        for framework in model.compatibleFrameworks {
            if let adapter = adapters[framework] {
                return adapter
            }
        }
        return nil
    }

    func getAvailableVoiceFrameworks() -> [LLMFramework] {
        return Array(adapters.keys)
    }
}
```

### Voice Activity Detection (VAD)

```swift
// Core/Protocols/Voice/VoiceActivityDetector.swift
public protocol VoiceActivityDetector {
    func detectActivity(in audio: Data) -> VADResult
    func detectActivityStream(
        audioStream: AsyncStream<AudioChunk>
    ) -> AsyncStream<VADSegment>
    var sensitivity: VADSensitivity { get set }
}

public struct VADResult {
    public let hasSpeech: Bool
    public let speechSegments: [SpeechSegment]
    public let silenceRatio: Float
    public let energyLevel: Float
}

public struct SpeechSegment {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
}

public struct VADSegment {
    public let timestamp: TimeInterval
    public let isSpeech: Bool
    public let energy: Float
    public let zeroCrossingRate: Float
}

public enum VADSensitivity {
    case low    // Energy threshold: 0.01
    case medium // Energy threshold: 0.05
    case high   // Energy threshold: 0.1

    var energyThreshold: Float {
        switch self {
        case .low: return 0.01
        case .medium: return 0.05
        case .high: return 0.1
        }
    }
}

// In Sample App - VAD Implementation
public class SimpleVAD: VoiceActivityDetector {
    public var sensitivity: VADSensitivity = .medium
    private let windowSize: Int = 320 // 20ms at 16kHz

    public func detectActivity(in audio: Data) -> VADResult {
        let samples = audio.toFloatArray()
        var speechSegments: [SpeechSegment] = []
        var currentSegmentStart: TimeInterval?
        let sampleRate: Float = 16000.0

        // Process in windows
        for i in stride(from: 0, to: samples.count, by: windowSize) {
            let window = Array(samples[i..<min(i + windowSize, samples.count)])
            let energy = calculateEnergy(window)
            let isSpeech = energy > sensitivity.energyThreshold
            let timestamp = Float(i) / sampleRate

            if isSpeech && currentSegmentStart == nil {
                currentSegmentStart = TimeInterval(timestamp)
            } else if !isSpeech && currentSegmentStart != nil {
                speechSegments.append(SpeechSegment(
                    startTime: currentSegmentStart!,
                    endTime: TimeInterval(timestamp),
                    confidence: 0.8
                ))
                currentSegmentStart = nil
            }
        }

        // Close final segment if needed
        if let start = currentSegmentStart {
            speechSegments.append(SpeechSegment(
                startTime: start,
                endTime: TimeInterval(samples.count) / TimeInterval(sampleRate),
                confidence: 0.8
            ))
        }

        let totalDuration = Float(samples.count) / sampleRate
        let speechDuration = speechSegments.reduce(0) { $0 + Float($1.endTime - $1.startTime) }
        let silenceRatio = 1.0 - (speechDuration / totalDuration)

        return VADResult(
            hasSpeech: !speechSegments.isEmpty,
            speechSegments: speechSegments,
            silenceRatio: silenceRatio,
            energyLevel: calculateEnergy(samples)
        )
    }

    public func detectActivityStream(
        audioStream: AsyncStream<AudioChunk>
    ) -> AsyncStream<VADSegment> {
        AsyncStream { continuation in
            Task {
                for await chunk in audioStream {
                    let energy = calculateEnergy(chunk.data.toFloatArray())
                    let zcr = calculateZeroCrossingRate(chunk.data.toFloatArray())

                    continuation.yield(VADSegment(
                        timestamp: chunk.timestamp,
                        isSpeech: energy > sensitivity.energyThreshold,
                        energy: energy,
                        zeroCrossingRate: zcr
                    ))
                }
                continuation.finish()
            }
        }
    }

    private func calculateEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        return sum / Float(samples.count)
    }

    private func calculateZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i-1] >= 0 && samples[i] < 0) ||
               (samples[i-1] < 0 && samples[i] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count - 1)
    }
}
```

### Voice Session Management

```swift
// Public/Models/Voice/VoiceSession.swift
public class VoiceSession {
    public let id: String
    public let startTime: Date
    public private(set) var endTime: Date?
    public private(set) var state: VoiceSessionState
    public private(set) var transcripts: [TranscriptionResult] = []
    public private(set) var audioData: [AudioChunk] = []
    public let configuration: VoiceSessionConfig

    public init(configuration: VoiceSessionConfig) {
        self.id = UUID().uuidString
        self.startTime = Date()
        self.state = .idle
        self.configuration = configuration
    }

    public func addTranscript(_ transcript: TranscriptionResult) {
        transcripts.append(transcript)
    }

    public func addAudioChunk(_ chunk: AudioChunk) {
        audioData.append(chunk)
    }

    public func updateState(_ newState: VoiceSessionState) {
        state = newState
        if newState == .ended {
            endTime = Date()
        }
    }

    public var duration: TimeInterval {
        if let endTime = endTime {
            return endTime.timeIntervalSince(startTime)
        }
        return Date().timeIntervalSince(startTime)
    }

    public var totalTranscribedText: String {
        return transcripts.map { $0.text }.joined(separator: " ")
    }
}

public struct VoiceSessionConfig {
    public let recognitionModel: String
    public let ttsModel: String?
    public let enableVAD: Bool
    public let enableWordTimestamps: Bool
    public let enableStreaming: Bool
    public let maxSessionDuration: TimeInterval
    public let silenceTimeout: TimeInterval

    public init(
        recognitionModel: String = "whisper-large-v3",
        ttsModel: String? = nil,
        enableVAD: Bool = true,
        enableWordTimestamps: Bool = false,
        enableStreaming: Bool = true,
        maxSessionDuration: TimeInterval = 300, // 5 minutes
        silenceTimeout: TimeInterval = 3.0
    ) {
        self.recognitionModel = recognitionModel
        self.ttsModel = ttsModel
        self.enableVAD = enableVAD
        self.enableWordTimestamps = enableWordTimestamps
        self.enableStreaming = enableStreaming
        self.maxSessionDuration = maxSessionDuration
        self.silenceTimeout = silenceTimeout
    }
}

// Public/Extensions/RunAnywhereSDK+VoiceSession.swift
public extension RunAnywhereSDK {

    /// Start a new voice session
    func startVoiceSession(config: VoiceSessionConfig) async throws -> VoiceSession {
        let session = VoiceSession(configuration: config)

        // Initialize voice service with model
        let voiceService = try await getVoiceService(modelId: config.recognitionModel)
        try await voiceService.initialize(modelPath: config.recognitionModel)

        session.updateState(.listening)

        // Store session
        currentVoiceSession = session

        return session
    }

    /// End current voice session
    func endVoiceSession() async throws {
        guard let session = currentVoiceSession else {
            throw VoiceError.noActiveSession
        }

        session.updateState(.ended)
        currentVoiceSession = nil

        // Cleanup voice service
        if let voiceService = loadedVoiceService {
            await voiceService.cleanup()
        }
    }

    /// Get current voice session
    var currentSession: VoiceSession? {
        return currentVoiceSession
    }

    private var currentVoiceSession: VoiceSession?
    private var loadedVoiceService: VoiceService?
}
```

### Wake Word Detection (Future Enhancement)

```swift
// Core/Protocols/Voice/WakeWordDetector.swift (Future)
public protocol WakeWordDetector {
    func initialize(wakeWords: [String]) async throws
    func startListening() async
    func stopListening() async
    var onWakeWordDetected: ((String) -> Void)? { get set }
    var sensitivity: Float { get set }
}

// Example implementation structure (not implemented yet)
/*
public class PicovoiceWakeWordDetector: WakeWordDetector {
    // Would use Picovoice Porcupine for wake word detection
    // Requires separate licensing
}

public class OpenWakeWordDetector: WakeWordDetector {
    // Would use OpenWakeWord (Apache 2.0 license)
    // For open-source alternative
}
*/
```

### Voice Performance Monitoring

```swift
// Core/Monitoring/VoicePerformanceMonitor.swift
public protocol VoicePerformanceMonitor {
    func trackTranscription(duration: TimeInterval, audioLength: TimeInterval, model: String)
    func trackTTS(duration: TimeInterval, textLength: Int, voice: String)
    func trackVAD(processingTime: TimeInterval, audioLength: TimeInterval)
    func getMetrics() -> VoicePerformanceMetrics
}

public struct VoicePerformanceMetrics {
    public let averageTranscriptionRTF: Float // Real-time factor
    public let averageTTSLatency: TimeInterval
    public let averageVADLatency: TimeInterval
    public let totalTranscriptions: Int
    public let totalTTSSynthesis: Int
    public let averageWordErrorRate: Float?
    public let modelPerformance: [String: ModelMetrics]
}

public struct ModelMetrics {
    public let modelName: String
    public let averageLatency: TimeInterval
    public let averageRTF: Float
    public let usageCount: Int
    public let errorRate: Float
}

// Implementation
public class VoicePerformanceMonitorImpl: VoicePerformanceMonitor {
    private var transcriptionMetrics: [TranscriptionMetric] = []
    private var ttsMetrics: [TTSMetric] = []
    private var vadMetrics: [VADMetric] = []

    struct TranscriptionMetric {
        let duration: TimeInterval
        let audioLength: TimeInterval
        let model: String
        let rtf: Float
        let timestamp: Date
    }

    struct TTSMetric {
        let duration: TimeInterval
        let textLength: Int
        let voice: String
        let timestamp: Date
    }

    struct VADMetric {
        let processingTime: TimeInterval
        let audioLength: TimeInterval
        let timestamp: Date
    }

    public func trackTranscription(duration: TimeInterval, audioLength: TimeInterval, model: String) {
        let rtf = Float(audioLength / duration)
        transcriptionMetrics.append(TranscriptionMetric(
            duration: duration,
            audioLength: audioLength,
            model: model,
            rtf: rtf,
            timestamp: Date()
        ))

        // Trim old metrics (keep last 100)
        if transcriptionMetrics.count > 100 {
            transcriptionMetrics.removeFirst()
        }
    }

    public func trackTTS(duration: TimeInterval, textLength: Int, voice: String) {
        ttsMetrics.append(TTSMetric(
            duration: duration,
            textLength: textLength,
            voice: voice,
            timestamp: Date()
        ))

        if ttsMetrics.count > 100 {
            ttsMetrics.removeFirst()
        }
    }

    public func trackVAD(processingTime: TimeInterval, audioLength: TimeInterval) {
        vadMetrics.append(VADMetric(
            processingTime: processingTime,
            audioLength: audioLength,
            timestamp: Date()
        ))

        if vadMetrics.count > 100 {
            vadMetrics.removeFirst()
        }
    }

    public func getMetrics() -> VoicePerformanceMetrics {
        // Calculate averages
        let avgRTF = transcriptionMetrics.isEmpty ? 0 :
            transcriptionMetrics.reduce(0) { $0 + $1.rtf } / Float(transcriptionMetrics.count)

        let avgTTSLatency = ttsMetrics.isEmpty ? 0 :
            ttsMetrics.reduce(0) { $0 + $1.duration } / Double(ttsMetrics.count)

        let avgVADLatency = vadMetrics.isEmpty ? 0 :
            vadMetrics.reduce(0) { $0 + $1.processingTime } / Double(vadMetrics.count)

        // Group by model
        var modelMetrics: [String: ModelMetrics] = [:]
        let groupedByModel = Dictionary(grouping: transcriptionMetrics, by: { $0.model })

        for (model, metrics) in groupedByModel {
            let avgLatency = metrics.reduce(0) { $0 + $1.duration } / Double(metrics.count)
            let avgRTF = metrics.reduce(0) { $0 + $1.rtf } / Float(metrics.count)

            modelMetrics[model] = ModelMetrics(
                modelName: model,
                averageLatency: avgLatency,
                averageRTF: avgRTF,
                usageCount: metrics.count,
                errorRate: 0 // Would need error tracking
            )
        }

        return VoicePerformanceMetrics(
            averageTranscriptionRTF: avgRTF,
            averageTTSLatency: avgTTSLatency,
            averageVADLatency: avgVADLatency,
            totalTranscriptions: transcriptionMetrics.count,
            totalTTSSynthesis: ttsMetrics.count,
            averageWordErrorRate: nil, // Would need ground truth
            modelPerformance: modelMetrics
        )
    }
}
```

### ServiceContainer Updates

```swift
// Add to ServiceContainer.swift
/// Voice adapter registry
internal lazy var voiceAdapterRegistry: VoiceAdapterRegistry = {
    VoiceAdapterRegistryImpl()
}()

/// Voice performance monitor
private(set) lazy var voicePerformanceMonitor: VoicePerformanceMonitor = {
    VoicePerformanceMonitorImpl()
}()

/// Voice activity detector (optional - created when needed)
private var voiceActivityDetector: VoiceActivityDetector?

public func getVoiceActivityDetector() -> VoiceActivityDetector {
    if voiceActivityDetector == nil {
        voiceActivityDetector = SimpleVAD()
    }
    return voiceActivityDetector!
}
```

## Key Benefits of This Approach

### Maximum Reuse
- **90% existing infrastructure reused**: Model loading, downloading, storage, memory management, generation
- **No duplication**: Voice uses exact same patterns as text models
- **Consistent architecture**: Voice feels native to the SDK

### Clean Separation
- **SDK remains framework-agnostic**: No WhisperKit dependency in SDK
- **WhisperKit in separate module**: Can be swapped for other implementations
- **Simple integration**: Just register adapter and use

### Minimal Complexity
- **Only 6 new files in SDK**: 2 protocols, 3 models, 1 API extension
- **Simple flow**: Audio → Text → LLM → Text → Audio
- **Proven patterns**: Follows existing LLMSwift integration exactly

### Future Extensibility
- **Easy to add new voice frameworks**: Just create new adapters
- **Swap implementations**: Can use OpenAI Whisper, Azure Speech, etc.
- **Progressive enhancement**: Start with STT, add TTS later

## Conclusion

### MVP Implementation Complete ✅

The basic voice infrastructure has been successfully implemented with minimal changes to the RunAnywhere SDK. The current implementation provides:

### What We're Building
A complete voice AI system featuring:

#### Core Capabilities
1. **Speech-to-Text (STT)**
   - WhisperKit integration with 99 language support
   - Real-time streaming transcription
   - Word-level timestamps
   - Automatic language detection

2. **Voice Activity Detection (VAD)**
   - Energy-based speech detection
   - Zero-crossing rate analysis
   - Configurable sensitivity levels
   - Real-time streaming VAD

3. **Text-to-Speech (TTS)**
   - System TTS with AVSpeechSynthesizer
   - Streaming audio synthesis
   - Multiple voice options
   - Emotion and prosody control (future)

4. **Voice Session Management**
   - Session state tracking
   - Transcript aggregation
   - Audio buffering
   - Silence timeout handling

5. **Performance Monitoring**
   - Real-time factor (RTF) tracking
   - Latency measurements
   - Model-specific metrics
   - Resource usage monitoring

6. **Future Enhancements**
   - Wake word detection (Picovoice/OpenWakeWord)
   - Voice cloning capabilities
   - Multi-speaker diarization
   - Emotion recognition

### Complete Voice Pipeline
1. **Audio Capture** → 16kHz mono PCM audio from microphone
2. **VAD Processing** → Detect speech segments, filter silence
3. **Speech Recognition** → WhisperKit transcribes to text
4. **LLM Processing** → Existing generation service handles response
5. **Speech Synthesis** → TTS converts response to audio
6. **Audio Playback** → Stream synthesized audio to speaker

### Architecture Summary
- **SDK Core**: Adds only 16 new files (5 protocols, 7 models, 2 infrastructure, 2 API extensions)
- **WhisperKit Module**: Lives separately in sample app (like LLMSwift) - 11 additional files
- **Infrastructure**: Reuses 90% of existing components without modification
- **Integration**: Follows exact same pattern as LLMSwift
- **Advanced Features**: VAD, session management, performance monitoring, future wake word support

### Key Design Decisions
1. **Framework Agnostic**: SDK has no dependency on WhisperKit
2. **Maximum Reuse**: All existing services work unchanged
3. **Simple API**: Just `transcribe()` and `processVoiceQuery()`
4. **Progressive Enhancement**: Start with STT, add TTS later

### Implementation Progress
- **Week 1** ✅: Added voice protocols, models, and infrastructure to SDK (8 files implemented, simplified for MVP)
- **Week 2-3** 🚧: WhisperKit module structure created (3 files, ready for integration)
- **Week 4** ⏭️: TTS implementation (deferred to future)
- **Week 5** 📝: Sample app UI integration (planned next)
- **Week 6** 📝: Testing and optimization (planned)

### Current State
- ✅ **SDK builds successfully** with voice infrastructure
- ✅ **Framework-agnostic design** maintained
- ✅ **Adapter pattern** implemented following existing patterns
- ✅ **Public API** ready for voice transcription
- 🚧 **WhisperKit integration** ready for actual library dependency
- 📝 **Next step**: Add WhisperKit dependency and implement actual transcription

This MVP approach provides a solid foundation while maintaining the SDK's clean architecture and allowing for progressive enhancement with additional voice features.

## Current Implementation Details

### What Has Been Implemented ✅

#### SDK Core (8 files added/modified):
1. **Enum Updates** (2 files modified):
   - `LLMFramework.swift`: Added `whisperKit` and `openAIWhisper` cases
   - `ModelArchitecture.swift`: Added `whisper` and `wav2vec2` cases

2. **Voice Protocols** (2 files created):
   - `VoiceService.swift`: Main protocol for voice transcription services
   - `VoiceFrameworkAdapter.swift`: Protocol for voice framework adapters

3. **Voice Models** (2 files created):
   - `TranscriptionResult.swift`: Result structure with text, language, confidence, duration
   - `TranscriptionOptions.swift`: Options with language and task enums

4. **Infrastructure** (1 file created):
   - `VoiceAdapterRegistry.swift`: Simplified registry for voice adapters (MVP version)

5. **Public API** (1 file created):
   - `RunAnywhereSDK+Voice.swift`: Public extensions with `transcribe()` and `processVoiceQuery()` methods

6. **SDK Main Class** (1 file modified):
   - `RunAnywhereSDK.swift`: Added voice adapter storage

#### Sample App (3 files added/modified):
1. **WhisperKit Module** (2 files created):
   - `WhisperKitAdapter.swift`: Adapter implementation conforming to `VoiceFrameworkAdapter`
   - `WhisperKitService.swift`: Service implementation with simulated transcription (ready for WhisperKit)

2. **App Initialization** (1 file modified):
   - `RunAnywhereAIApp.swift`: Added WhisperKit adapter registration

### What Was Simplified for MVP 🎯

- **No VAD**: Voice Activity Detection deferred to future
- **No TTS**: Text-to-Speech deferred to future
- **No Streaming**: Real-time transcription deferred to future
- **No Session Management**: Voice session handling deferred to future
- **No Performance Monitoring**: Voice-specific metrics deferred to future
- **Simulated Transcription**: WhisperKitService returns placeholder results (ready for real implementation)

### Next Steps to Complete Voice Pipeline 📝

#### 1. **Audio Input Implementation** (First Priority)
```swift
// Create AudioCapture.swift in sample app
- Implement AVAudioEngine setup
- Add 16kHz mono recording
- Handle microphone permissions
- Add to Info.plist: NSMicrophoneUsageDescription
```

#### 2. **WhisperKit Integration** (Second Priority)
```swift
// Add to Package.swift
.package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.4")

// Update WhisperKitService.swift
- Import WhisperKit
- Replace simulated transcription
- Add model download logic
```

#### 3. **TTS Implementation** (Third Priority)
```swift
// Create SystemTTSService.swift
- Implement TextToSpeechService protocol
- Add AVSpeechSynthesizer
- Configure voice settings
```

#### 4. **Complete Pipeline Integration** (Final Step)
```swift
// Wire everything together
- Create VoiceConversationManager
- Add UI components (mic button, display)
- Test full flow: Audio → STT → LLM → TTS → Audio
```

#### 5. **Testing Checklist**
- [ ] Microphone permission granted
- [ ] Audio recording working (16kHz mono)
- [ ] WhisperKit transcription accurate
- [ ] LLM response generation working
- [ ] TTS speaking clearly
- [ ] End-to-end latency < 3 seconds
- [ ] Error handling at each stage

## Complete Component Summary

### SDK Core Changes (Originally Planned: 16 Files, Implemented: 8 Files)

#### Protocols (5 files in `Core/Protocols/Voice/`)
1. `VoiceService.swift` - Main voice service protocol with transcribe, stream, language detection
2. `VoiceFrameworkAdapter.swift` - Adapter protocol for voice frameworks
3. `VoiceActivityDetector.swift` - VAD protocol for speech detection
4. `TextToSpeechService.swift` - TTS protocol for speech synthesis
5. `WakeWordDetector.swift` - Future wake word detection protocol

#### Models (7 files in `Public/Models/Voice/`)
1. `TranscriptionResult.swift` - Complete transcription results with segments
2. `TranscriptionOptions.swift` - Configuration for transcription
3. `AudioChunk.swift` - Audio data wrapper for streaming
4. `TranscriptionSegment.swift` - Individual transcription segments
5. `VoiceSessionState.swift` - State enum (idle, listening, processing, speaking)
6. `VoiceSession.swift` - Session management with transcript aggregation
7. `VADResult.swift` - Voice activity detection results

#### Infrastructure (2 files)
1. `Core/Foundation/DependencyInjection/VoiceAdapterRegistry.swift` - Registry for adapters
2. `Core/Monitoring/VoicePerformanceMonitor.swift` - Performance tracking

#### API Extensions (2 files in `Public/Extensions/`)
1. `RunAnywhereSDK+Voice.swift` - Main voice APIs (transcribe, processVoiceQuery)
2. `RunAnywhereSDK+VoiceSession.swift` - Session management APIs

### Sample App Implementation (11 Files)

#### WhisperKit Module (4 files)
1. `WhisperKitAdapter.swift` - Framework adapter implementation
2. `WhisperKitService.swift` - Voice service implementation
3. `WhisperKitConfiguration.swift` - WhisperKit-specific settings
4. `WhisperModelManager.swift` - Model download and management

#### Audio Processing (4 files)
1. `AudioCapture.swift` - Microphone capture at 16kHz mono
2. `AudioProcessor.swift` - Resampling, normalization, format conversion
3. `SimpleVAD.swift` - Energy-based voice detection
4. `StreamingTranscriber.swift` - Real-time transcription

#### TTS Module (3 files)
1. `SystemTTSService.swift` - AVSpeechSynthesizer implementation
2. `TTSConfiguration.swift` - Voice and speech settings
3. `VoiceManager.swift` - Voice selection and management

### Enum Updates (2 existing files)
1. `LLMFramework.swift` - Add `whisperKit`, `openAIWhisper`
2. `ModelArchitecture.swift` - Add `whisper`, `wav2vec2`

### Total Implementation Scope
- **SDK Core**: 16 new files
- **Sample App**: 11 new files
- **Enum Updates**: 2 existing files modified
- **Total**: 27 new files, 2 modified files

---

*Document Version: 2.1 (Implementation Updated)*
*Last Updated: January 2025*
*Status: MVP Foundation Complete - Ready for WhisperKit Integration*
*Implementation Date: January 14, 2025*
