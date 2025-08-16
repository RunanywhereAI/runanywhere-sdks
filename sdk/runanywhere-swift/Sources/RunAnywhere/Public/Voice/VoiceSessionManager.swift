import Foundation
import AVFoundation
import os

/// LiveKit-style Voice Session Manager for real-time conversation
public class VoiceSessionManager {
    // MARK: - Properties
    public let id: String = UUID().uuidString
    public private(set) var state: SessionState = .disconnected
    public weak var delegate: VoiceSessionDelegate?

    private let voiceOrchestrator: VoiceOrchestrator
    private var audioCaptureProvider: (() -> AsyncStream<VoiceAudioChunk>)?
    private var stopAudioCapture: (() -> Void)?
    private var streamTask: Task<Void, Never>?
    private var vadProcessor: VoiceActivityDetector?
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "VoiceSessionManager")

    // Configuration
    private let config: VoiceSessionConfig

    // MARK: - Session States
    public enum SessionState: Equatable {
        case disconnected
        case connecting
        case connected
        case listening
        case processing
        case speaking
        case error(String)

        public static func == (lhs: SessionState, rhs: SessionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.listening, .listening),
                 (.processing, .processing),
                 (.speaking, .speaking):
                return true
            case (.error(let lhs), .error(let rhs)):
                return lhs == rhs
            default:
                return false
            }
        }
    }

    // MARK: - Initialization
    public init(
        voiceOrchestrator: VoiceOrchestrator,
        config: VoiceSessionConfig = VoiceSessionConfig(),
        audioCaptureProvider: (() -> AsyncStream<VoiceAudioChunk>)? = nil,
        stopAudioCapture: (() -> Void)? = nil
    ) {
        self.voiceOrchestrator = voiceOrchestrator
        self.config = config
        self.audioCaptureProvider = audioCaptureProvider
        self.stopAudioCapture = stopAudioCapture
    }

    // MARK: - Public Methods

    /// Connect the voice session and start audio pipeline
    public func connect() async throws {
        guard state == .disconnected else {
            throw VoiceSessionError.invalidState("Already connected")
        }

        updateState(.connecting)

        do {
            // Initialize VAD if enabled
            if config.enableVAD {
                vadProcessor = SimpleVAD(sensitivity: .medium)  // Default sensitivity
            }

            // Get audio stream from provider if available
            guard let audioStream = audioCaptureProvider?() else {
                // If no audio provider, create a mock stream for testing
                logger.warning("No audio capture provider, using mock stream")
                let mockStream = AsyncStream<VoiceAudioChunk> { continuation in
                    // Mock implementation - just finish immediately
                    continuation.finish()
                }
                updateState(.connected)
                await startPipeline(audioStream: mockStream)
                return
            }

            updateState(.connected)

            // Start processing pipeline
            await startPipeline(audioStream: audioStream)

        } catch {
            updateState(.error(error.localizedDescription))
            throw error
        }
    }

    /// Disconnect the session and cleanup
    public func disconnect() async {
        streamTask?.cancel()
        stopAudioCapture?()
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

        if let audioStream = audioCaptureProvider?() {
            await startPipeline(audioStream: audioStream)
        }
    }

    // MARK: - Private Methods

    private func startPipeline(audioStream: AsyncStream<VoiceAudioChunk>) async {
        streamTask = Task { [weak self] in
            guard let self = self else { return }

            // Process through VAD if enabled
            let processedStream: AsyncStream<VoiceAudioChunk>
            if let vad = self.vadProcessor {
                processedStream = self.applyVAD(to: audioStream, using: vad)
            } else {
                processedStream = audioStream
            }

            // Accumulate audio chunks for batch processing
            // Since VoiceOrchestrator currently expects Data, not streams
            var audioBuffer = Data()
            let processingInterval: TimeInterval = 2.0 // Process every 2 seconds
            var lastProcessTime = Date()

            for await chunk in processedStream {
                audioBuffer.append(chunk.data)

                // Process when we have enough audio or timeout
                let timeSinceLastProcess = Date().timeIntervalSince(lastProcessTime)
                if timeSinceLastProcess >= processingInterval && !audioBuffer.isEmpty {
                    await self.processPipelineWithAudio(audioBuffer)
                    audioBuffer = Data()
                    lastProcessTime = Date()
                }
            }

            // Process any remaining audio
            if !audioBuffer.isEmpty {
                await self.processPipelineWithAudio(audioBuffer)
            }
        }
    }

    private func processPipelineWithAudio(_ audioData: Data) async {
        // Configure pipeline
        let pipelineConfig = VoicePipelineConfig(
            sttModelId: config.recognitionModel,
            llmModelId: config.llmModel,
            ttsEnabled: config.ttsModel != nil,
            ttsVoice: nil,
            streamingEnabled: config.enableStreaming,
            timeouts: VoicePipelineConfig.PipelineTimeouts(
                transcription: 30,
                llmGeneration: 60,
                textToSpeech: 30
            ),
            generationOptions: GenerationOptions(
                maxTokens: 500,
                temperature: 0.7
            )
        )

        // Process through orchestrator
        do {
            for try await event in self.voiceOrchestrator.processVoicePipeline(
                audio: audioData,
                config: pipelineConfig
            ) {
                self.handlePipelineEvent(event)
            }
        } catch {
            self.logger.error("Pipeline error: \(error)")
            self.updateState(.error(error.localizedDescription))
            self.delegate?.voiceSession(self, didEncounterError: error)
        }
    }

    private func applyVAD(to stream: AsyncStream<VoiceAudioChunk>, using vad: VoiceActivityDetector) -> AsyncStream<VoiceAudioChunk> {
        AsyncStream { continuation in
            Task {
                for await chunk in stream {
                    // Only yield chunks with speech
                    let result = vad.detectActivity(in: chunk.data)
                    if result.hasSpeech {
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

        case .transcriptionProgress(let text, _):
            delegate?.voiceSession(self, didReceiveTranscript: text, isFinal: false)

        case .transcriptionCompleted(let result):
            delegate?.voiceSession(self, didReceiveTranscript: result.text, isFinal: true)
            updateState(.processing)

        case .llmGenerationStarted:
            updateState(.processing)

        case .llmGenerationProgress(let text, _):
            delegate?.voiceSession(self, didReceiveResponse: text)

        case .llmGenerationCompleted(let text):
            delegate?.voiceSession(self, didReceiveResponse: text)

        case .ttsStarted:
            updateState(.speaking)

        case .ttsProgress(let audioChunk, _):
            delegate?.voiceSession(self, didReceiveAudio: audioChunk)

        case .ttsCompleted:
            updateState(.connected)

        case .completed(let result):
            logger.info("Pipeline completed in \(result.processingTime)s")
            updateState(.connected)

        case .error(let stage, let error):
            logger.error("Pipeline error at \(stage.rawValue): \(error)")
            delegate?.voiceSession(self, didEncounterError: error)
        }
    }

    private func updateState(_ newState: SessionState) {
        state = newState
        delegate?.voiceSession(self, didChangeState: newState)
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

// MARK: - AudioCapture placeholder
// Note: In production, AudioCapture should be moved to the SDK
// For now, we'll use a protocol-based approach
