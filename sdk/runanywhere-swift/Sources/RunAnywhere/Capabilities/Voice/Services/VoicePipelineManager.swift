import Foundation
import os

// MARK: - Errors

/// Errors that can occur in the modular voice pipeline
public enum ModularPipelineError: Error {
    case notInitialized
    case componentNotAvailable(String)
    case processingFailed(String)
}

// MARK: - Component Types

public enum VoiceComponent: String, CaseIterable {
    case vad = "VAD"
    case stt = "STT"
    case llm = "LLM"
    case tts = "TTS"
}

// MARK: - Modular Voice Pipeline

/// A simplified, modular voice pipeline that can run any combination of components
public class VoicePipelineManager {
    private let logger = SDKLogger(category: "VoicePipelineManager")
    private let config: ModularPipelineConfig

    // Component instances (created based on config)
    private var vadComponent: VADService?
    private var sttService: VoiceService?
    private var llmService: LLMService?
    private var ttsService: TextToSpeechService?
    private var useGenerationService: Bool = false

    // Handlers for component processing
    private let vadHandler = VADHandler()
    private let sttHandler = STTHandler()
    private let llmHandler = LLMHandler()
    private let ttsHandler = TTSHandler()
    private let speakerDiarizationHandler = SpeakerDiarizationHandler()

    // Audio management
    private var isProcessing = false
    private var isInitialized = false
    private let transcriptionQueue = DispatchQueue(label: "com.runanywhere.transcription", qos: .userInitiated)

    // Audio segmentation strategy
    private var segmentationStrategy: AudioSegmentationStrategy

    // Streaming TTS handler
    private var streamingTTSHandler: StreamingTTSHandler?

    // Speaker diarization
    private var speakerDiarizationService: SpeakerDiarizationProtocol?
    private var enableSpeakerDiarization: Bool = false
    private var continuousMode: Bool = false
    private var sessionStartTime: Date?

    public weak var delegate: ModularVoicePipelineDelegate?

    public init(
        config: ModularPipelineConfig,
        vadService: VADService? = nil,
        voiceService: VoiceService? = nil,
        llmService: LLMService? = nil,
        ttsService: TextToSpeechService? = nil,
        speakerDiarization: SpeakerDiarizationProtocol? = nil,
        segmentationStrategy: AudioSegmentationStrategy? = nil
    ) {
        self.config = config

        // Use provided segmentation strategy or default
        self.segmentationStrategy = segmentationStrategy ?? DefaultAudioSegmentation()

        // Initialize only requested components
        if config.components.contains(.vad) {
            if let providedVAD = vadService {
                vadComponent = providedVAD
            } else if let vadConfig = config.vad {
                let vad = SimpleEnergyVAD(
                    sampleRate: 16000,
                    frameLength: 0.1,
                    energyThreshold: vadConfig.energyThreshold
                )
                vad.onSpeechActivity = { [weak self] event in
                    self?.logger.debug("VAD speech activity event: \(event)")
                    switch event {
                    case .started:
                        self?.isSpeechActive = true
                    case .ended:
                        self?.isSpeechActive = false
                    }
                }
                // Start the VAD immediately after creation
                vad.start()
                vadComponent = vad
            }
        }

        if config.components.contains(.stt) {
            sttService = voiceService
        }

        if config.components.contains(.llm) {
            if let llmService = llmService {
                self.llmService = llmService
            } else {
                // If no LLM service provided, we'll use GenerationService directly
                self.useGenerationService = true
            }
        }

        if config.components.contains(.tts) {
            self.ttsService = ttsService ?? SystemTextToSpeechService()
            // Initialize streaming TTS handler if we have TTS
            if let tts = self.ttsService {
                self.streamingTTSHandler = StreamingTTSHandler(ttsService: tts)
            }
        }

        // Use injected speaker diarization service if provided
        if let customDiarization = speakerDiarization {
            self.speakerDiarizationService = customDiarization
            logger.debug("Using custom speaker diarization service")
        }
    }

    // MARK: - Configuration

    /// Enable speaker diarization for transcription
    public func enableSpeakerDiarization(_ enable: Bool = true) {
        self.enableSpeakerDiarization = enable
        if enable && speakerDiarizationService == nil {
            // Create default implementation if none provided
            speakerDiarizationService = DefaultSpeakerDiarization()
            logger.info("Speaker diarization enabled with default implementation")
        } else if !enable {
            speakerDiarizationService = nil
            logger.info("Speaker diarization disabled")
        }
    }

    /// Enable continuous mode for real-time streaming transcription
    public func enableContinuousMode(_ enable: Bool = true) {
        self.continuousMode = enable
        logger.info("Continuous mode \(enable ? "enabled" : "disabled")")
    }

    /// Get all detected speakers
    public func getAllSpeakers() -> [SpeakerInfo] {
        return speakerDiarizationService?.getAllSpeakers() ?? []
    }

    /// Update speaker name
    public func updateSpeakerName(speakerId: String, name: String) {
        speakerDiarizationService?.updateSpeakerName(speakerId: speakerId, name: name)
    }

    /// Reset speaker diarization
    public func resetSpeakerDiarization() {
        speakerDiarizationService?.reset()
    }

    // MARK: - Initialization

    /// Initialize all configured components
    public func initializeComponents() -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var componentsToInit: [(String, () async throws -> Void)] = []

                // Build list of components to initialize
                if let vad = vadComponent, config.components.contains(.vad) {
                    componentsToInit.append(("VAD", { try await vad.initialize() }))
                }

                if let stt = sttService, config.components.contains(.stt) {
                    let modelPath = config.stt?.modelId
                    componentsToInit.append(("STT", { try await stt.initialize(modelPath: modelPath) }))
                }

                if config.components.contains(.llm) {
                    if let llm = llmService {
                        if llm.isReady {
                            // LLM service is already initialized, emit events immediately
                            logger.debug("LLM service already ready, skipping initialization")
                            continuation.yield(.componentInitialized("LLM"))
                        } else {
                            // Only try to initialize if we have a valid model path
                            // Don't try to initialize with "default" or empty string
                            if let modelId = config.llm?.modelId,
                               !modelId.isEmpty && modelId != "default" {
                                logger.debug("Initializing LLM with model: \(modelId)")
                                componentsToInit.append(("LLM", { try await llm.initialize(modelPath: modelId) }))
                            } else {
                                // No valid model path - skip initialization
                                // The service should already be initialized if it's from GenerationService
                                logger.debug("No valid model path for LLM initialization, assuming already initialized")
                                continuation.yield(.componentInitialized("LLM"))
                            }
                        }
                    } else if useGenerationService {
                        // Using generation service directly, no initialization needed
                        logger.debug("Using GenerationService directly, no LLM initialization needed")
                        continuation.yield(.componentInitialized("LLM"))
                    } else {
                        // No LLM service available but component requested
                        // This is OK - we'll fall back to GenerationService in processing
                        logger.debug("No LLM service available, will use GenerationService fallback")
                        continuation.yield(.componentInitialized("LLM"))
                    }
                }

                if let tts = ttsService, config.components.contains(.tts) {
                    componentsToInit.append(("TTS", { try await tts.initialize() }))
                }

                // Initialize each component
                for (componentName, initFunction) in componentsToInit {
                    continuation.yield(.componentInitializing(componentName))

                    do {
                        try await initFunction()
                        continuation.yield(.componentInitialized(componentName))
                    } catch {
                        continuation.yield(.componentInitializationFailed(componentName, error))
                        continuation.finish(throwing: error)
                        return
                    }
                }

                isInitialized = true
                continuation.yield(.allComponentsInitialized)
                continuation.finish()
            }
        }
    }

    // MARK: - Pipeline Execution

    /// Process audio through the configured pipeline components
    /// Returns a stream of pipeline events
    public func process(
        audioStream: AsyncStream<VoiceAudioChunk>
    ) -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Check if components are initialized
                    guard isInitialized else {
                        throw ModularPipelineError.notInitialized
                    }

                    continuation.yield(.pipelineStarted)

                    // Process audio through each component in sequence
                    for await audioChunk in audioStream {
                        try await processAudioChunk(audioChunk, continuation: continuation)
                    }

                    // Process any remaining buffered audio
                    if !floatBuffer.isEmpty {
                        try await finalizeProcessing(continuation: continuation)
                    }

                    continuation.yield(.pipelineCompleted)
                    continuation.finish()

                } catch {
                    continuation.yield(.pipelineError(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Component Processing

    private func processAudioChunk(
        _ chunk: VoiceAudioChunk,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {

        // Step 1: VAD (if enabled)
        if let vad = vadComponent, config.components.contains(.vad) {
            // Use VAD handler for processing
            if let floatsToProcess = vadHandler.processAudioChunk(
                chunk,
                vad: vad,
                segmentationStrategy: segmentationStrategy,
                continuation: continuation
            ) {
                // Process the buffered audio asynchronously
                Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        try await self.processBufferedAudioAsync(
                            floatSamples: floatsToProcess,
                            continuation: continuation
                        )
                    } catch {
                        self.logger.error("Async audio processing failed: \(error)")
                        continuation.yield(.pipelineError(error))
                    }
                }
            }
        } else {
            // No VAD, use handler for buffering
            if let floatsToProcess = vadHandler.processWithoutVAD(chunk) {
                // Process asynchronously using structured concurrency
                Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        try await self.processBufferedAudioAsync(
                            floatSamples: floatsToProcess,
                            continuation: continuation
                        )
                    } catch {
                        self.logger.error("Async audio processing failed: \(error)")
                        continuation.yield(.pipelineError(error))
                    }
                }
            }
        }
    }

    private func processBufferedAudioAsync(
        floatSamples: [Float],
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {
        guard !floatSamples.isEmpty else {
            return
        }

        var currentData: Any = floatSamples

        // Step 2: STT (if enabled)
        if let stt = sttService, config.components.contains(.stt), let sttConfig = config.stt {

            let options = VoiceTranscriptionOptions(
                language: VoiceTranscriptionOptions.Language(rawValue: sttConfig.language) ?? .english,
                enableSpeakerDiarization: enableSpeakerDiarization,
                continuousMode: continuousMode
            )

            // Check the service's preferred audio format
            let preferredFormat = stt.preferredAudioFormat
            // logger.debug("STT service prefers \(preferredFormat) format")

            do {
                let result: VoiceTranscriptionResult

                if preferredFormat == .floatArray {
                    // Service prefers Float arrays - pass directly
                    // logger.debug("Using Float array transcription with \(floatSamples.count) samples")
                    result = try await stt.transcribe(
                        samples: floatSamples,
                        options: options
                    )
                } else {
                    // Service prefers Data - convert Float array to Data
                    // logger.debug("Converting \(floatSamples.count) float samples to Data")
                    let audioData = floatSamples.withUnsafeBytes { bytes in
                        Data(bytes)
                    }
                    // logger.debug("Calling STT.transcribe with \(audioData.count) bytes")
                    result = try await stt.transcribe(
                        audio: audioData,
                        options: options
                    )
                }

                let transcript = result.text
                logger.info("STT transcription result: '\(transcript)'")

                if !transcript.isEmpty {
                    // Handle speaker diarization if enabled
                    if enableSpeakerDiarization, let diarizationService = speakerDiarizationService {
                        // Detect speaker from audio features
                        let speaker = diarizationService.detectSpeaker(
                            from: floatSamples,
                            sampleRate: 16000
                        )

                        // Check if speaker changed
                        let previousSpeaker = diarizationService.getCurrentSpeaker()
                        if previousSpeaker?.id != speaker.id {
                            continuation.yield(.sttSpeakerChanged(from: previousSpeaker, to: speaker))
                        }

                        // Emit transcript with speaker info
                        continuation.yield(.sttFinalTranscriptWithSpeaker(transcript, speaker))
                        logger.info("Transcript with speaker \(speaker.name ?? speaker.id): '\(transcript)'")
                    } else {
                        // Regular transcript without speaker info
                        continuation.yield(.sttFinalTranscript(transcript))
                    }
                    currentData = transcript
                } else {
                    logger.warning("STT returned empty transcript")
                }
            } catch {
                logger.error("STT transcription failed: \(error)")
                throw error
            }

            // If no LLM, stop here
            if !config.components.contains(.llm) {
                // logger.debug("No LLM component, stopping after STT")
                return
            }
        } else {
            // logger.debug("No STT service available or not configured")
        }

        // Rest of the processing can continue as before...
        // Step 3: LLM (if enabled)
        if config.components.contains(.llm), let transcript = currentData as? String {
            continuation.yield(.llmThinking)

            let options = RunAnywhereGenerationOptions(
                maxTokens: config.llm?.maxTokens ?? 100,
                temperature: config.llm?.temperature ?? 0.7,
                systemPrompt: config.llm?.systemPrompt
            )

            // Check if streaming is enabled (prefer streaming for voice pipelines)
            let useStreaming = config.llm?.useStreaming ?? true

            if useStreaming && llmService != nil && llmService!.isReady {
                // Use streaming for real-time responses
                logger.debug("Using streaming LLM service for real-time generation")

                // Reset streaming TTS handler for new response
                streamingTTSHandler?.reset()

                var fullResponse = ""
                var firstTokenReceived = false

                try await llmService!.streamGenerate(
                    prompt: transcript,
                    options: options,
                    onToken: { [weak self] token in
                        guard let self = self else { return }
                        if !firstTokenReceived {
                            firstTokenReceived = true
                            continuation.yield(.llmStreamStarted)
                        }
                        fullResponse += token
                        continuation.yield(.llmStreamToken(token))

                        // Process token for streaming TTS if enabled
                        if self.config.components.contains(.tts),
                           let handler = self.streamingTTSHandler {
                            Task {
                                await handler.processStreamingText(
                                    token,
                                    config: self.config.tts,
                                    continuation: continuation
                                )
                            }
                        }
                    }
                )

                // Flush any remaining text in TTS buffer
                if config.components.contains(.tts),
                   let handler = streamingTTSHandler {
                    let ttsOptions = createTTSOptions()
                    await handler.flushRemaining(options: ttsOptions, continuation: continuation)
                }

                continuation.yield(.llmFinalResponse(fullResponse))
                currentData = fullResponse

                // No need for additional TTS - streaming handler takes care of it
                return
            } else {
                // Fall back to non-streaming generation
                let response: String
                if let llm = llmService, llm.isReady {
                    // Use the provided LLM service if it's ready
                    logger.debug("Using initialized LLM service for generation")
                    response = try await llm.generate(
                        prompt: transcript,
                        options: options
                    )
                } else if useGenerationService || llmService == nil {
                    // Use the SDK's generation service directly
                    logger.debug("Using GenerationService directly for LLM processing")
                    let generationService = RunAnywhereSDK.shared.serviceContainer.generationService
                    let result = try await generationService.generate(
                        prompt: transcript,
                        options: options
                    )
                    response = result.text
                } else {
                    // LLM service exists but not ready - this shouldn't happen after initialization
                    logger.error("LLM service exists but is not ready after initialization")
                    throw LLMServiceError.notInitialized
                }

                continuation.yield(.llmFinalResponse(response))
                currentData = response

                // If no TTS, stop here
                if !config.components.contains(.tts) {
                    return
                }
            }
        }

        // Step 4: TTS (if enabled)
        if let text = currentData as? String {
            try await performTTS(text: text, continuation: continuation)
        }
    }

    private func processBufferedAudio(
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {
        guard !floatBuffer.isEmpty else {
            // logger.debug("processBufferedAudio called with empty buffer, skipping")
            return
        }

        // logger.debug("processBufferedAudio starting with \(floatBuffer.count) float samples")

        // Use the float-based method for consistency
        try await processBufferedAudioAsync(
            floatSamples: floatBuffer,
            continuation: continuation
        )

        // Clear buffers after processing
        floatBuffer = []
    }

    private func finalizeProcessing(
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {
        try await processBufferedAudio(continuation: continuation)
    }

    // MARK: - TTS Helper Methods

    /// Create TTS options from configuration
    private func createTTSOptions() -> TTSOptions {
        return TTSOptions(
            voice: config.tts?.voice,
            language: "en",
            rate: config.tts?.rate ?? 1.0,
            pitch: config.tts?.pitch ?? 1.0,
            volume: config.tts?.volume ?? 1.0
        )
    }

    /// Perform TTS for given text
    private func performTTS(
        text: String,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {
        guard let tts = ttsService, config.components.contains(.tts) else {
            return
        }

        continuation.yield(.ttsStarted)
        let ttsOptions = createTTSOptions()
        try await tts.speak(text: text, options: ttsOptions)
        continuation.yield(.ttsCompleted)
    }


    // MARK: - Component Factory Methods

    /// Create a VAD service based on configuration
    public static func createVADService(config: VADConfig) -> VADService {
        return SimpleEnergyVAD(
            sampleRate: 16000,
            frameLength: 0.1,
            energyThreshold: config.energyThreshold
        )
    }

}

// MARK: - Pipeline Delegate

public protocol ModularVoicePipelineDelegate: AnyObject {
    func pipeline(_ pipeline: ModularVoicePipeline, didReceiveEvent event: ModularPipelineEvent)
    func pipeline(_ pipeline: ModularVoicePipeline, didEncounterError error: Error)
}

// MARK: - SDK Extension
// Note: The public API extensions have been moved to RunAnywhereSDK+Voice.swift
// to properly delegate to VoiceCapabilityService for better separation of concerns
