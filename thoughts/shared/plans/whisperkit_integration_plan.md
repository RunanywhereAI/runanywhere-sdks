# WhisperKit Integration Implementation Plan
## Detailed Guide for RunAnywhere SDK Voice Capability

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [WhisperKit Overview](#whisperkit-overview)
3. [Integration Architecture](#integration-architecture)
4. [Implementation Steps](#implementation-steps)
5. [WhisperKitFrameworkAdapter](#whisperkitframeworkadapter)
6. [Audio Processing Pipeline](#audio-processing-pipeline)
7. [Streaming Implementation](#streaming-implementation)
8. [Model Management](#model-management)
9. [Performance Optimization](#performance-optimization)
10. [Sample App Integration](#sample-app-integration)
11. [Testing Strategy](#testing-strategy)
12. [Migration & Deployment](#migration--deployment)

---

## Executive Summary

This document provides a comprehensive implementation plan for integrating WhisperKit into the RunAnywhere SDK as the primary speech-to-text engine. WhisperKit offers production-ready, on-device speech recognition with excellent performance characteristics and seamless Apple platform integration.

### Key Benefits of WhisperKit Integration

- **Proven Stability**: Mature, well-tested codebase with active development
- **Platform Optimization**: Native CoreML integration with Neural Engine support
- **Privacy-First**: Complete on-device processing with no cloud dependencies
- **Comprehensive Features**: 99 language support, streaming, VAD, and word timestamps
- **Easy Integration**: Clean API design with Swift Package Manager support

---

## WhisperKit Overview

### Core Capabilities

```swift
// WhisperKit Key Features
- Model Variants: tiny, base, small, medium, large, distilled
- Platforms: iOS 16+, macOS 13+, watchOS 10+, visionOS 1+
- Languages: 99 languages with automatic detection
- Streaming: Real-time transcription with < 200ms latency
- VAD: Built-in voice activity detection
- Timestamps: Word-level timing information
- Hardware: Automatic Neural Engine optimization
```

### Architecture Components

```
WhisperKit/
├── Core/
│   ├── WhisperKit.swift         # Main orchestrator
│   ├── AudioEncoder.swift       # Audio encoding pipeline
│   ├── TextDecoder.swift        # Text generation
│   └── FeatureExtractor.swift   # Mel spectrogram extraction
├── Audio/
│   ├── AudioProcessor.swift     # Audio preprocessing
│   ├── AudioStreamTranscriber.swift # Streaming support
│   ├── AudioChunker.swift       # VAD-based chunking
│   └── VoiceActivityDetector.swift # VAD implementation
└── Utilities/
    ├── ModelUtilities.swift     # Model management
    └── Logging.swift            # Debug logging
```

---

## Integration Architecture

### High-Level Integration Design

```
┌─────────────────────────────────────────────────────┐
│              RunAnywhere SDK                        │
│                                                     │
│  ┌──────────────────────────────────────────────┐ │
│  │           Voice Capability Module             │ │
│  │                                              │ │
│  │  ┌────────────────────────────────────────┐ │ │
│  │  │    WhisperKitFrameworkAdapter          │ │ │
│  │  │                                        │ │ │
│  │  │  - Model Management                    │ │ │
│  │  │  - Configuration Mapping               │ │ │
│  │  │  - Error Handling                      │ │ │
│  │  │  - Type Conversion                     │ │ │
│  │  └────────────────────────────────────────┘ │ │
│  │                     │                        │ │
│  │                     ▼                        │ │
│  │  ┌────────────────────────────────────────┐ │ │
│  │  │         WhisperKit Library              │ │ │
│  │  │                                        │ │ │
│  │  │  - CoreML Models                       │ │ │
│  │  │  - Audio Processing                    │ │ │
│  │  │  - Transcription Engine                │ │ │
│  │  │  - Streaming Support                   │ │ │
│  │  └────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### Dependency Structure

```swift
// Package.swift additions
dependencies: [
    .package(
        url: "https://github.com/argmaxinc/WhisperKit",
        from: "0.9.4"
    )
],
targets: [
    .target(
        name: "RunAnywhere",
        dependencies: [
            .product(name: "WhisperKit", package: "WhisperKit")
        ]
    )
]
```

---

## Implementation Steps

### Step 1: Project Setup

```bash
# 1. Add WhisperKit dependency to Package.swift
# 2. Create Voice capability structure
mkdir -p Sources/RunAnywhere/Capabilities/Voice/{Models,Services,Protocols,Extensions,Frameworks}

# 3. Create WhisperKit adapter structure
mkdir -p Sources/RunAnywhere/Capabilities/Voice/Frameworks/WhisperKit
```

### Step 2: Create Core Voice Models

```swift
// Sources/RunAnywhere/Capabilities/Voice/Models/TranscriptionResult.swift
public struct TranscriptionResult {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let language: String?
    public let confidence: Float
    public let duration: TimeInterval
    public let wordTimestamps: [WordTimestamp]?
}

public struct TranscriptionSegment {
    public let id: Int
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let tokens: [Int]
    public let confidence: Float
}

public struct WordTimestamp {
    public let word: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let probability: Float
}

// Sources/RunAnywhere/Capabilities/Voice/Models/TranscriptionOptions.swift
public struct TranscriptionOptions {
    public var language: Language = .auto
    public var task: TranscriptionTask = .transcribe
    public var enableWordTimestamps: Bool = true
    public var enableVAD: Bool = true
    public var vadSensitivity: VADSensitivity = .medium
    public var chunkingStrategy: ChunkingStrategy = .vad
    public var maxSegmentLength: TimeInterval = 30.0

    public enum TranscriptionTask {
        case transcribe
        case translate
    }

    public enum Language: String {
        case auto = "auto"
        case english = "en"
        case spanish = "es"
        case french = "fr"
        case german = "de"
        case chinese = "zh"
        case japanese = "ja"
        // ... other languages
    }

    public enum VADSensitivity {
        case low, medium, high

        var energyThreshold: Float {
            switch self {
            case .low: return 0.01
            case .medium: return 0.05
            case .high: return 0.1
            }
        }
    }

    public enum ChunkingStrategy {
        case none
        case vad
        case fixed(seconds: TimeInterval)
    }
}
```

### Step 3: Create Voice Protocols

```swift
// Sources/RunAnywhere/Capabilities/Voice/Protocols/SpeechRecognizer.swift
public protocol SpeechRecognizer {
    func initialize() async throws
    func transcribe(audio: Data, options: TranscriptionOptions) async throws -> TranscriptionResult
    func transcribeStream(audioStream: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptionSegment, Error>
    func detectLanguage(audio: Data) async throws -> String
    func loadModel(_ model: String) async throws
    func unloadModel() async
    func isModelLoaded() -> Bool
}

// Sources/RunAnywhere/Capabilities/Voice/Protocols/AudioProcessorProtocol.swift
public protocol AudioProcessorProtocol {
    func processAudio(_ data: Data) async throws -> ProcessedAudio
    func resample(audio: Data, from: Int, to: Int) async throws -> Data
    func convertToMono(_ audio: Data) async throws -> Data
    func normalizeAudio(_ audio: Data) async throws -> Data
}
```

---

## WhisperKitFrameworkAdapter

### Complete Implementation

```swift
// Sources/RunAnywhere/Capabilities/Voice/Frameworks/WhisperKit/WhisperKitFrameworkAdapter.swift
import Foundation
import WhisperKit
import RunAnywhere

public actor WhisperKitFrameworkAdapter: SpeechRecognizer {

    // MARK: - Properties

    private var whisperKit: WhisperKit?
    private let configuration: WhisperKitConfiguration
    private let logger: SDKLogger
    private let performanceMonitor: PerformanceMonitor
    private var currentModel: String?

    // MARK: - Initialization

    public init(
        configuration: WhisperKitConfiguration,
        logger: SDKLogger,
        performanceMonitor: PerformanceMonitor
    ) {
        self.configuration = configuration
        self.logger = logger
        self.performanceMonitor = performanceMonitor
    }

    public func initialize() async throws {
        logger.info("Initializing WhisperKit with model: \(configuration.model)")

        // Create WhisperKit configuration
        let computeOptions = ModelComputeOptions(
            computeUnits: mapComputeUnits(configuration.computeUnits),
            audioEncoderComputeUnits: mapComputeUnits(configuration.audioEncoderComputeUnits),
            textDecoderComputeUnits: mapComputeUnits(configuration.textDecoderComputeUnits)
        )

        let audioProcessor = AudioProcessor(
            sampleRate: configuration.sampleRate,
            doChunking: configuration.enableChunking,
            chunkingStrategy: mapChunkingStrategy(configuration.chunkingStrategy)
        )

        // Initialize WhisperKit
        do {
            self.whisperKit = try await WhisperKit(
                model: configuration.model,
                computeOptions: computeOptions,
                audioProcessor: audioProcessor,
                logLevel: mapLogLevel(configuration.logLevel),
                prewarm: configuration.prewarm
            )

            currentModel = configuration.model
            logger.info("WhisperKit initialized successfully with model: \(configuration.model)")
        } catch {
            logger.error("Failed to initialize WhisperKit: \(error)")
            throw VoiceError.initializationFailed(error)
        }
    }

    // MARK: - Transcription

    public func transcribe(
        audio: Data,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        guard let whisperKit = whisperKit else {
            throw VoiceError.notInitialized
        }

        let startTime = Date()
        performanceMonitor.startOperation("whisperkit_transcribe")

        do {
            // Convert audio data to float array
            let audioArray = try convertAudioDataToFloatArray(audio)

            // Create decoding options
            let decodingOptions = DecodingOptions(
                verbose: configuration.verbose,
                task: mapTask(options.task),
                language: options.language.rawValue,
                temperature: configuration.temperature,
                temperatureIncrementOnFallback: configuration.temperatureIncrementOnFallback,
                temperatureFallbackCount: configuration.temperatureFallbackCount,
                sampleLength: configuration.sampleLength,
                topK: configuration.topK,
                usePrefillPrompt: configuration.usePrefillPrompt,
                usePrefillCache: configuration.usePrefillCache,
                skipSpecialTokens: configuration.skipSpecialTokens,
                withoutTimestamps: !options.enableWordTimestamps,
                clipTimestamps: configuration.clipTimestamps,
                chunkingStrategy: mapChunkingStrategy(options.chunkingStrategy)
            )

            // Perform transcription
            let transcriptionResult = try await whisperKit.transcribe(
                audioArray: audioArray,
                decodeOptions: decodingOptions
            )

            // Track performance
            let duration = Date().timeIntervalSince(startTime)
            performanceMonitor.endOperation(
                "whisperkit_transcribe",
                metrics: [
                    "duration": duration,
                    "audio_length": Float(audioArray.count) / Float(configuration.sampleRate),
                    "realtime_factor": Float(audioArray.count) / Float(configuration.sampleRate) / Float(duration)
                ]
            )

            // Map to RunAnywhere types
            return mapTranscriptionResult(transcriptionResult, duration: duration)

        } catch {
            performanceMonitor.cancelOperation("whisperkit_transcribe")
            logger.error("Transcription failed: \(error)")
            throw VoiceError.transcriptionFailed(error)
        }
    }

    // MARK: - Streaming Transcription

    public func transcribeStream(
        audioStream: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptionSegment, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let whisperKit = whisperKit else {
                    continuation.finish(throwing: VoiceError.notInitialized)
                    return
                }

                // Create streaming transcriber
                let streamTranscriber = AudioStreamTranscriber(
                    audioProcessor: whisperKit.audioProcessor,
                    transcriber: whisperKit,
                    decodingOptions: DecodingOptions(
                        verbose: configuration.verbose,
                        task: "transcribe",
                        language: "auto",
                        skipSpecialTokens: true,
                        withoutTimestamps: false
                    )
                )

                // Process audio chunks
                do {
                    for await chunk in audioStream {
                        // Add audio to buffer
                        streamTranscriber.appendAudio(chunk.data.toFloatArray())

                        // Process if enough audio accumulated
                        if streamTranscriber.shouldProcess() {
                            let result = try await streamTranscriber.transcribe()

                            if let segment = mapToSegment(result) {
                                continuation.yield(segment)
                            }
                        }
                    }

                    // Process remaining audio
                    if streamTranscriber.hasRemainingAudio() {
                        let result = try await streamTranscriber.finalize()
                        if let segment = mapToSegment(result) {
                            continuation.yield(segment)
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Language Detection

    public func detectLanguage(audio: Data) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw VoiceError.notInitialized
        }

        let audioArray = try convertAudioDataToFloatArray(audio)

        // Use WhisperKit's language detection
        let detectedLanguage = try await whisperKit.detectLanguage(audioArray: audioArray)

        return detectedLanguage.bestLanguage?.key ?? "unknown"
    }

    // MARK: - Model Management

    public func loadModel(_ model: String) async throws {
        if currentModel == model && whisperKit != nil {
            logger.info("Model \(model) already loaded")
            return
        }

        logger.info("Loading WhisperKit model: \(model)")

        // Update configuration with new model
        var newConfig = configuration
        newConfig.model = model

        // Reinitialize with new model
        self.configuration = newConfig
        try await initialize()
    }

    public func unloadModel() async {
        logger.info("Unloading WhisperKit model")
        whisperKit = nil
        currentModel = nil
    }

    public func isModelLoaded() -> Bool {
        return whisperKit != nil
    }

    // MARK: - Private Helpers

    private func mapComputeUnits(_ units: ComputeUnits) -> MLComputeUnits {
        switch units {
        case .cpuOnly:
            return .cpuOnly
        case .cpuAndGPU:
            return .cpuAndGPU
        case .cpuAndNeuralEngine:
            return .cpuAndNeuralEngine
        case .all:
            return .all
        }
    }

    private func mapChunkingStrategy(_ strategy: TranscriptionOptions.ChunkingStrategy) -> ChunkingStrategy {
        switch strategy {
        case .none:
            return .none
        case .vad:
            return .vad
        case .fixed(let seconds):
            return .fixed(seconds: Int(seconds))
        }
    }

    private func mapTask(_ task: TranscriptionOptions.TranscriptionTask) -> String {
        switch task {
        case .transcribe:
            return "transcribe"
        case .translate:
            return "translate"
        }
    }

    private func mapLogLevel(_ level: LogLevel) -> Logging.LogLevel {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        case .none:
            return .none
        }
    }

    private func convertAudioDataToFloatArray(_ data: Data) throws -> [Float] {
        // Convert audio data to float array
        // Assumes PCM 16-bit audio at 16kHz
        let int16Array = data.withUnsafeBytes { bytes in
            bytes.bindMemory(to: Int16.self).map { Float($0) / Float(Int16.max) }
        }
        return int16Array
    }

    private func mapTranscriptionResult(
        _ result: TranscriptionResult,
        duration: TimeInterval
    ) -> RunAnywhere.TranscriptionResult {
        RunAnywhere.TranscriptionResult(
            text: result.text,
            segments: result.segments.map { segment in
                TranscriptionSegment(
                    id: segment.id,
                    text: segment.text,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    tokens: segment.tokens,
                    confidence: segment.avgLogprob ?? 0
                )
            },
            language: result.language,
            confidence: result.avgLogprob ?? 0,
            duration: duration,
            wordTimestamps: result.wordTimestamps?.map { timestamp in
                WordTimestamp(
                    word: timestamp.word,
                    startTime: TimeInterval(timestamp.start),
                    endTime: TimeInterval(timestamp.end),
                    probability: timestamp.probability
                )
            }
        )
    }

    private func mapToSegment(_ result: StreamTranscriptionResult) -> TranscriptionSegment? {
        guard !result.text.isEmpty else { return nil }

        return TranscriptionSegment(
            id: result.segmentId,
            text: result.text,
            startTime: result.startTime,
            endTime: result.endTime,
            tokens: result.tokens,
            confidence: result.confidence
        )
    }
}

// MARK: - Configuration

public struct WhisperKitConfiguration {
    public var model: String = "large-v3"
    public var computeUnits: ComputeUnits = .cpuAndNeuralEngine
    public var audioEncoderComputeUnits: ComputeUnits = .cpuAndNeuralEngine
    public var textDecoderComputeUnits: ComputeUnits = .cpuAndNeuralEngine
    public var sampleRate: Int = 16000
    public var enableChunking: Bool = true
    public var chunkingStrategy: TranscriptionOptions.ChunkingStrategy = .vad
    public var verbose: Bool = false
    public var logLevel: LogLevel = .info
    public var prewarm: Bool = true

    // Decoding options
    public var temperature: Float = 0.0
    public var temperatureIncrementOnFallback: Float = 0.2
    public var temperatureFallbackCount: Int = 5
    public var sampleLength: Int = 224
    public var topK: Int = 5
    public var usePrefillPrompt: Bool = true
    public var usePrefillCache: Bool = true
    public var skipSpecialTokens: Bool = true
    public var clipTimestamps: Bool = false

    public enum ComputeUnits {
        case cpuOnly
        case cpuAndGPU
        case cpuAndNeuralEngine
        case all
    }
}
```

---

## Audio Processing Pipeline

### Audio Processor Implementation

```swift
// Sources/RunAnywhere/Capabilities/Voice/Services/AudioProcessor.swift
import Foundation
import AVFoundation
import Accelerate

public class VoiceAudioProcessor: AudioProcessorProtocol {

    private let targetSampleRate: Int = 16000
    private let targetChannels: Int = 1

    public func processAudio(_ data: Data) async throws -> ProcessedAudio {
        // 1. Detect audio format
        let format = try detectAudioFormat(data)

        // 2. Convert to PCM if needed
        var pcmData = data
        if format.encoding != .pcm {
            pcmData = try await convertToPCM(data, format: format)
        }

        // 3. Resample to 16kHz if needed
        if format.sampleRate != targetSampleRate {
            pcmData = try await resample(
                audio: pcmData,
                from: format.sampleRate,
                to: targetSampleRate
            )
        }

        // 4. Convert to mono if needed
        if format.channels > 1 {
            pcmData = try await convertToMono(pcmData)
        }

        // 5. Normalize audio levels
        pcmData = try await normalizeAudio(pcmData)

        return ProcessedAudio(
            data: pcmData,
            format: AudioFormat(
                sampleRate: targetSampleRate,
                channels: targetChannels,
                bitsPerSample: 16,
                encoding: .pcm
            )
        )
    }

    public func resample(audio: Data, from: Int, to: Int) async throws -> Data {
        guard from != to else { return audio }

        // Use vDSP for efficient resampling
        let ratio = Double(to) / Double(from)
        let inputSamples = audio.count / 2 // 16-bit samples
        let outputSamples = Int(Double(inputSamples) * ratio)

        var outputData = Data(count: outputSamples * 2)

        audio.withUnsafeBytes { inputBytes in
            outputData.withUnsafeMutableBytes { outputBytes in
                let input = inputBytes.bindMemory(to: Int16.self)
                let output = outputBytes.bindMemory(to: Int16.self)

                // Simple linear interpolation resampling
                for i in 0..<outputSamples {
                    let inputIndex = Double(i) / ratio
                    let index = Int(inputIndex)
                    let fraction = inputIndex - Double(index)

                    if index < inputSamples - 1 {
                        let sample1 = Float(input[index])
                        let sample2 = Float(input[index + 1])
                        let interpolated = sample1 + Float(fraction) * (sample2 - sample1)
                        output[i] = Int16(interpolated)
                    } else {
                        output[i] = input[min(index, inputSamples - 1)]
                    }
                }
            }
        }

        return outputData
    }

    public func convertToMono(_ audio: Data) async throws -> Data {
        // Average stereo channels to mono
        let samples = audio.count / 4 // 16-bit stereo samples
        var monoData = Data(count: samples * 2)

        audio.withUnsafeBytes { stereoBytes in
            monoData.withUnsafeMutableBytes { monoBytes in
                let stereo = stereoBytes.bindMemory(to: Int16.self)
                let mono = monoBytes.bindMemory(to: Int16.self)

                for i in 0..<samples {
                    let left = Int32(stereo[i * 2])
                    let right = Int32(stereo[i * 2 + 1])
                    mono[i] = Int16((left + right) / 2)
                }
            }
        }

        return monoData
    }

    public func normalizeAudio(_ audio: Data) async throws -> Data {
        // Find peak amplitude
        var maxAmplitude: Int16 = 0
        audio.withUnsafeBytes { bytes in
            let samples = bytes.bindMemory(to: Int16.self)
            for i in 0..<(audio.count / 2) {
                maxAmplitude = max(maxAmplitude, abs(samples[i]))
            }
        }

        // Calculate normalization factor
        guard maxAmplitude > 0 else { return audio }
        let targetAmplitude: Int16 = Int16.max / 2 // Target 50% of max
        let factor = Float(targetAmplitude) / Float(maxAmplitude)

        // Apply normalization
        var normalizedData = audio
        normalizedData.withUnsafeMutableBytes { bytes in
            let samples = bytes.bindMemory(to: Int16.self)
            for i in 0..<(audio.count / 2) {
                samples[i] = Int16(Float(samples[i]) * factor)
            }
        }

        return normalizedData
    }

    private func detectAudioFormat(_ data: Data) throws -> AudioFormat {
        // Simple format detection based on data patterns
        // In production, use proper audio format detection
        return AudioFormat(
            sampleRate: 44100,
            channels: 2,
            bitsPerSample: 16,
            encoding: .pcm
        )
    }

    private func convertToPCM(_ data: Data, format: AudioFormat) async throws -> Data {
        // Convert compressed audio to PCM
        // This would use AVAudioConverter or similar
        return data
    }
}
```

---

## Streaming Implementation

### Real-time Streaming Transcriber

```swift
// Sources/RunAnywhere/Capabilities/Voice/Services/StreamingTranscriber.swift
import Foundation
import WhisperKit

public actor StreamingTranscriber {

    private let whisperKitAdapter: WhisperKitFrameworkAdapter
    private let bufferSize: Int = 16000 * 5 // 5 seconds of audio at 16kHz
    private var audioBuffer: [Float] = []
    private var lastProcessedIndex: Int = 0
    private var segmentId: Int = 0

    public init(whisperKitAdapter: WhisperKitFrameworkAdapter) {
        self.whisperKitAdapter = whisperKitAdapter
    }

    public func processAudioStream(
        _ audioStream: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptionSegment, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for await chunk in audioStream {
                        // Add audio to buffer
                        audioBuffer.append(contentsOf: chunk.floatData)

                        // Process when buffer reaches threshold
                        if audioBuffer.count >= bufferSize {
                            let segment = try await processBuffer()
                            if let segment = segment {
                                continuation.yield(segment)
                            }
                        }
                    }

                    // Process remaining audio
                    if !audioBuffer.isEmpty {
                        let segment = try await processBuffer(final: true)
                        if let segment = segment {
                            continuation.yield(segment)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func processBuffer(final: Bool = false) async throws -> TranscriptionSegment? {
        guard !audioBuffer.isEmpty else { return nil }

        // Extract audio segment to process
        let processingBuffer = Array(audioBuffer[lastProcessedIndex...])

        // Convert to Data for adapter
        let audioData = floatArrayToData(processingBuffer)

        // Transcribe segment
        let result = try await whisperKitAdapter.transcribe(
            audio: audioData,
            options: TranscriptionOptions(
                enableWordTimestamps: true,
                enableVAD: true
            )
        )

        // Update state
        if !result.text.isEmpty {
            segmentId += 1
            lastProcessedIndex = audioBuffer.count

            return TranscriptionSegment(
                id: segmentId,
                text: result.text,
                startTime: TimeInterval(lastProcessedIndex) / 16000.0,
                endTime: TimeInterval(audioBuffer.count) / 16000.0,
                tokens: [],
                confidence: result.confidence
            )
        }

        // Clear buffer if final
        if final {
            audioBuffer.removeAll()
            lastProcessedIndex = 0
        }

        return nil
    }

    private func floatArrayToData(_ floatArray: [Float]) -> Data {
        let int16Array = floatArray.map { Int16($0 * Float(Int16.max)) }
        return int16Array.withUnsafeBytes { Data($0) }
    }
}
```

---

## Model Management

### WhisperKit Model Manager

```swift
// Sources/RunAnywhere/Capabilities/Voice/Services/WhisperModelManager.swift
import Foundation
import WhisperKit

public actor WhisperModelManager {

    // Model variants with sizes
    public enum ModelVariant: String, CaseIterable {
        case tiny = "tiny"           // ~39 MB
        case tinyEn = "tiny.en"      // ~39 MB
        case base = "base"           // ~74 MB
        case baseEn = "base.en"      // ~74 MB
        case small = "small"         // ~244 MB
        case smallEn = "small.en"    // ~244 MB
        case medium = "medium"       // ~769 MB
        case mediumEn = "medium.en"  // ~769 MB
        case large = "large-v3"      // ~1550 MB
        case distilled = "distil-whisper/distil-large-v3" // ~756 MB

        var estimatedSize: Int64 {
            switch self {
            case .tiny, .tinyEn: return 39_000_000
            case .base, .baseEn: return 74_000_000
            case .small, .smallEn: return 244_000_000
            case .medium, .mediumEn: return 769_000_000
            case .large: return 1_550_000_000
            case .distilled: return 756_000_000
            }
        }

        var isEnglishOnly: Bool {
            return rawValue.contains(".en")
        }
    }

    private let fileManager = FileManager.default
    private let modelsDirectory: URL
    private var downloadedModels: Set<String> = []

    public init() {
        // Set up models directory
        let documentsPath = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        modelsDirectory = documentsPath.appendingPathComponent("WhisperKitModels")

        // Create directory if needed
        try? fileManager.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )

        // Scan for existing models
        scanDownloadedModels()
    }

    // MARK: - Model Management

    public func downloadModel(
        _ variant: ModelVariant,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        guard !isModelDownloaded(variant) else {
            throw VoiceError.modelAlreadyDownloaded(variant.rawValue)
        }

        // Check available storage
        let availableSpace = try getAvailableSpace()
        guard availableSpace > variant.estimatedSize * 2 else {
            throw VoiceError.insufficientStorage(
                required: variant.estimatedSize,
                available: availableSpace
            )
        }

        // Download using WhisperKit's built-in downloader
        let modelPath = try await WhisperKit.download(
            variant: variant.rawValue,
            progressCallback: { progress in
                progressHandler?(progress.fractionCompleted)
            }
        )

        // Register downloaded model
        downloadedModels.insert(variant.rawValue)
    }

    public func deleteModel(_ variant: ModelVariant) throws {
        let modelPath = modelsDirectory.appendingPathComponent(variant.rawValue)

        if fileManager.fileExists(atPath: modelPath.path) {
            try fileManager.removeItem(at: modelPath)
            downloadedModels.remove(variant.rawValue)
        }
    }

    public func isModelDownloaded(_ variant: ModelVariant) -> Bool {
        return downloadedModels.contains(variant.rawValue)
    }

    public func getDownloadedModels() -> [ModelVariant] {
        return ModelVariant.allCases.filter { isModelDownloaded($0) }
    }

    public func recommendModel(for device: DeviceCapabilities) -> ModelVariant {
        // Recommend based on device capabilities
        if device.totalMemory > 8_000_000_000 && device.hasNeuralEngine {
            // High-end device: Use large model
            return .large
        } else if device.totalMemory > 4_000_000_000 {
            // Mid-range device: Use medium or distilled
            return device.hasNeuralEngine ? .distilled : .medium
        } else if device.totalMemory > 2_000_000_000 {
            // Lower-end device: Use small
            return .small
        } else {
            // Very constrained device: Use base or tiny
            return device.totalMemory > 1_000_000_000 ? .base : .tiny
        }
    }

    // MARK: - Private Helpers

    private func scanDownloadedModels() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents {
            if let variant = ModelVariant(rawValue: url.lastPathComponent) {
                downloadedModels.insert(variant.rawValue)
            }
        }
    }

    private func getAvailableSpace() throws -> Int64 {
        let attributes = try fileManager.attributesOfFileSystem(
            forPath: modelsDirectory.path
        )

        return attributes[.systemFreeSize] as? Int64 ?? 0
    }
}
```

---

## Performance Optimization

### Optimization Strategies

```swift
// Sources/RunAnywhere/Capabilities/Voice/Services/VoiceOptimizer.swift
public class VoiceOptimizer {

    private let hardwareDetector: HardwareDetector
    private let memoryService: MemoryService
    private let modelManager: WhisperModelManager

    public struct OptimizationProfile {
        let modelVariant: WhisperModelManager.ModelVariant
        let computeUnits: WhisperKitConfiguration.ComputeUnits
        let enableStreaming: Bool
        let chunkDuration: TimeInterval
        let vadSensitivity: TranscriptionOptions.VADSensitivity
        let enableWordTimestamps: Bool
        let prewarm: Bool
    }

    public func createOptimizedProfile() async -> OptimizationProfile {
        let capabilities = hardwareDetector.detectCapabilities()
        let availableMemory = memoryService.getAvailableMemory()

        // Select model based on device capabilities
        let modelVariant = await modelManager.recommendModel(for: capabilities)

        // Configure compute units
        let computeUnits: WhisperKitConfiguration.ComputeUnits
        if capabilities.hasNeuralEngine {
            computeUnits = .cpuAndNeuralEngine
        } else if capabilities.hasGPU {
            computeUnits = .cpuAndGPU
        } else {
            computeUnits = .cpuOnly
        }

        // Configure streaming based on memory
        let enableStreaming = availableMemory < 2_000_000_000

        // Configure chunk duration
        let chunkDuration: TimeInterval = enableStreaming ? 2.0 : 5.0

        // Configure VAD sensitivity
        let vadSensitivity: TranscriptionOptions.VADSensitivity
        if capabilities.processorInfo.coreCount >= 8 {
            vadSensitivity = .high
        } else if capabilities.processorInfo.coreCount >= 4 {
            vadSensitivity = .medium
        } else {
            vadSensitivity = .low
        }

        // Word timestamps only on powerful devices
        let enableWordTimestamps = capabilities.totalMemory > 4_000_000_000

        // Prewarm on devices with sufficient memory
        let prewarm = availableMemory > 1_000_000_000

        return OptimizationProfile(
            modelVariant: modelVariant,
            computeUnits: computeUnits,
            enableStreaming: enableStreaming,
            chunkDuration: chunkDuration,
            vadSensitivity: vadSensitivity,
            enableWordTimestamps: enableWordTimestamps,
            prewarm: prewarm
        )
    }
}
```

---

## Sample App Integration

### Voice Feature in Sample App

```swift
// Examples/iOS/RunAnywhereAI/Features/Voice/VoiceView.swift
import SwiftUI
import RunAnywhere

struct VoiceView: View {
    @StateObject private var viewModel = VoiceViewModel()
    @State private var isRecording = false
    @State private var transcription = ""
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 20) {
            // Transcription Display
            ScrollView {
                Text(transcription)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            }
            .frame(maxHeight: 300)

            // Status Indicator
            if isProcessing {
                HStack {
                    ProgressView()
                    Text("Processing...")
                        .font(.caption)
                }
            }

            // Record Button
            Button(action: toggleRecording) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(isRecording ? .red : .blue)
            }
            .disabled(isProcessing)

            // Model Selection
            Picker("Model", selection: $viewModel.selectedModel) {
                ForEach(viewModel.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .disabled(isRecording || isProcessing)

            // Settings
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable Streaming", isOn: $viewModel.enableStreaming)
                Toggle("Word Timestamps", isOn: $viewModel.enableWordTimestamps)
                Toggle("Auto Language Detection", isOn: $viewModel.autoDetectLanguage)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
        }
        .padding()
        .navigationTitle("Voice Recognition")
        .onAppear {
            viewModel.initialize()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        transcription = ""

        Task {
            do {
                if viewModel.enableStreaming {
                    // Streaming transcription
                    for try await segment in viewModel.startStreamingTranscription() {
                        transcription += segment.text + " "
                    }
                } else {
                    // File-based transcription
                    isProcessing = true
                    let result = try await viewModel.startRecording()
                    transcription = result.text
                    isProcessing = false
                }
            } catch {
                print("Transcription error: \(error)")
                isProcessing = false
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        viewModel.stopRecording()
    }
}

// View Model
class VoiceViewModel: ObservableObject {
    @Published var availableModels: [String] = []
    @Published var selectedModel = "large-v3"
    @Published var enableStreaming = true
    @Published var enableWordTimestamps = true
    @Published var autoDetectLanguage = true

    private var voiceSession: VoiceSession?

    func initialize() {
        Task {
            do {
                // Initialize SDK if needed
                try await RunAnywhereSDK.shared.initialize(
                    configuration: Configuration(apiKey: "demo")
                )

                // Get available models
                availableModels = await getAvailableModels()

            } catch {
                print("Initialization error: \(error)")
            }
        }
    }

    func startStreamingTranscription() -> AsyncThrowingStream<TranscriptionSegment, Error> {
        RunAnywhereSDK.shared.transcribeStream(
            audioStream: createAudioStream(),
            options: TranscriptionOptions(
                language: autoDetectLanguage ? .auto : .english,
                enableWordTimestamps: enableWordTimestamps,
                enableVAD: true
            )
        )
    }

    func startRecording() async throws -> TranscriptionResult {
        // Start voice session
        voiceSession = try await RunAnywhereSDK.shared.startVoiceSession(
            config: VoiceSessionConfig(
                recognitionModel: selectedModel,
                enableWordTimestamps: enableWordTimestamps
            )
        )

        // Record audio
        let audioData = try await recordAudio()

        // Transcribe
        return try await RunAnywhereSDK.shared.transcribe(
            audio: audioData,
            options: TranscriptionOptions(
                language: autoDetectLanguage ? .auto : .english,
                enableWordTimestamps: enableWordTimestamps
            )
        )
    }

    func stopRecording() {
        Task {
            try? await RunAnywhereSDK.shared.endVoiceSession()
        }
    }

    private func getAvailableModels() async -> [String] {
        // Return available WhisperKit models
        return [
            "tiny",
            "base",
            "small",
            "medium",
            "large-v3",
            "distil-large-v3"
        ]
    }

    private func createAudioStream() -> AsyncStream<AudioChunk> {
        // Create audio stream from microphone
        // Implementation depends on platform
        AsyncStream { continuation in
            // Audio capture implementation
        }
    }

    private func recordAudio() async throws -> Data {
        // Record audio from microphone
        // Implementation depends on platform
        return Data()
    }
}
```

---

## Testing Strategy

### Unit Tests

```swift
// Tests/VoiceTests/WhisperKitAdapterTests.swift
import XCTest
@testable import RunAnywhere
import WhisperKit

final class WhisperKitAdapterTests: XCTestCase {

    var adapter: WhisperKitFrameworkAdapter!

    override func setUp() async throws {
        let config = WhisperKitConfiguration(
            model: "tiny",
            computeUnits: .cpuOnly,
            verbose: false
        )

        adapter = WhisperKitFrameworkAdapter(
            configuration: config,
            logger: SDKLogger.shared,
            performanceMonitor: PerformanceMonitor()
        )

        try await adapter.initialize()
    }

    func testTranscription() async throws {
        // Load test audio
        let audioURL = Bundle.module.url(forResource: "test", withExtension: "wav")!
        let audioData = try Data(contentsOf: audioURL)

        // Transcribe
        let result = try await adapter.transcribe(
            audio: audioData,
            options: TranscriptionOptions()
        )

        // Verify
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertGreaterThan(result.confidence, 0)
        XCTAssertNotNil(result.language)
    }

    func testStreamingTranscription() async throws {
        // Create audio stream
        let audioStream = createTestAudioStream()

        // Transcribe stream
        let transcriptionStream = adapter.transcribeStream(audioStream)

        var segments: [TranscriptionSegment] = []
        for try await segment in transcriptionStream {
            segments.append(segment)
        }

        // Verify
        XCTAssertFalse(segments.isEmpty)
        XCTAssertGreaterThan(segments.first?.confidence ?? 0, 0)
    }

    func testLanguageDetection() async throws {
        // Test with English audio
        let englishAudio = loadTestAudio("english")
        let detectedLang = try await adapter.detectLanguage(audio: englishAudio)
        XCTAssertEqual(detectedLang, "en")

        // Test with Spanish audio
        let spanishAudio = loadTestAudio("spanish")
        let detectedLang2 = try await adapter.detectLanguage(audio: spanishAudio)
        XCTAssertEqual(detectedLang2, "es")
    }

    func testModelManagement() async throws {
        // Test loading different model
        try await adapter.loadModel("base")
        XCTAssertTrue(adapter.isModelLoaded())

        // Test unloading
        await adapter.unloadModel()
        XCTAssertFalse(adapter.isModelLoaded())
    }
}
```

---

## Migration & Deployment

### Migration Steps

1. **Add WhisperKit Dependency**
```swift
// Package.swift
.package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.4")
```

2. **Create Voice Capability Structure**
```bash
# Create directories
mkdir -p Sources/RunAnywhere/Capabilities/Voice/{Models,Services,Protocols,Extensions,Frameworks}
```

3. **Implement Core Components**
- WhisperKitFrameworkAdapter
- AudioProcessor
- StreamingTranscriber
- ModelManager

4. **Integrate with ServiceContainer**
```swift
// Add to ServiceContainer.swift
private(set) lazy var voiceService: VoiceService = {
    VoiceService(
        speechRecognition: speechRecognitionService,
        textToSpeech: textToSpeechService,
        performanceMonitor: performanceMonitor
    )
}()
```

5. **Add Public API Extensions**
```swift
// RunAnywhereSDK+Voice.swift
public extension RunAnywhereSDK {
    func transcribe(audio: Data, options: TranscriptionOptions?) async throws -> TranscriptionResult
    // ... other voice methods
}
```

6. **Update Sample App**
- Add voice UI components
- Implement voice view model
- Add microphone permissions

7. **Test Integration**
- Unit tests for adapter
- Integration tests for voice pipeline
- Performance benchmarks

### Deployment Checklist

- [ ] WhisperKit dependency added
- [ ] Voice capability module created
- [ ] WhisperKitFrameworkAdapter implemented
- [ ] Audio processing pipeline complete
- [ ] Streaming support implemented
- [ ] Model management system ready
- [ ] ServiceContainer integration done
- [ ] Public API extensions added
- [ ] Sample app updated
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] Performance benchmarks met
- [ ] Documentation updated
- [ ] Migration guide created

---

## Conclusion

The WhisperKit integration provides a robust, production-ready speech-to-text capability for the RunAnywhere SDK. The modular architecture ensures easy maintenance and future enhancements while maintaining compatibility with the existing SDK infrastructure.

Key advantages:
- **Minimal integration effort** - Clean adapter pattern
- **Excellent performance** - Neural Engine optimization
- **Complete privacy** - On-device processing
- **Production ready** - Mature, tested codebase
- **Future proof** - Active development and updates

---

*Document Version: 1.0*
*Last Updated: January 2025*
*Status: Ready for Implementation*
