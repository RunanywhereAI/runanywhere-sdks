# RunAnywhere SDK - Voice RTC Implementation Plan
## LiveKit-Inspired Architecture for Offline Voice AI

## Executive Summary

This document provides a streamlined implementation plan for real-time voice capabilities in the RunAnywhere SDK, adapted from LiveKit's architecture for fully offline operation. The plan focuses on **minimal necessary changes** to transform batch processing into real-time streaming.

## Current Implementation Status

### ✅ ALREADY IMPLEMENTED (No Changes Needed)
- **VoiceOrchestrator**: Complete pipeline with streaming events
- **Streaming LLM**: Token-by-token generation with sentence-level TTS
- **Voice Protocols**: Complete interfaces with streaming support
- **Audio Processing**: Professional signal processing pipeline
- **VAD**: Energy-based detection with streaming capability
- **TTS Integration**: System TTS with AVSpeechSynthesizer
- **Error Handling**: Comprehensive timeout and error recovery

### ⚠️ PARTIALLY IMPLEMENTED (Needs Enhancement)
- **WhisperKit STT**: Has protocol but missing streaming implementation
- **Audio Capture**: Has batch recording but needs continuous mode
- **Sample App**: Has UI but uses batch processing

### ❌ NOT IMPLEMENTED (New Components)
- **VoiceSession API**: LiveKit-like simple interface
- **Continuous Audio Pipeline**: Real-time audio streaming
- **Interruption Handling**: User interrupt support

## 1. Architecture Overview

### 1.1 Current vs Target
**Current**: Audio Batch (5-10s) → WhisperKit → LLM → TTS → Playback (Total: 2-4s latency)

**Target**: Audio Stream (20ms chunks) → Real-time STT → Streaming LLM → Progressive TTS (Total: <500ms first response)

### 1.2 Core Architecture (Adapted from LiveKit)

In LiveKit, the flow is:
```
Client ↔ WebRTC ↔ Server ↔ Agent ↔ AI Services
```

For RunAnywhere (offline):
```
Audio Input ↔ VoiceSession ↔ Pipeline Coordinator ↔ On-Device Models
```

## 2. Proposed Architecture

### 2.1 High-Level Design

```
┌─────────────────────────────────────────────────────────────────────┐
│                    RunAnywhere Voice RTC System                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │                    VoiceSession (Like LiveKit Room)         │   │
│  │  • Session state management                                │   │
│  │  • Delegate pattern for events                             │   │
│  │  • Audio control (start/stop)                              │   │
│  └────────────────────────────────────────────────────────────┘   │
│                              │                                     │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │         VoicePipelineCoordinator (Like LiveKit Agent)       │   │
│  │  • Coordinates STT → LLM → TTS pipeline                    │   │
│  │  • Manages conversation context                            │   │
│  │  • Handles interruptions                                   │   │
│  └────────────────────────────────────────────────────────────┘   │
│                              │                                     │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┐   │
│  │ AudioStream  │ Streaming    │ Streaming    │ Streaming    │   │
│  │ Manager      │ WhisperKit   │ LLM Service  │ TTS Service  │   │
│  │ (Transport)  │ (STT)        │ (Generation) │ (Synthesis)  │   │
│  └──────────────┴──────────────┴──────────────┴──────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Key Components Mapping

| LiveKit Component | RunAnywhere Equivalent | Purpose |
|------------------|------------------------|---------|
| Room | VoiceSession | Manages session lifecycle and events |
| SignalClient | (Not needed - local) | WebSocket signaling → Direct calls |
| Transport (WebRTC) | AudioStreamManager | Audio I/O and streaming |
| Agent Worker | VoicePipelineCoordinator | Orchestrates AI pipeline |
| DataChannel/RPC | Direct method calls | No network needed for control |

### 2.3 Core Components (Minimal Changes)

```swift
// 1. VoiceSession - Public API (NEW - Like LiveKit Room)
public class VoiceSession {
    public let id: String
    public var state: SessionState
    public weak var delegate: VoiceSessionDelegate?

    public func connect() async throws
    public func disconnect() async
    public func startListening() async throws
    public func stopListening() async
    public func interrupt() async
}

// 2. VoiceSessionDelegate - Events (NEW - Like LiveKit)
public protocol VoiceSessionDelegate: AnyObject {
    func voiceSession(_ session: VoiceSession, didChangeState state: SessionState)
    func voiceSession(_ session: VoiceSession, didReceiveTranscript text: String, isFinal: Bool)
    func voiceSession(_ session: VoiceSession, didReceiveResponse text: String)
    func voiceSession(_ session: VoiceSession, didEncounterError error: Error)
}

// 3. AudioStreamManager - Real-time audio (NEW - Like WebRTC Transport)
class AudioStreamManager {
    func startInputStream() -> AsyncStream<AudioChunk>
    func startOutputStream() -> AsyncStream<AudioChunk>
    func playAudioStream(_ stream: AsyncStream<AudioChunk>)
}

// 4. VoicePipelineCoordinator - Orchestration (ENHANCE existing VoiceOrchestrator)
class VoicePipelineCoordinator {
    // Reuse existing VoiceOrchestrator logic
    // Add streaming support
    func processAudioStream(_ stream: AsyncStream<AudioChunk>) async
}

## 3. Minimal Change Implementation Plan

### Phase 1: Enable Continuous Audio Capture (2 hours)

**📝 MODIFY 1 FILE:**
```swift
// FILE: examples/ios/RunAnywhereAI/Core/Services/Audio/AudioCapture.swift

// ADD these properties to class:
private var continuationTask: Task<Void, Never>?
private var streamContinuation: AsyncStream<AudioChunk>.Continuation?

// ADD this method to existing AudioCapture class:
func startContinuousCapture() -> AsyncStream<AudioChunk> {
    // Stop any existing capture
    stopCapture()

    return AsyncStream { continuation in
        self.streamContinuation = continuation

        // Configure audio session for real-time
        setupAudioSession()

        // Install tap with small buffer for low latency
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0,
                                        bufferSize: 512,  // ~11ms at 44.1kHz
                                        format: format) { [weak self] buffer, time in
            guard let self = self else { return }

            // Process audio through existing pipeline
            let processed = self.audioProcessor.process(buffer)

            // Convert to 16kHz mono for WhisperKit
            let resampled = self.resampleTo16kHz(processed)

            // Create AudioChunk (need to add this model to SDK)
            let chunk = AudioChunk(
                data: resampled,
                timestamp: Date(),
                duration: Double(buffer.frameLength) / format.sampleRate
            )

            continuation.yield(chunk)
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            logger.info("Continuous audio capture started")
        } catch {
            logger.error("Failed to start audio engine: \(error)")
            continuation.finish()
        }
    }
}

// ADD method to stop continuous capture:
func stopContinuousCapture() {
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    streamContinuation?.finish()
    streamContinuation = nil
    logger.info("Continuous audio capture stopped")
}

// ADD helper method for resampling:
private func resampleTo16kHz(_ buffer: AVAudioPCMBuffer) -> Data {
    // Use existing audioProcessor's resample method
    let resampled = audioProcessor.resample(buffer, targetSampleRate: 16000)
    return resampled.toData() // Need to implement this extension
}
```

**❌ REMOVE from AudioCapture:**
- Nothing to remove, keep batch methods for backward compatibility

---

### Phase 2: Add Streaming to WhisperKit (3 hours)

**📝 MODIFY 1 FILE:**
```swift
// FILE: examples/ios/RunAnywhereAI/Core/Services/WhisperKit/WhisperKitService.swift

// ADD these properties to class:
private var streamingTask: Task<Void, Error>?
private var audioAccumulator = Data()
private let minAudioLength = 8000  // 500ms at 16kHz
private let contextOverlap = 1600   // 100ms overlap for context

// IMPLEMENT the existing protocol method that was empty:
func transcribeStream(
    audioStream: AsyncStream<AudioChunk>,
    options: TranscriptionOptions
) -> AsyncThrowingStream<TranscriptionSegment, Error> {
    AsyncThrowingStream { continuation in
        self.streamingTask = Task {
            do {
                // Ensure WhisperKit is loaded
                guard let whisperKit = self.whisperKit else {
                    if actualMode {
                        // Load model if not loaded
                        try await loadModelIfNeeded()
                        guard let kit = self.whisperKit else {
                            throw VoiceServiceError.modelNotLoaded
                        }
                    } else {
                        // Simulated mode
                        await handleSimulatedStreaming(audioStream, continuation)
                        return
                    }
                }

                // Process audio stream
                var audioBuffer = Data()
                var lastTranscript = ""

                for await chunk in audioStream {
                    audioBuffer.append(chunk.data)

                    // Process when we have enough audio (500ms)
                    if audioBuffer.count >= minAudioLength {
                        // Convert to float array for WhisperKit
                        let floatArray = audioBuffer.toFloatArray()

                        // Transcribe using WhisperKit
                        let results = try await whisperKit.transcribe(
                            audioArray: floatArray,
                            decodeOptions: DecodingOptions(
                                task: options.task == .translate ? .translate : .transcribe,
                                language: options.language,
                                temperature: 0.0,
                                temperatureFallbackCount: 0,
                                sampleLength: 224,  // Shorter for streaming
                                usePrefillPrompt: false,
                                detectLanguage: false,
                                skipSpecialTokens: true,
                                withoutTimestamps: false
                            )
                        )

                        // Get the transcribed text
                        if let result = results.first {
                            let newText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                            // Only yield if there's new content
                            if !newText.isEmpty && newText != lastTranscript {
                                let segment = TranscriptionSegment(
                                    text: newText,
                                    startTime: chunk.timestamp.addingTimeInterval(-0.5),
                                    endTime: chunk.timestamp,
                                    confidence: 0.95,
                                    language: options.language ?? "en"
                                )
                                continuation.yield(segment)
                                lastTranscript = newText
                            }
                        }

                        // Keep last 100ms for context continuity
                        audioBuffer = Data(audioBuffer.suffix(contextOverlap))
                    }
                }

                // Process any remaining audio
                if audioBuffer.count > 0 {
                    // Final transcription with remaining audio
                    let floatArray = audioBuffer.toFloatArray()
                    let results = try await whisperKit.transcribe(audioArray: floatArray)
                    if let result = results.first {
                        let segment = TranscriptionSegment(
                            text: result.text,
                            startTime: Date().addingTimeInterval(-0.1),
                            endTime: Date(),
                            confidence: 0.95,
                            language: options.language ?? "en"
                        )
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

// ADD helper method for simulated streaming:
private func handleSimulatedStreaming(
    _ audioStream: AsyncStream<AudioChunk>,
    _ continuation: AsyncThrowingStream<TranscriptionSegment, Error>.Continuation
) async {
    let simulatedPhrases = [
        "Hello, how can I",
        "Hello, how can I help you",
        "Hello, how can I help you today?"
    ]

    var index = 0
    for await _ in audioStream {
        if index < simulatedPhrases.count {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
            let segment = TranscriptionSegment(
                text: simulatedPhrases[index],
                startTime: Date(),
                endTime: Date(),
                confidence: 0.95,
                language: "en"
            )
            continuation.yield(segment)
            index += 1
        }
    }
    continuation.finish()
}

// ADD Data extension for float conversion:
extension Data {
    func toFloatArray() -> [Float] {
        let shorts = self.withUnsafeBytes { buffer in
            buffer.bindMemory(to: Int16.self)
        }
        return shorts.map { Float($0) / Float(Int16.max) }
    }
}
```

---

### Phase 3: Create Simple VoiceSession API (2 hours)

**➕ ADD 2 NEW FILES:**

**FILE 1: VoiceSession.swift**
```swift
// FILE: sdk/runanywhere-swift/Public/Voice/VoiceSession.swift

import Foundation
import AVFoundation

/// LiveKit-style Voice Session for real-time conversation
public class VoiceSession {
    // MARK: - Properties
    public let id: String = UUID().uuidString
    public private(set) var state: SessionState = .disconnected
    public weak var delegate: VoiceSessionDelegate?

    private let orchestrator: VoiceOrchestrator
    private var audioCapture: AudioCapture?
    private var streamTask: Task<Void, Never>?
    private var vadProcessor: SimpleVAD?
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "VoiceSession")

    // Configuration
    private let config: VoiceSessionConfig

    // MARK: - Session States
    public enum SessionState {
        case disconnected
        case connecting
        case connected
        case listening
        case processing
        case speaking
        case error(Error)
    }

    // MARK: - Initialization
    init(orchestrator: VoiceOrchestrator, config: VoiceSessionConfig = .default) {
        self.orchestrator = orchestrator
        self.config = config
    }

    // MARK: - Public Methods

    /// Connect the voice session and start audio pipeline
    public func connect() async throws {
        guard state == .disconnected else {
            throw VoiceSessionError.invalidState("Already connected")
        }

        updateState(.connecting)

        do {
            // Initialize audio capture from sample app
            // TODO: Move AudioCapture to SDK in future
            audioCapture = AudioCapture()

            // Initialize VAD if enabled
            if config.vadEnabled {
                vadProcessor = SimpleVAD(sensitivity: config.vadSensitivity)
            }

            // Start continuous audio capture
            guard let audioStream = audioCapture?.startContinuousCapture() else {
                throw VoiceSessionError.audioInitializationFailed
            }

            updateState(.connected)

            // Start processing pipeline
            await startPipeline(audioStream: audioStream)

        } catch {
            updateState(.error(error))
            throw error
        }
    }

    /// Disconnect the session and cleanup
    public func disconnect() async {
        streamTask?.cancel()
        audioCapture?.stopContinuousCapture()
        updateState(.disconnected)
        logger.info("Voice session disconnected")
    }

    /// Start listening for user input
    public func startListening() async throws {
        guard state == .connected else {
            throw VoiceSessionError.invalidState("Not connected")
        }
        updateState(.listening)
    }

    /// Stop listening
    public func stopListening() async {
        if state == .listening {
            updateState(.connected)
        }
    }

    /// Interrupt current generation
    public func interrupt() async {
        logger.info("Interrupting current generation")
        // Cancel current pipeline task and restart
        streamTask?.cancel()

        if let audioStream = audioCapture?.startContinuousCapture() {
            await startPipeline(audioStream: audioStream)
        }
    }

    // MARK: - Private Methods

    private func startPipeline(audioStream: AsyncStream<AudioChunk>) async {
        streamTask = Task { [weak self] in
            guard let self = self else { return }

            // Process through VAD if enabled
            let processedStream: AsyncStream<AudioChunk>
            if let vad = self.vadProcessor {
                processedStream = self.applyVAD(to: audioStream, using: vad)
            } else {
                processedStream = audioStream
            }

            // Configure pipeline
            let pipelineConfig = VoicePipelineConfig(
                sttTimeout: self.config.sttTimeout,
                llmTimeout: self.config.llmTimeout,
                ttsTimeout: self.config.ttsTimeout,
                enableStreaming: true,
                generationOptions: self.config.generationOptions
            )

            // Process through orchestrator
            do {
                for try await event in self.orchestrator.processVoicePipeline(
                    audio: processedStream,
                    config: pipelineConfig
                ) {
                    self.handlePipelineEvent(event)
                }
            } catch {
                self.logger.error("Pipeline error: \(error)")
                self.updateState(.error(error))
                self.delegate?.voiceSession(self, didEncounterError: error)
            }
        }
    }

    private func applyVAD(to stream: AsyncStream<AudioChunk>, using vad: SimpleVAD) -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            Task {
                for await chunk in stream {
                    // Only yield chunks with speech
                    if vad.detectActivity(chunk.data) {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }
        }
    }

    private func handlePipelineEvent(_ event: VoicePipelineEvent) {
        switch event {
        case .started(let sessionId):
            logger.debug("Pipeline started: \(sessionId)")

        case .transcriptionStarted:
            updateState(.listening)

        case .transcriptionProgress(let text):
            delegate?.voiceSession(self, didReceiveTranscript: text, isFinal: false)

        case .transcriptionCompleted(let finalText):
            delegate?.voiceSession(self, didReceiveTranscript: finalText, isFinal: true)
            updateState(.processing)

        case .llmGenerationStarted:
            updateState(.processing)

        case .llmGenerationProgress(let text):
            delegate?.voiceSession(self, didReceiveResponse: text)

        case .llmGenerationCompleted(let fullText):
            delegate?.voiceSession(self, didReceiveResponse: fullText)

        case .ttsStarted:
            updateState(.speaking)

        case .ttsProgress(let audioData):
            delegate?.voiceSession(self, didReceiveAudio: audioData)

        case .ttsCompleted:
            updateState(.connected)

        case .completed(let result):
            logger.info("Pipeline completed in \(result.totalDuration)s")
            updateState(.connected)

        case .error(let stage, let error):
            logger.error("Pipeline error at \(stage): \(error)")
            delegate?.voiceSession(self, didEncounterError: error)
        }
    }

    private func updateState(_ newState: SessionState) {
        state = newState
        delegate?.voiceSession(self, didChangeState: newState)
    }
}

// MARK: - VoiceSessionConfig
public struct VoiceSessionConfig {
    public var vadEnabled: Bool = true
    public var vadSensitivity: Float = 0.5
    public var sttTimeout: TimeInterval = 30
    public var llmTimeout: TimeInterval = 60
    public var ttsTimeout: TimeInterval = 30
    public var language: String = "en"
    public var generationOptions: GenerationOptions?

    public static let `default` = VoiceSessionConfig()

    public init(
        vadEnabled: Bool = true,
        vadSensitivity: Float = 0.5,
        language: String = "en"
    ) {
        self.vadEnabled = vadEnabled
        self.vadSensitivity = vadSensitivity
        self.language = language
    }
}

// MARK: - VoiceSessionError
public enum VoiceSessionError: LocalizedError {
    case invalidState(String)
    case audioInitializationFailed
    case pipelineError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .audioInitializationFailed:
            return "Failed to initialize audio capture"
        case .pipelineError(let error):
            return "Pipeline error: \(error.localizedDescription)"
        }
    }
}
```

**FILE 2: VoiceSessionDelegate.swift**
```swift
// FILE: sdk/runanywhere-swift/Public/Voice/VoiceSessionDelegate.swift

import Foundation

/// Delegate protocol for VoiceSession events (LiveKit-style)
public protocol VoiceSessionDelegate: AnyObject {
    /// Called when session state changes
    func voiceSession(_ session: VoiceSession, didChangeState state: VoiceSession.SessionState)

    /// Called when transcription is received (partial or final)
    func voiceSession(_ session: VoiceSession, didReceiveTranscript text: String, isFinal: Bool)

    /// Called when AI response is received
    func voiceSession(_ session: VoiceSession, didReceiveResponse text: String)

    /// Called when audio data is available (for TTS playback)
    func voiceSession(_ session: VoiceSession, didReceiveAudio data: Data)

    /// Called when an error occurs
    func voiceSession(_ session: VoiceSession, didEncounterError error: Error)
}

// Optional methods with default implementation
public extension VoiceSessionDelegate {
    func voiceSession(_ session: VoiceSession, didReceiveAudio data: Data) {
        // Default: no-op
    }
}
```

**📝 MODIFY SDK to add factory method:**
```swift
// FILE: sdk/runanywhere-swift/Public/RunAnywhereSDK.swift

// ADD this method to RunAnywhereSDK class:
/// Create a new voice session for real-time conversation
public func createVoiceSession(config: VoiceSessionConfig = .default) -> VoiceSession {
    logger.info("Creating new voice session")

    // Get or create voice orchestrator from service container
    let orchestrator = serviceContainer.voiceOrchestrator

    // Create and return session
    return VoiceSession(orchestrator: orchestrator, config: config)
}

// Also ADD import at top if needed:
import AVFoundation
```

---

### Phase 4: Update Sample App (1 hour)

**📝 MODIFY ViewModel:**
```swift
// FILE: examples/ios/RunAnywhereAI/Features/Voice/VoiceAssistantViewModel.swift

import SwiftUI
import Combine

@MainActor
class VoiceAssistantViewModel: ObservableObject, VoiceSessionDelegate {
    // MARK: - Keep these existing properties
    @Published var currentTranscript: String = ""
    @Published var assistantResponse: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    // MARK: - Add new properties for real-time
    private var voiceSession: VoiceSession?
    @Published var sessionState: VoiceSession.SessionState = .disconnected
    @Published var isListening: Bool = false

    // MARK: - REMOVE these old batch methods
    // DELETE: func startRecording()
    // DELETE: func stopRecording()
    // DELETE: func processRecording()
    // DELETE: private func processVoiceQuery(audio: Data) async
    // DELETE: private var audioCapture: AudioCapture?
    // DELETE: private var recordingTask: Task<Void, Error>?

    // MARK: - ADD new real-time methods

    /// Start real-time conversation
    func startConversation() async {
        do {
            // Create voice session with configuration
            let config = VoiceSessionConfig(
                vadEnabled: true,
                vadSensitivity: 0.5,
                language: "en"
            )

            voiceSession = RunAnywhereSDK.shared.createVoiceSession(config: config)
            voiceSession?.delegate = self

            // Connect and start listening
            try await voiceSession?.connect()
            try await voiceSession?.startListening()

            isListening = true
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start conversation: \(error.localizedDescription)"
            isListening = false
        }
    }

    /// Stop conversation
    func stopConversation() async {
        isListening = false
        await voiceSession?.disconnect()
        voiceSession = nil
    }

    /// Interrupt AI response
    func interruptResponse() async {
        await voiceSession?.interrupt()
    }

    // MARK: - VoiceSessionDelegate Implementation

    func voiceSession(_ session: VoiceSession, didChangeState state: VoiceSession.SessionState) {
        DispatchQueue.main.async {
            self.sessionState = state

            switch state {
            case .listening:
                self.isProcessing = false
                self.isListening = true
            case .processing, .speaking:
                self.isProcessing = true
            case .error(let error):
                self.errorMessage = error.localizedDescription
                self.isProcessing = false
                self.isListening = false
            default:
                break
            }
        }
    }

    func voiceSession(_ session: VoiceSession, didReceiveTranscript text: String, isFinal: Bool) {
        DispatchQueue.main.async {
            self.currentTranscript = text

            // Clear response when new transcript starts
            if !isFinal && self.assistantResponse.isEmpty == false {
                self.assistantResponse = ""
            }
        }
    }

    func voiceSession(_ session: VoiceSession, didReceiveResponse text: String) {
        DispatchQueue.main.async {
            self.assistantResponse = text
        }
    }

    func voiceSession(_ session: VoiceSession, didEncounterError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isProcessing = false
        }
    }

    func voiceSession(_ session: VoiceSession, didReceiveAudio data: Data) {
        // Audio playback handled by TTS service
        // Can add custom audio handling here if needed
    }
}
```

**📝 MODIFY View:**
```swift
// FILE: examples/ios/RunAnywhereAI/Features/Voice/VoiceAssistantView.swift

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAssistantViewModel()

    var body: some View {
        VStack(spacing: 20) {
            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.caption)
            }

            // Transcript display
            VStack(alignment: .leading, spacing: 10) {
                Text("You:")
                    .font(.headline)
                Text(viewModel.currentTranscript.isEmpty ? "Tap mic to speak..." : viewModel.currentTranscript)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            }

            // AI Response
            VStack(alignment: .leading, spacing: 10) {
                Text("Assistant:")
                    .font(.headline)
                Text(viewModel.assistantResponse.isEmpty ? "Waiting..." : viewModel.assistantResponse)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
            }

            Spacer()

            // Control buttons
            HStack(spacing: 30) {
                // Mic button - tap to start/stop
                Button(action: {
                    Task {
                        if viewModel.isListening {
                            await viewModel.stopConversation()
                        } else {
                            await viewModel.startConversation()
                        }
                    }
                }) {
                    Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 40))
                        .foregroundColor(viewModel.isListening ? .red : .blue)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Color.gray.opacity(0.1)))
                }
                .disabled(viewModel.isProcessing && !viewModel.isListening)

                // Interrupt button - only shown when AI is responding
                if viewModel.sessionState == .speaking || viewModel.sessionState == .processing {
                    Button(action: {
                        Task {
                            await viewModel.interruptResponse()
                        }
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.orange)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                    }
                }
            }

            // Error display
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
        .navigationTitle("Voice Assistant")
    }

    // Helper computed properties
    private var statusColor: Color {
        switch viewModel.sessionState {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .blue
        case .error: return .red
        }
    }

    private var statusText: String {
        switch viewModel.sessionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Thinking..."
        case .speaking: return "Speaking..."
        case .error: return "Error"
        }
    }
}
```

**❌ REMOVE from Sample App:**
```swift
// From VoiceAssistantViewModel.swift, REMOVE:
- var audioCapture: AudioCapture?
- var recordingTask: Task<Void, Error>?
- func startRecording()
- func stopRecording()
- func processRecording()
- private func processVoiceQuery(audio: Data) async

// From VoiceAssistantView.swift, REMOVE:
- Recording timer display
- Stop recording button
- Recording duration state
```

```

## 4. Components to Clean Up

### SDK Level - Remove Old Components
**✅ KEEP ALL** - The SDK components are well-designed and support streaming

### Sample App Level - Remove Batch Processing
**❌ REMOVE these methods from VoiceAssistantViewModel:**
```swift
// Remove batch recording methods:
func startRecording()
func stopRecording()
func processRecording()
private func processVoiceQuery(audio: Data)
```

**❌ REMOVE these UI elements from VoiceAssistantView:**
```swift
// Remove fixed duration recording UI:
- Recording timer display
- Stop recording button (replace with interrupt button)

## 5. Real-Time Implementation Details

### 5.1 Audio Streaming Pipeline (20ms chunks for real-time)
```swift
class AudioStreamManager {
    private let chunkDuration: TimeInterval = 0.02 // 20ms chunks
    private let sampleRate: Double = 16000
    private let samplesPerChunk = 320 // 16000 * 0.02

    func startInputStream() -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 512) { buffer, time in
                // Send 20ms chunks immediately
                continuation.yield(AudioChunk(buffer: buffer, timestamp: time))
            }
        }
    }
}
```

### 5.2 Real-Time STT (Process while user speaks)
```swift
class StreamingWhisperService {
    func transcribeStream(_ audio: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptChunk> {
        AsyncStream { continuation in
            var audioBuffer = Data()

            for await chunk in audio {
                audioBuffer.append(chunk.data)

                // Process every 200ms for partial results
                if audioBuffer.count >= 3200 { // 200ms of audio
                    let partial = whisper.transcribePartial(audioBuffer)
                    continuation.yield(TranscriptChunk(text: partial, isFinal: false))
                }
            }
        }
    }
}
```

### 5.3 Streaming LLM (Start speaking while thinking)
```swift
class StreamingLLMService {
    func generateStream(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            // Start generating immediately
            llm.generateTokens(prompt) { token in
                continuation.yield(token)

                // Start TTS on sentence boundaries
                if token.contains(".") || token.contains("!") || token.contains("?") {
                    startTTSForSentence(token)
                }
            }
        }
    }
}
```

## 6. Simple API Usage

```swift
// Developer using the SDK - LiveKit-style simplicity
class MyViewController: UIViewController, VoiceSessionDelegate {
    var session: VoiceSession?

    func startVoiceChat() {
        session = RunAnywhereSDK.shared.createVoiceSession()
        session?.delegate = self
        await session?.connect()
    }

    // Real-time callbacks
    func voiceSession(_ session: VoiceSession, didReceiveTranscript text: String, isFinal: Bool) {
        userTranscriptLabel.text = text
    }

    func voiceSession(_ session: VoiceSession, didReceiveResponse text: String) {
        aiResponseLabel.text = text
    }
}
```

## 7. Implementation Checklist

### Pre-Implementation Requirements
- [ ] Ensure WhisperKit pod is installed and working
- [ ] Verify audio permissions in Info.plist
- [ ] Test existing batch voice implementation works

### Phase 1: Audio Infrastructure ✅
- [ ] Add `startContinuousCapture()` to AudioCapture.swift
- [ ] Add `stopContinuousCapture()` method
- [ ] Add Data → Float conversion helper
- [ ] Test continuous audio streaming works

### Phase 2: STT Streaming ✅
- [ ] Implement `transcribeStream()` in WhisperKitService
- [ ] Add streaming properties to class
- [ ] Add simulated streaming for testing
- [ ] Test partial transcription works

### Phase 3: Voice Session API ✅
- [ ] Create VoiceSession.swift file
- [ ] Create VoiceSessionDelegate.swift file
- [ ] Add `createVoiceSession()` to RunAnywhereSDK
- [ ] Test session lifecycle works

### Phase 4: Sample App Integration ✅
- [ ] Remove batch processing from ViewModel
- [ ] Add VoiceSessionDelegate implementation
- [ ] Update UI for real-time feedback
- [ ] Add interrupt button
- [ ] Test end-to-end flow

### Post-Implementation Testing
- [ ] Test VAD integration
- [ ] Test interruption handling
- [ ] Test error recovery
- [ ] Measure latency improvements

## 8. Troubleshooting Guide

### Common Issues and Solutions

**Issue: Audio not capturing**
- Check microphone permissions
- Verify AVAudioSession configuration
- Ensure audio engine is started

**Issue: WhisperKit not transcribing**
- Check model is loaded
- Verify audio format (must be 16kHz)
- Check buffer size is sufficient

**Issue: No real-time updates**
- Verify AsyncStream is yielding
- Check delegate is set and retained
- Ensure main thread updates for UI

**Issue: High latency**
- Reduce audio buffer size
- Decrease STT chunk size
- Check model size (use smaller model)

## 9. Performance Metrics

| Component | Target Latency | How to Measure |
|-----------|---------------|----------------|
| Audio Capture | < 20ms | Time from speak to buffer |
| VAD Detection | < 10ms | Time to detect speech |
| STT Streaming | < 500ms | Time to first transcript |
| LLM First Token | < 200ms | Time from prompt to token |
| TTS First Audio | < 500ms | Time from text to audio |
| **End-to-End** | **< 1 second** | **User speaks to AI responds** |

## 10. Summary

This comprehensive implementation plan provides everything needed to transform the RunAnywhere SDK voice capabilities from batch processing to real-time streaming:

### ✅ What We're Keeping (90% of code)
- VoiceOrchestrator with streaming events
- All protocols and models
- Audio processing pipeline
- VAD implementation
- TTS integration

### 🔧 What We're Modifying (3 files)
1. **AudioCapture.swift** - Add continuous capture mode
2. **WhisperKitService.swift** - Implement streaming transcription
3. **RunAnywhereSDK.swift** - Add factory method

### ➕ What We're Adding (2 new files)
1. **VoiceSession.swift** - LiveKit-style API
2. **VoiceSessionDelegate.swift** - Event callbacks

### ❌ What We're Removing
- Batch recording methods in ViewModel
- Fixed duration UI elements

### 📊 Expected Results
- **10-18x faster** response time
- **Real-time** conversation capability
- **Natural** interruption handling
- **LiveKit-style** simple API

**Total Implementation Time: 8 hours**

The plan leverages the excellent existing architecture while adding minimal new code to achieve real-time voice interaction inspired by LiveKit's proven patterns.
