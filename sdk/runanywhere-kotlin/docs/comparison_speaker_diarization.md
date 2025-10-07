# Speaker Diarization Component Architecture Comparison: iOS vs Kotlin SDKs

## Executive Summary

The Speaker Diarization Component shows **significant architectural and implementation differences** between iOS and Kotlin SDKs:

- **iOS SDK**: ✅ **Complete Implementation** - Full production-ready speaker diarization with multiple implementations
- **Kotlin SDK**: ❌ **Missing Implementation** - Only placeholder interfaces and TODO items

## Architecture Overview

### iOS SDK Architecture

#### Core Components Structure
```
ios/
├── Components/SpeakerDiarization/
│   └── SpeakerDiarizationComponent.swift (584 lines)
├── Capabilities/Voice/Services/
│   └── DefaultSpeakerDiarization.swift (188 lines)
├── Capabilities/Voice/Handlers/
│   └── SpeakerDiarizationHandler.swift (55 lines)
└── Modules/FluidAudioDiarization/
    ├── FluidAudioDiarization.swift (350 lines)
    └── FluidAudioDiarizationProvider.swift (129 lines)
```

#### Kotlin SDK Architecture
```
kotlin/
├── src/commonMain/.../components/
│   └── [NO SPEAKER DIARIZATION COMPONENTS]
├── src/commonMain/.../core/ModuleRegistry.kt
│   └── SpeakerDiarizationServiceProvider (interface only)
└── docs/
    ├── TODO-TRACKER.md (lists missing implementation)
    └── refactor*.md (planned implementation)
```

## Detailed Component Comparison

### 1. Core Protocol/Interface Design

#### iOS Implementation
```swift
// Comprehensive Protocol
public protocol SpeakerDiarizationService: AnyObject {
    func initialize() async throws
    func processAudio(_ samples: [Float]) -> SpeakerInfo
    func getAllSpeakers() -> [SpeakerInfo]
    func reset()
    var isReady: Bool { get }
    func cleanup() async
}

// Rich Data Models
public struct SpeakerInfo: Sendable {
    public let id: String
    public var name: String?
    public let confidence: Float?
    public let embedding: [Float]?
}

public struct SpeakerDiarizationOutput: ComponentOutput {
    public let segments: [SpeakerSegment]
    public let speakers: [SpeakerProfile]
    public let labeledTranscription: LabeledTranscription?
    public let metadata: DiarizationMetadata
}
```

#### Kotlin Implementation
```kotlin
// Basic placeholder interface (in ModuleRegistry.kt)
interface SpeakerDiarizationServiceProvider {
    suspend fun createSpeakerDiarizationService(configuration: Any): Any
    // TODO: Add SpeakerDiarizationConfiguration
}

// No speaker diarization data models exist
// STTOptions has enableDiarization: Boolean = false (unused)
```

**Gap Analysis**: iOS has comprehensive protocol design with rich data models, while Kotlin only has basic placeholder interfaces.

### 2. Speaker Identification Algorithms

#### iOS Implementations

**DefaultSpeakerDiarization (Simple)**:
```swift
// Energy-based diarization with embedding comparison
private func createSimpleEmbedding(from audioBuffer: [Float]) -> [Float] {
    var embedding = Array(repeating: Float(0), count: 128)
    let chunkSize = audioBuffer.count / 128

    for i in 0..<min(128, audioBuffer.count / max(1, chunkSize)) {
        let chunk = Array(audioBuffer[start..<end])
        var mean: Float = 0
        var variance: Float = 0
        vDSP_meanv(chunk, 1, &mean, vDSP_Length(chunk.count))
        vDSP_measqv(chunk, 1, &variance, vDSP_Length(chunk.count))
        embedding[i] = mean + variance
    }
    return embedding
}

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    // Uses Accelerate framework for optimized vector operations
    vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
    // ... normalized cosine similarity calculation
}
```

**FluidAudioDiarization (Production)**:
```swift
// Uses external FluidAudio framework with ML models
let result = try diarizerManager.performCompleteDiarization(
    audioBuffer,
    sampleRate: sampleRate
)

// Advanced features:
// - 17.7% DER (Diarization Error Rate)
// - Neural network-based embeddings
// - Real-time and batch processing
// - Speaker clustering and assignment
```

#### Kotlin Implementation
```kotlin
// No speaker identification algorithms implemented
// Only placeholder in STTOptions.enableDiarization = false
```

### 3. Audio Segmentation Techniques

#### iOS Implementation

**Temporal Segmentation**:
```swift
// Advanced segmentation with configurable parameters
public struct SpeakerDiarizationConfiguration {
    public let maxSpeakers: Int
    public let minSpeechDuration: TimeInterval
    public let speakerChangeThreshold: Float
    public let windowSize: TimeInterval = 2.0
    public let stepSize: TimeInterval = 0.5
}

// Dynamic segmentation in processing
while currentTime < totalDuration {
    let endTime = min(currentTime + segmentDuration, totalDuration)
    segments.append(SpeakerSegment(
        speakerId: currentSpeaker,
        startTime: currentTime,
        endTime: endTime,
        confidence: speakerInfo.confidence ?? 0.8
    ))
}
```

**FluidAudio Advanced Segmentation**:
```swift
// Production-grade segmentation with ML
config.minSpeechDuration = 0.5  // Reduced for quicker detection
config.minSilenceGap = 0.3      // Better responsiveness
config.clusteringThreshold = threshold // Adaptive thresholding
```

#### Kotlin Implementation
```kotlin
// No audio segmentation for speaker diarization
// STT component has basic audio segmentation but no speaker attribution
```

### 4. Speaker Clustering and Classification

#### iOS Implementation

**Hierarchical Clustering**:
```swift
// DefaultSpeakerDiarization uses threshold-based clustering
private func findMatchingSpeaker(embedding: [Float]) -> SpeakerInfo? {
    var bestMatch: (speaker: SpeakerInfo, similarity: Float)?

    for speaker in speakers.values {
        let similarity = cosineSimilarity(embedding, speakerEmbedding)
        if similarity > speakerChangeThreshold {
            if bestMatch == nil || similarity > bestMatch!.similarity {
                bestMatch = (speaker, similarity)
            }
        }
    }
    return bestMatch?.speaker
}
```

**FluidAudio ML Clustering**:
```swift
// Advanced ML-based clustering with speaker database
let fluidSpeaker = diarizerManager.speakerManager.assignSpeaker(
    embedding,
    speechDuration: speechDuration,
    confidence: firstSegment.qualityScore
)

// Features:
// - Persistent speaker database across sessions
// - Quality score-based confidence
// - Adaptive threshold adjustment
```

#### Kotlin Implementation
```kotlin
// No speaker clustering or classification implemented
```

### 5. STT Integration

#### iOS Implementation

**Comprehensive STT Integration**:
```swift
// Input can include transcription for labeling
public struct SpeakerDiarizationInput: ComponentInput {
    public let transcription: STTOutput?
    // Creates labeled transcription with speaker attribution
}

// Output provides labeled transcription
public struct LabeledTranscription: Sendable {
    public let segments: [LabeledSegment]

    public struct LabeledSegment: Sendable {
        public let speakerId: String
        public let text: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
    }
}

// Pipeline integration
private func createLabeledTranscription(
    wordTimestamps: [WordTimestamp],
    segments: [SpeakerSegment]
) -> LabeledTranscription {
    // Maps word timestamps to speaker segments
    // Creates speaker-attributed transcript
}
```

**Voice Pipeline Integration**:
```swift
// SpeakerDiarizationHandler integrates with voice pipeline
public func handleSpeakerChange(
    previous: SpeakerInfo?,
    current: SpeakerInfo,
    continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
) {
    continuation.yield(.sttSpeakerChanged(from: previous, to: current))
}

public func emitTranscriptWithSpeaker(
    transcript: String,
    speaker: SpeakerInfo,
    continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
) {
    continuation.yield(.sttFinalTranscriptWithSpeaker(transcript, speaker))
}
```

#### Kotlin Implementation
```kotlin
// Limited STT integration
data class STTOptions(
    val enableDiarization: Boolean = false,
    val maxSpeakers: Int? = null,
    // ... but no actual diarization implementation
)

// No speaker attribution in STTOutput
data class STTOutput(
    val text: String,
    val confidence: Float,
    // No speaker information
)
```

### 6. Real-time vs Batch Processing

#### iOS Implementation

**Real-time Processing**:
```swift
// DefaultSpeakerDiarization: Real-time optimized
public func processAudio(_ samples: [Float]) -> SpeakerInfo {
    // Immediate processing for streaming audio
    let embedding = createSimpleEmbedding(from: samples)
    return findMatchingSpeaker(embedding: embedding) ?? createNewSpeaker(embedding: embedding)
}
```

**Batch Processing**:
```swift
// FluidAudioDiarization: Batch processing for accuracy
public func performDetailedDiarization(audioBuffer: [Float]) async throws -> SpeakerDiarizationResult? {
    let result = try diarizerManager.performCompleteDiarization(
        audioBuffer,
        sampleRate: 16000
    )
    // Returns complete diarization with all speakers and segments
}
```

**Adaptive Processing**:
```swift
// Audio buffering for optimal chunk size
private var audioAccumulator: [Float] = []
private let minimumChunkDuration: Float = 3.0  // seconds

// Balances real-time responsiveness with accuracy
```

#### Kotlin Implementation
```kotlin
// No real-time or batch processing for speaker diarization
// Only basic audio processing in STT without speaker attribution
```

### 7. Model Requirements and Performance

#### iOS Implementation

**Model Support**:
```swift
// Supports multiple model types
public struct SpeakerDiarizationConfiguration {
    public let modelId: String?  // Optional ML model
    // Graceful fallback to energy-based if no model
}

// FluidAudio: Production ML models
let models = try await DiarizerModels.downloadIfNeeded()
diarizerManager.initialize(models: models)
```

**Performance Metrics**:
```swift
// FluidAudio achieves 17.7% DER (Diarization Error Rate)
// Configurable thresholds for performance/accuracy trade-offs
config.clusteringThreshold = threshold  // 0.5-0.9 range

// Performance monitoring
public struct DiarizationMetadata: Sendable {
    public let processingTime: TimeInterval
    public let audioLength: TimeInterval
    public let speakerCount: Int
    public let method: String  // "energy", "ml", "hybrid"
}
```

#### Kotlin Implementation
```kotlin
// No model support for speaker diarization
// No performance metrics for diarization
```

### 8. Platform-specific Optimizations

#### iOS Implementation

**iOS Optimizations**:
```swift
// Uses Accelerate framework for vector operations
import Accelerate

// SIMD optimized similarity calculations
vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))

// Concurrent processing with GCD
private let diarizationQueue: DispatchQueue = DispatchQueue(
    label: "com.runanywhere.fluidaudio.diarization",
    attributes: .concurrent
)

// Memory-efficient audio processing
data.withUnsafeBytes { bytes in
    Array(UnsafeBufferPointer<Float>(
        start: bytes.bindMemory(to: Float.self).baseAddress,
        count: floatCount
    ))
}
```

**Thread Safety**:
```swift
// DefaultSpeakerDiarization uses NSLock
private let lock = NSLock()

// FluidAudioDiarization uses concurrent queue with barriers
diarizationQueue.async(flags: .barrier) {
    // Write operations
}
```

#### Kotlin Implementation
```kotlin
// expect/actual pattern not used for speaker diarization (doesn't exist)
// No platform-specific optimizations for diarization
// Potential platform implementations would be:
// - Android: Could use native C++ libraries
// - JVM: Could use Java-based ML frameworks
// - Native: Could use platform-specific audio libraries
```

### 9. Output Format and Speaker Labeling

#### iOS Implementation

**Rich Output Format**:
```swift
public struct SpeakerDiarizationOutput: ComponentOutput {
    public let segments: [SpeakerSegment]           // Temporal segments
    public let speakers: [SpeakerProfile]           // Speaker profiles
    public let labeledTranscription: LabeledTranscription?  // Text with speakers
    public let metadata: DiarizationMetadata        // Processing info
}

public struct SpeakerProfile: Sendable {
    public let id: String
    public let embedding: [Float]?              // 128-dimensional vector
    public let totalSpeakingTime: TimeInterval  // Aggregate stats
    public let segmentCount: Int               // Number of segments
    public let name: String?                   // Custom label
}

// Formatted output for display
public var formattedTranscript: String {
    segments.map { "[\($0.speakerId)]: \($0.text)" }.joined(separator: "\n")
}
```

**Speaker Management**:
```swift
// Persistent speaker naming
public func updateSpeakerName(speakerId: String, name: String) {
    // Updates both in-memory and persistent storage
    if let fluidSpeaker = diarizerManager.speakerManager.getSpeaker(for: speakerId) {
        fluidSpeaker.name = name
        diarizerManager.speakerManager.upsertSpeaker(fluidSpeaker)
    }
}

// Speaker retrieval and management
public func getAllSpeakers() -> [SpeakerInfo]
public func getSpeakerProfile(id: String) -> SpeakerProfile?
public func resetProfiles()
```

#### Kotlin Implementation
```kotlin
// No output format for speaker diarization
// No speaker labeling capabilities
// STTOutput only provides text without speaker attribution
```

## Implementation Status Summary

| Feature | iOS SDK | Kotlin SDK | Gap Severity |
|---------|---------|------------|--------------|
| **Core Protocol** | ✅ Complete | ❌ Missing | **CRITICAL** |
| **Speaker Identification** | ✅ 2 implementations | ❌ Missing | **CRITICAL** |
| **Audio Segmentation** | ✅ Advanced | ❌ Missing | **HIGH** |
| **Speaker Clustering** | ✅ ML + Rule-based | ❌ Missing | **CRITICAL** |
| **STT Integration** | ✅ Full integration | ⚠️ Stub only | **HIGH** |
| **Real-time Processing** | ✅ Optimized | ❌ Missing | **HIGH** |
| **Batch Processing** | ✅ Production-ready | ❌ Missing | **MEDIUM** |
| **ML Models** | ✅ FluidAudio + Basic | ❌ Missing | **HIGH** |
| **Platform Optimization** | ✅ Accelerate framework | ❌ Missing | **MEDIUM** |
| **Output Formatting** | ✅ Rich formats | ❌ Missing | **HIGH** |
| **Speaker Management** | ✅ Persistent profiles | ❌ Missing | **HIGH** |

## Recommendations for Kotlin SDK Implementation

### 1. High Priority - Core Infrastructure
```kotlin
// 1. Create speaker diarization data models
data class SpeakerInfo(
    val id: String,
    val name: String? = null,
    val confidence: Float? = null,
    val embedding: FloatArray? = null
)

data class SpeakerDiarizationInput(
    val audioData: ByteArray,
    val format: AudioFormat = AudioFormat.WAV,
    val transcription: STTOutput? = null,
    val options: SpeakerDiarizationOptions? = null
) : ComponentInput

data class SpeakerDiarizationOutput(
    val segments: List<SpeakerSegment>,
    val speakers: List<SpeakerProfile>,
    val labeledTranscription: LabeledTranscription? = null,
    val metadata: DiarizationMetadata,
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput
```

### 2. Medium Priority - Basic Implementation
```kotlin
// 2. Create basic speaker diarization component
interface SpeakerDiarizationService {
    suspend fun initialize(modelPath: String?)
    suspend fun processAudio(samples: FloatArray): SpeakerInfo
    fun getAllSpeakers(): List<SpeakerInfo>
    fun reset()
    val isReady: Boolean
    suspend fun cleanup()
}

class DefaultSpeakerDiarizationService : SpeakerDiarizationService {
    // Port iOS DefaultSpeakerDiarization logic
    // Implement cosine similarity with platform-specific optimizations
}
```

### 3. Platform-specific Optimizations
```kotlin
// 3. Use expect/actual for platform optimizations
expect class PlatformAudioProcessor {
    fun createEmbedding(audioSamples: FloatArray): FloatArray
    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float
}

// Android actual - use native libraries
// JVM actual - use Java ML libraries
// Native actual - use platform audio libs
```

### 4. STT Integration Enhancement
```kotlin
// 4. Enhance STT integration
data class STTOutput(
    val text: String,
    val confidence: Float,
    val wordTimestamps: List<WordTimestamp>? = null,
    val speakerSegments: List<SpeakerSegment>? = null,  // Add speaker info
    val detectedLanguage: String? = null,
    val alternatives: List<TranscriptionAlternative>? = null,
    val metadata: TranscriptionMetadata,
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput
```

## Conclusion

The Speaker Diarization Component represents one of the **most significant architectural gaps** between the iOS and Kotlin SDKs. The iOS implementation provides:

- **Production-ready speaker identification** with 17.7% DER performance
- **Multiple algorithm choices** (energy-based and ML-based)
- **Comprehensive STT integration** with speaker-attributed transcripts
- **Real-time and batch processing** capabilities
- **Rich output formats** with speaker profiles and metadata

The Kotlin SDK currently has **no speaker diarization implementation**, only placeholder interfaces and TODO items. This represents a **critical feature gap** that requires substantial development effort to achieve parity.

**Estimated Implementation Effort**: 4-6 weeks for basic parity, 8-10 weeks for full feature parity including ML models and optimization.

**Priority**: **CRITICAL** - Speaker diarization is essential for multi-speaker conversation analysis and transcript attribution.
