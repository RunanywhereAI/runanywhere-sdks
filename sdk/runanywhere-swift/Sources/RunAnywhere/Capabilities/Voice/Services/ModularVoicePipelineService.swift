import Foundation
import os
import AVFoundation

// MARK: - Pipeline Configuration

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

    /// Convenience initializer from unified voice configuration
    public init(voiceConfig: VoiceConfiguration) {
        self.components = [.vad, .stt, .llm, .tts]
        self.vadConfig = voiceConfig.vad
        self.sttConfig = voiceConfig.stt
        self.llmConfig = voiceConfig.llm
        self.ttsConfig = voiceConfig.tts
    }
}

// MARK: - Pipeline Delegate

/// Protocol for pipeline delegates
public protocol ModularPipelineDelegate: AnyObject {
    func pipelineDidGenerateEvent(_ event: SDKVoiceEvent)
}

// MARK: - Modular Voice Pipeline Service

/// Service that orchestrates modular voice pipeline components
/// This is the proper location following SDK patterns: Capabilities/Voice/Services
public class ModularVoicePipelineService {
    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var llmComponent: LLMComponent?
    private var ttsComponent: TTSComponent?
    private var speakerDiarizationComponent: SpeakerDiarizationComponent?
    private var customDiarizationService: SpeakerDiarizationService?

    private let config: ModularPipelineConfig
    private let eventBus: EventBus
    public weak var delegate: ModularPipelineDelegate?

    // State management for feedback prevention
    private let stateManager: AudioPipelineStateManager

    // Diarization state
    private var enableDiarization = false
    private var enableContinuousMode = false

    public init(
        config: ModularPipelineConfig,
        speakerDiarization: SpeakerDiarizationService? = nil,
        eventBus: EventBus = EventBus.shared
    ) async throws {
        self.config = config
        self.eventBus = eventBus
        self.stateManager = AudioPipelineStateManager(eventBus: eventBus)

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
    public func initializeComponents() -> AsyncThrowingStream<SDKVoiceEvent, Error> {
        return AsyncThrowingStream<SDKVoiceEvent, Error> { continuation in
            Task {
                do {
                    // Initialize VAD
                    if let vad = vadComponent {
                        eventBus.publish(SDKVoiceEvent.componentInitializing("VAD"))
                        try await vad.initialize()
                        eventBus.publish(SDKVoiceEvent.componentInitialized("VAD"))
                    }

                    // Initialize STT
                    if let stt = sttComponent {
                        eventBus.publish(SDKVoiceEvent.componentInitializing("STT"))
                        try await stt.initialize()
                        eventBus.publish(SDKVoiceEvent.componentInitialized("STT"))
                    }

                    // Initialize LLM
                    if let llm = llmComponent {
                        eventBus.publish(SDKVoiceEvent.componentInitializing("LLM"))
                        try await llm.initialize()
                        eventBus.publish(SDKVoiceEvent.componentInitialized("LLM"))
                    }

                    // Initialize TTS
                    if let tts = ttsComponent {
                        eventBus.publish(SDKVoiceEvent.componentInitializing("TTS"))
                        try await tts.initialize()
                        eventBus.publish(SDKVoiceEvent.componentInitialized("TTS"))
                    }

                    // Initialize Speaker Diarization
                    if let diarization = speakerDiarizationComponent {
                        eventBus.publish(SDKVoiceEvent.componentInitializing("SpeakerDiarization"))
                        try await diarization.initialize()
                        eventBus.publish(SDKVoiceEvent.componentInitialized("SpeakerDiarization"))
                    } else if let customDiarization = customDiarizationService {
                        eventBus.publish(SDKVoiceEvent.componentInitializing("CustomDiarization"))
                        try await customDiarization.initialize()
                        eventBus.publish(SDKVoiceEvent.componentInitialized("CustomDiarization"))
                    }

                    eventBus.publish(SDKVoiceEvent.allComponentsInitialized)
                    continuation.finish()
                } catch {
                    eventBus.publish(SDKVoiceEvent.componentInitializationFailed("Pipeline", error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Process audio stream through the pipeline
    public func process(audioStream: AsyncStream<VoiceAudioChunk>) -> AsyncThrowingStream<SDKVoiceEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentSpeaker: SpeakerInfo?
                    var audioBuffer: [Float] = []
                    var isSpeaking = false

                    for await voiceChunk in audioStream {
                        let floatSamples = voiceChunk.samples

                        // Check if we can process audio based on state
                        let currentState = await stateManager.state

                        // Block audio during TTS, generation, AND cooldown to prevent feedback
                        if currentState == .playingTTS || currentState == .generatingResponse || currentState == .cooldown {
                            audioBuffer.removeAll()
                            continue
                        }

                        // Process through VAD if available
                        var speechDetected = false
                        if let vad = vadComponent {
                            let vadResult = try await vad.detectSpeech(in: floatSamples)
                            speechDetected = vadResult.isSpeechDetected

                            if speechDetected && !isSpeaking {
                                // Speech just started
                                _ = await stateManager.transition(to: .listening)
                                eventBus.publish(SDKVoiceEvent.vadSpeechStart)
                                isSpeaking = true
                                audioBuffer = []
                            } else if !speechDetected && isSpeaking {
                                // Speech just ended
                                _ = await stateManager.transition(to: .processingSpeech)
                                eventBus.publish(SDKVoiceEvent.vadSpeechEnd)
                                isSpeaking = false

                                // Transcribe the accumulated audio
                                if let stt = sttComponent, !audioBuffer.isEmpty {
                                    let minimumSamples = 12800
                                    if audioBuffer.count >= minimumSamples {
                                        let accumulatedData = audioBuffer.withUnsafeBytes { bytes in
                                            Data(bytes)
                                        }
                                        let transcript = try await stt.transcribe(accumulatedData)

                                        if !transcript.text.isEmpty {
                                            // Emit transcript with or without speaker info
                                            if enableDiarization, let speaker = currentSpeaker {
                                                eventBus.publish(SDKVoiceEvent.transcriptionFinalWithSpeaker(text: transcript.text, speaker: speaker))
                                            } else {
                                                eventBus.publish(SDKVoiceEvent.transcriptionFinal(text: transcript.text))
                                            }

                                            // Process through LLM if available
                                            if let llm = llmComponent {
                                                _ = await stateManager.transition(to: .generatingResponse)
                                                await vadComponent?.pause()

                                                eventBus.publish(SDKVoiceEvent.llmThinking)

                                                // Use streaming generation
                                                for try await token in await llm.streamGenerate(transcript.text) {
                                                    eventBus.publish(SDKVoiceEvent.llmStreamToken(token))
                                                }

                                                // Process through TTS if available
                                                if let tts = ttsComponent {
                                                    _ = await stateManager.transition(to: .playingTTS)
                                                    let response = try await llm.generate(transcript.text)
                                                    _ = try await tts.synthesize(response.text)
                                                    _ = await stateManager.transition(to: .cooldown)
                                                }

                                                await vadComponent?.resume()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Accumulate audio samples while speaking
                        if isSpeaking {
                            audioBuffer.append(contentsOf: floatSamples)
                        }
                    }
                } catch {
                    eventBus.publish(SDKVoiceEvent.pipelineError(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Legacy Compatibility

/// Type alias for backward compatibility - points to the service in Capabilities
public typealias ModularVoicePipeline = ModularVoicePipelineService
