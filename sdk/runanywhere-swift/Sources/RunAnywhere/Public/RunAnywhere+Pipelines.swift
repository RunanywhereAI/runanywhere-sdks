import Foundation
import os

// MARK: - Pipeline Extensions

public extension RunAnywhere {

    /// Create a modular voice pipeline for the sample app
    /// This uses individual components in a modular way
    @MainActor
    static func createVoicePipeline(config: ModularPipelineConfig) async throws -> ModularVoicePipeline {
        return try await ModularVoicePipeline(config: config)
    }
}

// MARK: - Modular Pipeline Configuration

/// Configuration for the modular voice pipeline
public struct ModularPipelineConfig {
    public let components: [SDKComponent]
    public let vadConfig: VADConfiguration?
    public let sttConfig: STTConfiguration?
    public let llmConfig: LLMConfiguration?
    public let ttsConfig: TTSConfiguration?

    public init(
        components: [SDKComponent],
        vadConfig: VADConfiguration? = nil,
        sttConfig: STTConfiguration? = nil,
        llmConfig: LLMConfiguration? = nil,
        ttsConfig: TTSConfiguration? = nil
    ) {
        self.components = components
        self.vadConfig = vadConfig
        self.sttConfig = sttConfig
        self.llmConfig = llmConfig
        self.ttsConfig = ttsConfig
    }

    /// Convenience initializer with simplified parameters
    public init(
        components: [SDKComponent],
        vad: VADConfig? = nil,
        stt: VoiceSTTConfig? = nil,
        llm: VoiceLLMConfig? = nil,
        tts: VoiceTTSConfig? = nil
    ) {
        self.components = components

        // Convert simplified configs to full configurations
        self.vadConfig = vad.map { VADConfiguration(energyThreshold: $0.energyThreshold) }
        self.sttConfig = stt.map { STTConfiguration(modelId: $0.modelId, language: $0.language) }
        self.llmConfig = llm.map {
            LLMConfiguration(
                modelId: $0.modelId,
                temperature: 0.3,  // Lower temperature for more consistent responses
                maxTokens: 200,    // Increased from default 100 for better responses
                systemPrompt: $0.systemPrompt
            )
        }
        self.ttsConfig = tts.map { TTSConfiguration(voice: $0.voice) }
    }

    /// Create a configuration for transcription with VAD
    public static func transcriptionWithVAD(
        sttModel: String = "whisper-base",
        vadThreshold: Float = 0.01
    ) -> ModularPipelineConfig {
        return ModularPipelineConfig(
            components: [.vad, .stt],
            vad: VADConfig(energyThreshold: vadThreshold),
            stt: VoiceSTTConfig(modelId: sttModel, language: "en")
        )
    }
}

// MARK: - Simplified Configuration Types for Sample App Compatibility

/// Simplified VAD configuration
public struct VADConfig {
    public let energyThreshold: Float

    public init(energyThreshold: Float = 0.01) {
        self.energyThreshold = energyThreshold
    }
}

/// Simplified STT configuration for voice
public struct VoiceSTTConfig {
    public let modelId: String
    public let language: String

    public init(modelId: String = "whisper-base", language: String = "en") {
        self.modelId = modelId
        self.language = language
    }
}

/// Simplified LLM configuration for voice
public struct VoiceLLMConfig {
    public let modelId: String
    public let systemPrompt: String?

    public init(modelId: String, systemPrompt: String? = nil) {
        self.modelId = modelId
        self.systemPrompt = systemPrompt
    }
}

/// Simplified TTS configuration for voice
public struct VoiceTTSConfig {
    public let voice: String

    public init(voice: String = "system") {
        self.voice = voice
    }
}

// MARK: - Pipeline Delegate

/// Protocol for pipeline delegates
public protocol ModularPipelineDelegate: AnyObject {
    func pipelineDidGenerateEvent(_ event: ModularPipelineEvent)
}

// MARK: - Modular Voice Pipeline

/// Modular voice pipeline that orchestrates individual components
@MainActor
public class ModularVoicePipeline {
    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var llmComponent: LLMComponent?
    private var ttsComponent: TTSComponent?
    private var speakerDiarizationComponent: SpeakerDiarizationComponent?
    private var customDiarizationService: SpeakerDiarizationService?

    private let config: ModularPipelineConfig
    public weak var delegate: ModularPipelineDelegate?

    // Diarization state
    private var enableDiarization = false
    private var enableContinuousMode = false

    public init(
        config: ModularPipelineConfig,
        speakerDiarization: SpeakerDiarizationService? = nil
    ) async throws {
        self.config = config

        // Create components based on config
        if config.components.contains(.vad), let vadConfig = config.vadConfig {
            vadComponent = await VADComponent(configuration: vadConfig)
        }

        if config.components.contains(.stt), let sttConfig = config.sttConfig {
            sttComponent = await STTComponent(configuration: sttConfig)
        }

        if config.components.contains(.llm), let llmConfig = config.llmConfig {
            llmComponent = await LLMComponent(configuration: llmConfig)
        }

        if config.components.contains(.tts), let ttsConfig = config.ttsConfig {
            ttsComponent = await TTSComponent(configuration: ttsConfig)
        }

        // Setup speaker diarization if provided
        if let diarization = speakerDiarization {
            customDiarizationService = diarization
        } else if config.components.contains(.speakerDiarization) {
            // Create default speaker diarization component
            let diarizationConfig = SpeakerDiarizationConfiguration()
            speakerDiarizationComponent = await SpeakerDiarizationComponent(configuration: diarizationConfig)
        }
    }

    /// Enable or disable speaker diarization
    public func enableSpeakerDiarization(_ enabled: Bool) {
        enableDiarization = enabled
    }

    /// Enable or disable continuous mode
    public func enableContinuousMode(_ enabled: Bool) {
        enableContinuousMode = enabled
    }

    /// Initialize all components
    public func initializeComponents() -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let logger = Logger(subsystem: "com.runanywhere.sdk", category: "ModularVoicePipeline")
                do {
                    // Initialize VAD
                    if let vad = vadComponent {
                        continuation.yield(.componentInitializing("VAD"))
                        try await vad.initialize()
                        continuation.yield(.componentInitialized("VAD"))
                    }

                    // Initialize STT
                    if let stt = sttComponent {
                        continuation.yield(.componentInitializing("STT"))
                        try await stt.initialize()
                        continuation.yield(.componentInitialized("STT"))
                    }

                    // Initialize LLM
                    if let llm = llmComponent {
                        continuation.yield(.componentInitializing("LLM"))
                        try await llm.initialize()
                        continuation.yield(.componentInitialized("LLM"))
                    }

                    // Initialize TTS
                    if let tts = ttsComponent {
                        continuation.yield(.componentInitializing("TTS"))
                        try await tts.initialize()
                        continuation.yield(.componentInitialized("TTS"))
                    }

                    // Initialize Speaker Diarization
                    if let diarization = speakerDiarizationComponent {
                        continuation.yield(.componentInitializing("SpeakerDiarization"))
                        try await diarization.initialize()
                        continuation.yield(.componentInitialized("SpeakerDiarization"))
                    } else if let customDiarization = customDiarizationService {
                        continuation.yield(.componentInitializing("CustomDiarization"))
                        try await customDiarization.initialize()
                        continuation.yield(.componentInitialized("CustomDiarization"))
                    }

                    continuation.yield(.allComponentsInitialized)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Process audio stream through the pipeline
    public func process(audioStream: AsyncStream<VoiceAudioChunk>) -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let logger = Logger(subsystem: "com.runanywhere.sdk", category: "ModularVoicePipeline")
                do {
                    var currentSpeaker: SpeakerInfo?
                    var audioBuffer: [Float] = []  // Accumulate audio samples
                    var isSpeaking = false

                    for await voiceChunk in audioStream {
                        // Extract float samples from VoiceAudioChunk
                        let floatSamples = voiceChunk.samples
                        let audioChunk = voiceChunk.data

                        // Process through VAD if available
                        var speechDetected = false
                        if let vad = vadComponent {
                            let vadResult = try await vad.detectSpeech(in: floatSamples)
                            speechDetected = vadResult.isSpeechDetected

                            if speechDetected && !isSpeaking {
                                // Speech just started
                                logger.info("🎙️ Speech started")
                                continuation.yield(.vadSpeechStart)
                                isSpeaking = true
                                audioBuffer = []  // Clear buffer for new speech
                            } else if !speechDetected && isSpeaking {
                                // Speech just ended
                                logger.info("🎙️ Speech ended with \(audioBuffer.count) samples")
                                continuation.yield(.vadSpeechEnd)
                                isSpeaking = false

                                // Now transcribe the accumulated audio
                                if let stt = sttComponent, !audioBuffer.isEmpty {
                                    // Check minimum audio duration (at least 0.5 second = 8000 samples at 16kHz)
                                    let minimumSamples = 8000

                                    if audioBuffer.count >= minimumSamples {
                                        logger.info("📤 Sending \(audioBuffer.count) samples to STT")
                                        // Convert accumulated float samples to Data
                                        let accumulatedData = audioBuffer.withUnsafeBytes { bytes in
                                            Data(bytes)
                                        }

                                        let transcript = try await stt.transcribe(accumulatedData)

                                        // Only emit if we got actual text
                                        if !transcript.text.isEmpty {
                                            logger.info("📝 Got transcript: '\(transcript.text)'")

                                            // Emit transcript with or without speaker info
                                            if enableDiarization, let speaker = currentSpeaker {
                                                continuation.yield(.sttFinalTranscriptWithSpeaker(transcript.text, speaker))
                                            } else {
                                                continuation.yield(.sttFinalTranscript(transcript.text))
                                            }

                                            // Process through LLM if available
                                            if let llm = llmComponent {
                                                logger.info("🤖 Sending to LLM: '\(transcript.text)'")
                                                continuation.yield(.llmThinking)
                                                let response = try await llm.generate(prompt: transcript.text)
                                                logger.info("💬 LLM Response: '\(response.text)'")
                                                continuation.yield(.llmFinalResponse(response.text))

                                                // Process through TTS if available
                                                if let tts = ttsComponent {
                                                    logger.info("🔊 Starting TTS for: '\(response.text.prefix(50))...'")
                                                    continuation.yield(.ttsStarted)
                                                    _ = try await tts.synthesize(response.text)
                                                    logger.info("✅ TTS completed")
                                                    continuation.yield(.ttsCompleted)
                                                }
                                            }
                                        } else {
                                            logger.debug("⚠️ Empty transcript, skipping")
                                        }
                                    }

                                    // Clear buffer after processing
                                    audioBuffer = []
                                }
                            }
                        } else {
                            // No VAD, treat all audio as speech
                            speechDetected = true
                        }

                        // Accumulate audio if speaking
                        if speechDetected {
                            audioBuffer.append(contentsOf: floatSamples)
                        }

                        // Process speaker diarization if enabled
                        var detectedSpeaker: SpeakerInfo?
                        if enableDiarization {
                            if let customDiarization = customDiarizationService {
                                detectedSpeaker = customDiarization.processAudio(floatSamples)
                            } else if let diarization = speakerDiarizationComponent {
                                // Use component's diarization
                                let diarizationInput = SpeakerDiarizationInput(
                                    audioData: audioChunk,
                                    format: .pcm
                                )
                                let diarizationResult = try await diarization.process(diarizationInput)
                                // Convert SpeakerProfile to SpeakerInfo
                                if let profile = diarizationResult.speakers.first {
                                    detectedSpeaker = SpeakerInfo(
                                        id: profile.id,
                                        name: profile.name,
                                        confidence: nil,
                                        embedding: profile.embedding
                                    )
                                }
                            }

                            // Check for speaker change
                            if let speaker = detectedSpeaker {
                                if currentSpeaker?.id != speaker.id {
                                    if currentSpeaker == nil {
                                        continuation.yield(.sttNewSpeakerDetected(speaker))
                                    } else {
                                        continuation.yield(.sttSpeakerChanged(from: currentSpeaker, to: speaker))
                                    }
                                    currentSpeaker = speaker
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Cleanup all components
    public func cleanup() async {
        // Cleanup can throw but we handle errors gracefully
        try? await vadComponent?.cleanup()
        try? await sttComponent?.cleanup()
        try? await llmComponent?.cleanup()
        try? await ttsComponent?.cleanup()
    }
}
