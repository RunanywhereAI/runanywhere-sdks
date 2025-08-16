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

    // STT readiness state
    private var isSTTReady: Bool = false

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
            // Pre-initialize STT service to ensure it's ready before starting VAD
            logger.info("🚀 Pre-initializing STT service...")
            try await preInitializeSTTService()
            logger.info("✅ STT service pre-initialized and ready")

            // Initialize VAD if enabled
            if config.enableVAD {
                logger.info("Initializing VAD with medium sensitivity")
                vadProcessor = SimpleVAD(sensitivity: .medium)
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
        isSTTReady = false
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

            self.logger.info("Pipeline started, VAD enabled: \(self.config.enableVAD)")

            // Process through VAD if enabled
            let processedStream: AsyncStream<VoiceAudioChunk>
            if let vad = self.vadProcessor {
                self.logger.info("Applying VAD with threshold: \(vad.energyThreshold)")
                processedStream = self.applyVAD(to: audioStream, using: vad)
            } else {
                processedStream = audioStream
            }

            // Accumulate audio chunks for batch processing - SIMPLIFIED PIPELINE
            var audioSamples: [Float] = []
            let processingInterval: TimeInterval = 1.5 // Process every 1.5 seconds
            var lastProcessTime = Date()
            var chunkCount = 0
            let minSampleCount = 48000 // Minimum 3 seconds at 16kHz - WhisperKit needs longer audio for better transcription

            for await chunk in processedStream {
                audioSamples.append(contentsOf: chunk.samples)
                chunkCount += 1

                // Enhanced debug logging for audio flow
                if chunkCount % 10 == 0 {
                    let chunkSampleCount = chunk.samples.count
                    let chunkDuration = Float(chunkSampleCount) / 16000.0
                    let bufferDuration = Float(audioSamples.count) / 16000.0
                    self.logger.debug("📊 Audio Flow Debug:")
                    self.logger.debug("  Chunk #\(chunkCount): \(chunkSampleCount) samples = \(String(format: "%.3f", chunkDuration))s")
                    self.logger.debug("  Buffer: \(audioSamples.count) samples = \(String(format: "%.3f", bufferDuration))s")
                    self.logger.debug("  Chunk duration property: \(String(format: "%.3f", chunk.duration))s")
                }

                // Process when we have enough audio or timeout - SIMPLIFIED
                let timeSinceLastProcess = Date().timeIntervalSince(lastProcessTime)
                let hasEnoughAudio = audioSamples.count >= minSampleCount
                let timeoutReached = timeSinceLastProcess >= processingInterval

                // Check if buffer has actual audio content (not just silence)
                let hasAudioContent = self.checkForAudioContent(samples: audioSamples)

                if (hasEnoughAudio || (timeoutReached && audioSamples.count > 16000)) && !audioSamples.isEmpty && hasAudioContent {
                    // Check if STT service is ready before processing
                    guard self.isSTTReady else {
                        self.logger.info("⏳ STT service not ready yet, skipping audio processing")
                        continue
                    }

                    let bufferDuration = Float(audioSamples.count) / 16000.0
                    self.logger.info("🎯 Triggering processing:")
                    self.logger.info("  Buffer: \(audioSamples.count) samples = \(String(format: "%.3f", bufferDuration))s")
                    self.logger.info("  Time since last: \(String(format: "%.3f", timeSinceLastProcess))s")
                    self.logger.info("  Reason: \(hasEnoughAudio ? "enough audio (>=2s)" : "timeout reached")")
                    await self.processPipelineWithSamples(audioSamples)
                    audioSamples = []
                    lastProcessTime = Date()
                    chunkCount = 0
                } else if timeoutReached && !hasAudioContent {
                    // Clear buffer if it's just silence after timeout
                    self.logger.debug("Clearing silent buffer after timeout")
                    audioSamples = []
                    lastProcessTime = Date()
                    chunkCount = 0
                }
            }

            // Process any remaining audio
            if !audioSamples.isEmpty {
                await self.processPipelineWithSamples(audioSamples)
            }
        }
    }

    private func processPipelineWithSamples(_ samples: [Float]) async {
        logger.info("🎤 Processing pipeline with audio: \(samples.count) samples")

        // Convert to Data for legacy VoiceOrchestrator interface
        let audioData = Data(bytes: samples, count: samples.count * MemoryLayout<Float>.size)

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

        logger.info("📝 Starting pipeline with config - STT: \(pipelineConfig.sttModelId ?? "none"), LLM: \(pipelineConfig.llmModelId ?? "none")")

        // Process through orchestrator
        do {
            var eventCount = 0
            for try await event in self.voiceOrchestrator.processVoicePipeline(
                audio: audioData,
                config: pipelineConfig
            ) {
                eventCount += 1
                // Only log important events, not progress events
                switch event {
                case .transcriptionCompleted(let result):
                    logger.info("✅ Transcription completed: '\(result.text)'")
                case .llmGenerationCompleted(let text):
                    logger.info("✅ LLM generation completed: '\(text)'")
                case .error(let stage, let error):
                    logger.error("❌ Pipeline error at \(stage.rawValue): \(error)")
                default:
                    break // Skip logging progress events
                }
                self.handlePipelineEvent(event)
            }
            logger.info("✅ Pipeline completed with \(eventCount) events")
        } catch {
            self.logger.error("❌ Pipeline error: \(error)")
            self.updateState(.error(error.localizedDescription))
            self.delegate?.voiceSession(self, didEncounterError: error)
        }
    }

    private func applyVAD(to stream: AsyncStream<VoiceAudioChunk>, using vad: VoiceActivityDetector) -> AsyncStream<VoiceAudioChunk> {
        AsyncStream { continuation in
            Task {
                var speechChunkCount = 0
                var silenceChunkCount = 0
                var totalChunkCount = 0

                for await chunk in stream {
                    totalChunkCount += 1

                    // Only yield chunks with speech - SIMPLIFIED
                    let hasSpeech = vad.detectActivity(chunk.data)
                    let result = vad.detectActivity(in: chunk.data) // For energy logging
                    if hasSpeech {
                        speechChunkCount += 1
                        continuation.yield(chunk)
                        let sampleCount = chunk.samples.count
                        let duration = Float(sampleCount) / 16000.0
                        self.logger.info("🎤 VAD: Speech detected in chunk #\(totalChunkCount)")
                        self.logger.info("  Energy: \(String(format: "%.4f", result.energyLevel)), Threshold: \(String(format: "%.4f", vad.energyThreshold))")
                        self.logger.info("  Chunk: \(chunk.samples.count) samples = \(String(format: "%.3f", duration))s")
                    } else {
                        silenceChunkCount += 1
                        // Log every 20th silence chunk to see energy levels
                        if silenceChunkCount % 20 == 0 {
                            self.logger.info("🔇 VAD: Silence #\(silenceChunkCount) (energy: \(String(format: "%.6f", result.energyLevel)), threshold: \(String(format: "%.6f", vad.energyThreshold)))")
                        }
                    }

                    // Log VAD stats periodically
                    if totalChunkCount % 100 == 0 {
                        self.logger.info("VAD stats - Total: \(totalChunkCount), Speech: \(speechChunkCount), Silence: \(silenceChunkCount)")
                    }
                }
                self.logger.info("VAD stream finished - Total chunks: \(totalChunkCount), Speech: \(speechChunkCount), Silence: \(silenceChunkCount)")
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

    /// Check if audio buffer contains actual content (not just silence) - SIMPLIFIED
    private func checkForAudioContent(samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }

        // Calculate RMS energy (similar to VAD)
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        // Also check maximum amplitude for additional validation
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0

        // Use a more conservative threshold that matches our VAD settings
        let rmsThreshold: Float = 0.005  // Lower threshold to match VAD sensitivity
        let maxThreshold: Float = 0.01   // Lower max amplitude threshold

        // Use OR condition instead of AND - either high RMS OR high amplitude indicates speech
        let hasContent = rms > rmsThreshold || maxAmplitude > maxThreshold

        if !hasContent {
            logger.debug("Audio buffer appears silent (RMS: \(String(format: "%.6f", rms)), Max: \(String(format: "%.6f", maxAmplitude)))")
        } else {
            logger.debug("Audio buffer has content (RMS: \(String(format: "%.6f", rms)), Max: \(String(format: "%.6f", maxAmplitude)))")
        }

        return hasContent
    }

    // Legacy method for backward compatibility
    private func processPipelineWithAudio(_ audioData: Data) async {
        let samples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        await processPipelineWithSamples(samples)
    }

    /// Pre-initialize the STT service to ensure it's ready before audio processing starts
    private func preInitializeSTTService() async throws {
        logger.info("🔧 Pre-initializing STT service for model: \(self.config.recognitionModel)")

        do {
            // Create pipeline config for STT initialization
            let pipelineConfig = VoicePipelineConfig(
                sttModelId: self.config.recognitionModel,
                llmModelId: self.config.llmModel,
                ttsEnabled: false, // Don't initialize TTS during pre-init
                ttsVoice: nil,
                streamingEnabled: false, // Don't need streaming for init
                timeouts: VoicePipelineConfig.PipelineTimeouts(
                    transcription: 30,
                    llmGeneration: 60,
                    textToSpeech: 30
                ),
                generationOptions: GenerationOptions(
                    maxTokens: 1,
                    temperature: 0.7
                )
            )

            // Create a small dummy audio buffer for initialization
            let dummyAudioSize = 1600 // 0.1 seconds at 16kHz
            let dummyAudio = Data(count: dummyAudioSize * 4) // Float32 PCM

            logger.info("🔧 Initializing STT service with dummy audio...")

            // Initialize the STT service by attempting a transcription
            // This will trigger the WhisperKit initialization
            let initStartTime = Date()

            var initializationComplete = false
            for try await event in self.voiceOrchestrator.processVoicePipeline(
                audio: dummyAudio,
                config: pipelineConfig
            ) {
                switch event {
                case .transcriptionStarted:
                    logger.info("🔧 STT service initialization started")
                case .transcriptionCompleted:
                    let initTime = Date().timeIntervalSince(initStartTime)
                    logger.info("🔧 STT service initialization completed in \(String(format: "%.2f", initTime))s")
                    initializationComplete = true
                    self.isSTTReady = true
                    // Break out early since we only need initialization
                    break
                case .error(let stage, let error):
                    logger.error("🔧 STT initialization failed at \(stage.rawValue): \(error)")
                    throw error
                default:
                    // Ignore other events during initialization
                    break
                }
            }

            if !initializationComplete {
                logger.warning("🔧 STT initialization may not be complete")
            }

        } catch {
            logger.error("🔧 Failed to pre-initialize STT service: \(error)")
            throw VoiceSessionError.audioInitializationFailed
        }
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
