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
public class ModularVoicePipeline {
    private let logger = SDKLogger(category: "ModularVoicePipeline")
    private let config: ModularPipelineConfig

    // Component instances (created based on config)
    private var vadComponent: VADService?
    private var sttService: VoiceService?
    private var llmService: LLMService?
    private var ttsService: TextToSpeechService?
    private var useGenerationService: Bool = false

    // Audio management
    private var floatBuffer: [Float] = []  // Buffer for Float samples
    private var isProcessing = false
    private var isSpeechActive = false
    private var isInitialized = false
    private var speechStartTime: Date?
    private let minSpeechDuration: TimeInterval = 1.0 // Minimum 1.0 seconds of speech for better transcription
    private let transcriptionQueue = DispatchQueue(label: "com.runanywhere.transcription", qos: .userInitiated)

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
        speakerDiarization: SpeakerDiarizationProtocol? = nil
    ) {
        self.config = config

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

        // Get float samples from chunk - needed for both VAD and non-VAD paths
        let floatArray = chunk.samples

        // Step 1: VAD (if enabled)
        if let vad = vadComponent, config.components.contains(.vad) {

            // Process audio through VAD and check result
            let hasVoice = vad.processAudioData(floatArray)

            // Debug logging - commented out to reduce noise
            // if floatArray.count > 0 {
            //     let energy = floatArray.map { $0 * $0 }.reduce(0, +) / Float(floatArray.count)
            //     let rms = sqrt(energy)
            //     logger.debug("Processing \(floatArray.count) samples, RMS: \(rms), hasVoice: \(hasVoice), isSpeechActive: \(isSpeechActive)")
            // }

            // Handle speech state transitions
            let wasSpeaking = isSpeechActive

            // Check if speech state changed
            if hasVoice && !wasSpeaking {
                // Speech just started
                isSpeechActive = true
                speechStartTime = Date()
                floatBuffer = []  // Clear float buffer
                continuation.yield(.vadSpeechStart)
                logger.info("Speech started, beginning to buffer audio")
            }

            // Always buffer audio when speech is active
            if isSpeechActive {
                // Buffer float samples directly (no need for Data conversion)
                floatBuffer.append(contentsOf: floatArray)  // Use the float samples directly
                // logger.debug("Buffering audio, total samples: \(floatBuffer.count)")
            }

            // Check if speech ended - but ensure minimum duration
            if !hasVoice && wasSpeaking {
                let speechDuration = Date().timeIntervalSince(speechStartTime ?? Date())

                // Only process if we have enough speech
                if speechDuration >= minSpeechDuration && !floatBuffer.isEmpty {
                    // Speech ended with sufficient duration
                    isSpeechActive = false
                    continuation.yield(.vadSpeechEnd)
                    logger.info("Speech ended after \(speechDuration)s, processing \(floatBuffer.count) samples")

                    // Process the buffered audio asynchronously
                    let floatsToProcess = floatBuffer
                    floatBuffer = []

                    // Non-blocking transcription using structured concurrency
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
                } else if speechDuration < minSpeechDuration {
                    // Speech was too short, keep buffering
                    // logger.debug("Speech too short (\(speechDuration)s), continuing to buffer")
                }
            }
        } else {
            // No VAD, buffer all audio
            floatBuffer.append(contentsOf: floatArray)

            // Process periodically
            if floatBuffer.count > 32000 { // ~2 seconds at 16kHz
                // logger.debug("No VAD, processing \(floatBuffer.count) samples periodically")

                let floatsToProcess = floatBuffer
                floatBuffer = []

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
            // logger.debug("processBufferedAudioAsync called with empty samples, skipping")
            return
        }

        // logger.debug("processBufferedAudioAsync starting with \(floatSamples.count) float samples")

        var currentData: Any = floatSamples

        // Step 2: STT (if enabled)
        if let stt = sttService, config.components.contains(.stt), let sttConfig = config.stt {
            // logger.debug("STT service found, preparing to transcribe")

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

extension RunAnywhereSDK {
    /// Create a modular voice pipeline with the specified configuration
    /// This is the single API for all voice processing needs
    public func createVoicePipeline(
        config: ModularPipelineConfig,
        speakerDiarization: SpeakerDiarizationProtocol? = nil
    ) -> ModularVoicePipeline {
        var llmService: LLMService? = nil

        // Only try to find an LLM service if LLM component is requested
        if config.components.contains(.llm) {
            // Try to find an LLM service, but don't fail if none found
            // The pipeline will fall back to using GenerationService directly
            llmService = findLLMService(for: config.llm?.modelId)
        }

        return ModularVoicePipeline(
            config: config,
            vadService: nil, // Will use default SimpleEnergyVAD
            voiceService: findVoiceService(for: config.stt?.modelId ?? "whisper-base"),
            llmService: llmService,
            ttsService: findTTSService(),
            speakerDiarization: speakerDiarization
        )
    }

    /// Process audio with a custom pipeline configuration
    /// Returns a stream of events from the pipeline
    public func processVoice(
        audioStream: AsyncStream<VoiceAudioChunk>,
        config: ModularPipelineConfig
    ) -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        let pipeline = createVoicePipeline(config: config)
        return pipeline.process(audioStream: audioStream)
    }

    /// Create a modular voice pipeline with the legacy config
    /// For backward compatibility
    public func createVoicePipeline(config: VoicePipelineConfig) -> ModularVoicePipeline {
        // Convert legacy config to modular config
        var components: Set<VoiceComponent> = [.vad, .stt]
        if config.llmModelId != nil {
            components.insert(.llm)
        }
        if config.ttsEnabled {
            components.insert(.tts)
        }

        let modularConfig = ModularPipelineConfig(
            components: components,
            vad: VADConfig(),
            stt: VoiceSTTConfig(modelId: config.sttModelId),
            llm: VoiceLLMConfig(
                modelId: config.llmModelId,
                systemPrompt: config.systemPrompt,
                temperature: config.generationOptions.temperature,
                maxTokens: config.generationOptions.maxTokens
            ),
            tts: VoiceTTSConfig(voice: config.ttsVoice ?? "system")
        )

        return createVoicePipeline(config: modularConfig)
    }
}
