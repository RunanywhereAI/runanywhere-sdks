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
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "ModularVoicePipeline")
    private let config: ModularPipelineConfig

    // Component instances (created based on config)
    private var vadComponent: VADService?
    private var sttService: VoiceService?
    private var llmService: LLMService?
    private var ttsService: TextToSpeechService?

    // Audio management
    private var audioBuffer = Data()
    private var isProcessing = false
    private var isSpeechActive = false
    private var isInitialized = false

    public weak var delegate: ModularVoicePipelineDelegate?

    public init(
        config: ModularPipelineConfig,
        vadService: VADService? = nil,
        voiceService: VoiceService? = nil,
        llmService: LLMService? = nil,
        ttsService: TextToSpeechService? = nil
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
                    print("ModularPipeline: VAD speech activity event: \(event)")
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
            self.llmService = llmService
        }

        if config.components.contains(.tts) {
            self.ttsService = ttsService ?? SystemTextToSpeechService()
        }
    }

    // MARK: - Initialization

    /// Initialize all configured components
    public func initializeComponents() -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var componentsToInit: [(String, () async throws -> Void)] = []

                    // Build list of components to initialize
                    if let vad = vadComponent, config.components.contains(.vad) {
                        componentsToInit.append(("VAD", { try await vad.initialize() }))
                    }

                    if let stt = sttService, config.components.contains(.stt) {
                        let modelPath = config.stt?.modelId
                        componentsToInit.append(("STT", { try await stt.initialize(modelPath: modelPath) }))
                    }

                    if let llm = llmService, config.components.contains(.llm) {
                        if llm.isReady {
                            // LLM service is already initialized, emit events immediately
                            print("ModularPipeline: LLM service already ready, skipping initialization")
                            continuation.yield(.componentInitialized("LLM"))
                        } else {
                            // Check if we have a valid model path, otherwise try to use the existing app's LLM
                            if let modelId = config.llm?.modelId, !modelId.isEmpty, modelId != "default" {
                                print("ModularPipeline: Initializing LLM with model: \(modelId)")
                                componentsToInit.append(("LLM", { try await llm.initialize(modelPath: modelId) }))
                            } else {
                                // No valid model path, but LLM component requested - try to skip and emit success
                                print("ModularPipeline: No valid LLM model path, assuming existing app LLM will be used")
                                continuation.yield(.componentInitialized("LLM"))
                            }
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

                } catch {
                    continuation.finish(throwing: error)
                }
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
                    if !audioBuffer.isEmpty {
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
            // Use samples directly from chunk, no conversion needed
            let floatArray = chunk.samples

            // Process audio through VAD and check result
            let hasVoice = vad.processAudioData(floatArray)

            // Debug logging
            if floatArray.count > 0 {
                let energy = floatArray.map { $0 * $0 }.reduce(0, +) / Float(floatArray.count)
                let rms = sqrt(energy)
                print("ModularPipeline: Processing \(floatArray.count) samples, RMS: \(rms), hasVoice: \(hasVoice), isSpeechActive: \(isSpeechActive)")
            }

            // Handle speech state transitions
            let wasSpeaking = isSpeechActive

            // Check if speech state changed
            if hasVoice && !wasSpeaking {
                // Speech just started
                isSpeechActive = true
                audioBuffer = Data() // Clear any old data
                continuation.yield(.vadSpeechStart)
                print("ModularPipeline: Speech started, beginning to buffer audio")
            }

            // Always buffer audio when speech is active
            if isSpeechActive {
                audioBuffer.append(chunk.data)
                print("ModularPipeline: Buffering audio, total buffer size: \(audioBuffer.count) bytes")
            }

            // Check if speech ended
            if !hasVoice && wasSpeaking {
                // Speech just ended
                isSpeechActive = false
                continuation.yield(.vadSpeechEnd)
                print("ModularPipeline: Speech ended, processing \(audioBuffer.count) bytes of audio")

                // Process the buffered audio
                if !audioBuffer.isEmpty {
                    try await processBufferedAudio(continuation: continuation)
                    audioBuffer = Data()
                }
            }
        } else {
            // No VAD, buffer all audio
            audioBuffer.append(chunk.data)

            // Process periodically
            if audioBuffer.count > 32000 { // ~2 seconds at 16kHz
                print("ModularPipeline: No VAD, processing \(audioBuffer.count) bytes periodically")
                try await processBufferedAudio(continuation: continuation)
                audioBuffer = Data()
            }
        }
    }

    private func processBufferedAudio(
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {
        guard !audioBuffer.isEmpty else {
            print("ModularPipeline: processBufferedAudio called with empty buffer, skipping")
            return
        }

        print("ModularPipeline: processBufferedAudio starting with \(audioBuffer.count) bytes")

        var currentData: Any = audioBuffer

        // Step 2: STT (if enabled)
        if let stt = sttService, config.components.contains(.stt), let sttConfig = config.stt {
            print("ModularPipeline: STT service found, preparing to transcribe")

            let options = VoiceTranscriptionOptions(
                language: VoiceTranscriptionOptions.Language(rawValue: sttConfig.language) ?? .english
            )

            print("ModularPipeline: Calling STT.transcribe with \(audioBuffer.count) bytes of audio")

            do {
                let result = try await stt.transcribe(
                    audio: audioBuffer,
                    options: options
                )

                let transcript = result.text
                print("ModularPipeline: STT transcription result: '\(transcript)'")

                if !transcript.isEmpty {
                    continuation.yield(.sttFinalTranscript(transcript))
                    currentData = transcript
                } else {
                    print("ModularPipeline: WARNING - STT returned empty transcript")
                }
            } catch {
                print("ModularPipeline: ERROR - STT transcription failed: \(error)")
                throw error
            }

            // If no LLM, stop here
            if !config.components.contains(.llm) {
                print("ModularPipeline: No LLM component, stopping after STT")
                return
            }
        } else {
            print("ModularPipeline: No STT service available or not configured")
        }

        // Step 3: LLM (if enabled)
        if let llm = llmService, config.components.contains(.llm), let transcript = currentData as? String {
            continuation.yield(.llmThinking)

            let options = RunAnywhereGenerationOptions(
                maxTokens: config.llm?.maxTokens ?? 100,
                temperature: config.llm?.temperature ?? 0.7,
                systemPrompt: config.llm?.systemPrompt
            )

            let response = try await llm.generate(
                prompt: transcript,
                options: options
            )

            continuation.yield(.llmFinalResponse(response))
            currentData = response

            // If no TTS, stop here
            if !config.components.contains(.tts) {
                return
            }
        }

        // Step 4: TTS (if enabled)
        if let tts = ttsService, config.components.contains(.tts), let text = currentData as? String {
            continuation.yield(.ttsStarted)

            // For now, just speak the text
            // TTS synthesizes and plays directly
            continuation.yield(.ttsStarted)

            let ttsOptions = TTSOptions(
                voice: config.tts?.voice,
                language: "en",
                rate: config.tts?.rate ?? 1.0,
                pitch: config.tts?.pitch ?? 1.0,
                volume: config.tts?.volume ?? 1.0
            )
            try await tts.speak(text: text, options: ttsOptions)

            continuation.yield(.ttsCompleted)
        }
    }

    private func finalizeProcessing(
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {
        try await processBufferedAudio(continuation: continuation)
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
    public func createVoicePipeline(config: ModularPipelineConfig) -> ModularVoicePipeline {
        let llmService = config.components.contains(.llm) ?
            findLLMService(for: config.llm?.modelId) : nil

        return ModularVoicePipeline(
            config: config,
            vadService: nil, // Will use default SimpleEnergyVAD
            voiceService: findVoiceService(for: config.stt?.modelId ?? "whisper-base"),
            llmService: llmService,
            ttsService: findTTSService()
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
