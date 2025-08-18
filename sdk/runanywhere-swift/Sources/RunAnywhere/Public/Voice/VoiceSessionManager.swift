import Foundation
import AVFoundation
import os

/// Thread-safe actor for managing audio buffer
private actor AudioBufferActor {
    private var buffer: [Float] = []

    func append(contentsOf samples: [Float]) {
        buffer.append(contentsOf: samples)
    }

    func clear() {
        buffer = []
    }

    func getAndClear() -> [Float] {
        let current = buffer
        buffer = []
        return current
    }

    func count() -> Int {
        return buffer.count
    }

    func isEmpty() -> Bool {
        return buffer.isEmpty
    }
}

/// Simplified Voice Session Manager with WebRTC VAD
public class VoiceSessionManager {
    // MARK: - Properties

    public let id = UUID().uuidString
    public private(set) var state: SessionState = .disconnected
    public weak var delegate: VoiceSessionDelegate?

    private let voiceOrchestrator: VoiceOrchestrator
    private var audioCaptureProvider: (() -> AsyncStream<VoiceAudioChunk>)?
    private var stopAudioCapture: (() -> Void)?
    private var streamTask: Task<Void, Never>?
    private var vadDetector: SimpleEnergyVAD?
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "VoiceSessionManager")
    private var ttsService: TextToSpeechService?

    // Configuration
    private let config: VoiceSessionConfig

    // Audio buffer for accumulating speech - protected by actor for thread safety
    private let audioBufferActor = AudioBufferActor()
    private let minSpeechDuration: TimeInterval = 2.0 // Minimum 2 seconds of speech

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

    /// Connect and start voice session
    public func connect() async throws {
        guard state == .disconnected else {
            throw VoiceSessionError.invalidState("Already connected")
        }

        updateState(.connecting)

        // Initialize TTS service with proper priority
        await Task(priority: .userInitiated) {
            ttsService = SystemTextToSpeechService()
            try? await ttsService?.initialize()
        }.value

        // Pre-initialize WhisperKit for faster first transcription
        logger.info("Pre-initializing speech recognition model: \(self.config.recognitionModel)")
        do {
            // Trigger initialization through the orchestrator
            let testConfig = VoicePipelineConfig(
                sttModelId: self.config.recognitionModel,
                llmModelId: self.config.llmModel,
                ttsEnabled: false,
                streamingEnabled: false
            )
            // Pre-warm the voice service
            _ = try? await voiceOrchestrator.processVoiceQuery(
                audio: Data(repeating: 0, count: 16000), // 1 second of silence
                config: testConfig
            )
            logger.info("Speech recognition model pre-initialized successfully")
        } catch {
            logger.warning("Failed to pre-initialize speech model: \(error)")
            // Continue anyway - it will initialize on first use
        }

        // Initialize Simple Energy VAD if enabled
        if config.enableVAD {
            await Task(priority: .userInitiated) {
                vadDetector = SimpleEnergyVAD(
                    sampleRate: 16000,
                    frameLength: 0.1,
                    energyThreshold: 0.01  // Lowered from 0.025 for better sensitivity
                )
                setupVADCallbacks()
                vadDetector?.start()
                logger.info("Simple Energy VAD initialized with threshold: 0.01")
            }.value
        }

        // Get audio stream
        guard let audioStream = audioCaptureProvider?() else {
            throw VoiceSessionError.audioInitializationFailed
        }

        updateState(.connected)

        // Start processing pipeline
        await startProcessingPipeline(audioStream: audioStream)
    }

    /// Disconnect session
    public func disconnect() async {
        // Stop TTS if playing
        await Task(priority: .userInitiated) {
            ttsService?.stop()
        }.value

        streamTask?.cancel()
        stopAudioCapture?()
        // Stop and clear all resources with proper priority
        await Task(priority: .userInitiated) {
            vadDetector?.stop()
            vadDetector = nil
            ttsService = nil
        }.value
        
        updateState(.disconnected)
        logger.info("Session disconnected")
    }

    /// Start listening for speech
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

        // Stop TTS immediately with proper priority
        await Task(priority: .userInitiated) {
            ttsService?.stop()
        }.value

        // Cancel ongoing stream task
        streamTask?.cancel()

        if let audioStream = audioCaptureProvider?() {
            await startProcessingPipeline(audioStream: audioStream)
        }
    }

    // MARK: - Private Methods

    private func setupVADCallbacks() {
        vadDetector?.onSpeechActivity = { [weak self] event in
            guard let self = self else { return }

            switch event {
            case .started:
                self.logger.info("🎤 Speech started")
                self.updateState(.listening)
                Task(priority: .userInitiated) {
                    await self.audioBufferActor.clear() // Clear buffer for new speech
                }

            case .ended:
                self.logger.info("🔇 Speech ended")
                // Process accumulated speech buffer
                Task(priority: .userInitiated) {
                    let isEmpty = await self.audioBufferActor.isEmpty()
                    if !isEmpty {
                        await self.processSpeechBuffer()
                    }
                }
            }
        }

        // Note: SimpleEnergyVAD doesn't provide audio data directly
        // Audio processing happens in the main pipeline
        vadDetector?.onAudioBuffer = { [weak self] audioData in
            // Optional: Additional audio processing can be done here
            guard let self = self else { return }
            self.logger.debug("VAD received audio buffer: \(audioData.count) bytes")
        }
    }

    private func startProcessingPipeline(audioStream: AsyncStream<VoiceAudioChunk>) async {
        streamTask = Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            self.logger.info("Starting audio processing pipeline")
            var chunkCount = 0

            for await chunk in audioStream {
                chunkCount += 1

                // Log every 10th chunk to avoid spam (every second at 100ms chunks)
                if chunkCount % 10 == 0 {
                    let maxAmplitude = chunk.samples.map { abs($0) }.max() ?? 0
                    let rms = sqrt(chunk.samples.reduce(0) { $0 + $1 * $1 } / Float(chunk.samples.count))
                    self.logger.debug("Audio chunk #\(chunkCount): \(chunk.samples.count) samples, RMS: \(String(format: "%.4f", rms)), Max: \(String(format: "%.4f", maxAmplitude))")
                }

                // If VAD is enabled, feed audio to VAD for analysis
                if self.config.enableVAD {
                    // Process audio through VAD
                    self.vadDetector?.processAudioData(chunk.samples)

                    // Only accumulate audio when we're actively listening (after speech started)
                    if self.state == .listening {
                        await self.audioBufferActor.append(contentsOf: chunk.samples)
                        let bufferCount = await self.audioBufferActor.count()
                        if bufferCount % 16000 == 0 { // Log every second of buffered audio
                            self.logger.debug("Speech buffer: \(bufferCount) samples (\(bufferCount/16000)s)")
                        }
                    }
                } else {
                    // No VAD - accumulate audio and process periodically
                    await self.audioBufferActor.append(contentsOf: chunk.samples)

                    let bufferCount = await self.audioBufferActor.count()
                    let bufferDuration = TimeInterval(bufferCount) / 16000.0
                    if bufferDuration >= self.minSpeechDuration {
                        await self.processSpeechBuffer()
                    }
                }
            }

            // Process any remaining audio
            let isEmpty = await self.audioBufferActor.isEmpty()
            if !isEmpty {
                await self.processSpeechBuffer()
            }
        }
    }

    private func processSpeechBuffer() async {
        let speechBuffer = await audioBufferActor.getAndClear()
        guard !speechBuffer.isEmpty else { return }

        let sampleCount = speechBuffer.count
        let duration = Float(sampleCount) / 16000.0

        // Skip very short segments (less than 0.5 seconds) to avoid WhisperKit issues
        if duration < 0.5 {
            logger.warning("Skipping short audio segment: \(String(format: "%.2f", duration))s (\(sampleCount) samples)")
            updateState(.connected)
            return
        }

        logger.info("Processing speech buffer: \(sampleCount) samples (\(String(format: "%.2f", duration))s)")

        // Convert to Data for orchestrator
        let audioData = Data(bytes: speechBuffer, count: sampleCount * MemoryLayout<Float>.size)

        // Create pipeline config
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
           generationOptions: RunAnywhereGenerationOptions(
                maxTokens: 500,
                temperature: 0.7
            )
        )

        // Process through orchestrator
        updateState(.processing)

        do {
            for try await event in voiceOrchestrator.processVoicePipeline(
                audio: audioData,
                config: pipelineConfig
            ) {
                handlePipelineEvent(event)
            }
        } catch {
            logger.error("Pipeline error: \(error)")
            updateState(.error(error.localizedDescription))
            delegate?.voiceSession(self, didEncounterError: error)
        }

        updateState(.connected)
    }

    private func handlePipelineEvent(_ event: VoicePipelineEvent) {
        switch event {
        case .transcriptionStarted:
            updateState(.processing)

        case .transcriptionProgress(let text, _):
            delegate?.voiceSession(self, didReceiveTranscript: text, isFinal: false)

        case .transcriptionCompleted(let result):
            delegate?.voiceSession(self, didReceiveTranscript: result.text, isFinal: true)

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

        case .error(let stage, let error):
            logger.error("Pipeline error at \(stage.rawValue): \(error)")
            delegate?.voiceSession(self, didEncounterError: error)

        default:
            break // Ignore other events for simplicity
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
