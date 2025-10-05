import Foundation
import os
import AVFoundation

// MARK: - Pipeline Extensions

public extension RunAnywhere {

    /// Create a modular voice pipeline for the sample app
    /// This uses individual components in a modular way
    static func createVoicePipeline(config: ModularPipelineConfig) async throws -> ModularVoicePipeline {
        return try await ModularVoicePipeline(config: config)
    }
}

// MARK: - Modular Pipeline Configuration

// Type alias to help with type inference
public typealias PipelineEventStream = AsyncThrowingStream<ModularPipelineEvent, Error>

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
                maxTokens: $0.maxTokens ?? 100,  // Use provided or default to 100
                systemPrompt: $0.systemPrompt,
                streamingEnabled: true  // Enable streaming for real-time feedback
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
    public let maxTokens: Int?  // Optional - let model decide if not specified

    public init(modelId: String, systemPrompt: String? = nil, maxTokens: Int? = nil) {
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
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
public class ModularVoicePipeline {
    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var llmComponent: LLMComponent?
    private var ttsComponent: TTSComponent?
    private var speakerDiarizationComponent: SpeakerDiarizationComponent?
    private var customDiarizationService: SpeakerDiarizationService?

    private let config: ModularPipelineConfig
    public weak var delegate: ModularPipelineDelegate?

    // State management for feedback prevention
    private let stateManager = AudioPipelineStateManager()

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
    public func initializeComponents() -> PipelineEventStream {
        return AsyncThrowingStream<ModularPipelineEvent, Error> { continuation in
            Task {
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
    public func process(audioStream: AsyncStream<VoiceAudioChunk>) -> PipelineEventStream {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentSpeaker: SpeakerInfo?
                    var audioBuffer: [Float] = []  // Accumulate audio samples
                    var isSpeaking = false

                    for await voiceChunk in audioStream {
                        // Extract float samples from VoiceAudioChunk
                        let floatSamples = voiceChunk.samples
                        let audioChunk = voiceChunk.data

                        // Check if we can process audio based on state
                        let currentState = await stateManager.state
                        let canProcessAudio = await stateManager.canActivateMicrophone()

                        // Be extra strict - skip audio during TTS, cooldown, and generating response
                        if !canProcessAudio || currentState == .playingTTS || currentState == .cooldown || currentState == .generatingResponse {
                            // Aggressively clear the audio buffer during these states
                            audioBuffer.removeAll()  // Clear buffer to prevent any accumulation
                            if currentState == .playingTTS || currentState == .cooldown {
                                // Extra clearing for TTS and cooldown states
                                audioBuffer = []
                            }
                            print("🚫 Blocking audio - state: \(currentState), buffer cleared")
                            continue
                        }

                        // Process through VAD if available
                        var speechDetected = false
                        if let vad = vadComponent {
                            let vadResult = try await vad.detectSpeech(in: floatSamples)
                            speechDetected = vadResult.isSpeechDetected

                            if speechDetected && !isSpeaking {
                                // Speech just started
                                await stateManager.transition(to: .listening)
                                print("🎙️ Speech started")
                                continuation.yield(.vadSpeechStart)
                                isSpeaking = true
                                audioBuffer = []  // Clear buffer for new speech
                            } else if !speechDetected && isSpeaking {
                                // Speech just ended
                                await stateManager.transition(to: .processingSpeech)
                                print("🎙️ Speech ended with \(audioBuffer.count) samples")
                                continuation.yield(.vadSpeechEnd)
                                isSpeaking = false

                                // Now transcribe the accumulated audio
                                if let stt = sttComponent, !audioBuffer.isEmpty {
                                    // Check minimum audio duration (at least 1.0 second = 16000 samples at 16kHz)
                                    // WhisperKit performs better with longer audio segments
                                    let minimumSamples = 16000

                                    if audioBuffer.count >= minimumSamples {
                                        print("📤 Sending \(audioBuffer.count) samples to STT")
                                        // Convert accumulated float samples to Data
                                        let accumulatedData = audioBuffer.withUnsafeBytes { bytes in
                                            Data(bytes)
                                        }

                                        let transcript = try await stt.transcribe(accumulatedData)

                                        // Only emit if we got actual text
                                        if !transcript.text.isEmpty {
                                            print("📝 Got transcript: '\(transcript.text)'")

                                            // Emit transcript with or without speaker info
                                            if enableDiarization, let speaker = currentSpeaker {
                                                continuation.yield(.sttFinalTranscriptWithSpeaker(transcript.text, speaker))
                                            } else {
                                                continuation.yield(.sttFinalTranscript(transcript.text))
                                            }

                                            // Process through LLM if available
                                            if let llm = llmComponent {
                                                // Transition to generating response
                                                await stateManager.transition(to: .generatingResponse)

                                                // Pause VAD IMMEDIATELY when starting LLM generation
                                                await vadComponent?.pause()  // Pause VAD during response generation

                                                print("🤖 Sending to LLM: '\(transcript.text)'")
                                                continuation.yield(.llmThinking)

                                                // Use streaming for better UX - user sees response as it's generated
                                                var fullResponse = ""
                                                var lastYieldTime = Date()
                                                let yieldInterval: TimeInterval = 0.1  // Yield every 100ms for smooth updates

                                                for try await token in await llm.streamGenerate(transcript.text) {
                                                    fullResponse += token

                                                    // Yield partial responses at regular intervals for smooth UI updates
                                                    let now = Date()
                                                    if now.timeIntervalSince(lastYieldTime) >= yieldInterval {
                                                        continuation.yield(.llmPartialResponse(fullResponse))
                                                        lastYieldTime = now
                                                    }
                                                }

                                                // Always yield the final complete response
                                                print("💬 LLM Response: '\(fullResponse)'")
                                                continuation.yield(.llmFinalResponse(fullResponse))

                                                // Process through TTS if available
                                                if let tts = ttsComponent {
                                                    // Notify VAD BEFORE starting TTS that it should block
                                                    if let vad = await vadComponent?.service as? SimpleEnergyVAD {
                                                        vad.notifyTTSWillStart()
                                                    }

                                                    // Configure audio session for playback only (disable mic)
                                                    #if os(iOS) || os(tvOS) || os(watchOS)
                                                    let audioSession = AVAudioSession.sharedInstance()
                                                    let savedCategory = audioSession.category
                                                    let savedMode = audioSession.mode
                                                    let savedOptions = audioSession.categoryOptions
                                                    do {
                                                        // Switch to playback-only mode to completely disable microphone
                                                        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
                                                        try audioSession.setActive(true, options: [])
                                                        print("🔇 Microphone disabled at system level for TTS")
                                                    } catch {
                                                        print("⚠️ Failed to configure audio session for TTS: \(error)")
                                                    }
                                                    #endif

                                                    // Add a small delay to ensure VAD has blocked and audio session is configured
                                                    try await Task.sleep(nanoseconds: 200_000_000) // 200ms

                                                    // Transition to TTS playback
                                                    await stateManager.transition(to: .playingTTS)

                                                    print("🔊 Starting TTS for: '\(fullResponse.prefix(50))...'")
                                                    continuation.yield(.ttsStarted)
                                                    _ = try await tts.synthesize(fullResponse)
                                                    print("✅ TTS completed")
                                                    continuation.yield(.ttsCompleted)

                                                    // Transition to cooldown
                                                    await stateManager.transition(to: .cooldown)

                                                    // Restore audio session for recording
                                                    #if os(iOS) || os(tvOS) || os(watchOS)
                                                    do {
                                                        // Wait before re-enabling mic to ensure TTS audio has finished
                                                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                                                        // Restore to recording mode
                                                        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
                                                        try audioSession.setActive(true, options: [])
                                                        print("🎤 Microphone re-enabled at system level after 1s delay")
                                                    } catch {
                                                        print("⚠️ Failed to restore audio session: \(error)")
                                                    }
                                                    #endif
                                                }

                                                // Notify VAD that TTS finished
                                                if let vad = await vadComponent?.service as? SimpleEnergyVAD {
                                                    vad.notifyTTSDidFinish()
                                                }

                                                // Clear any buffered audio before resuming
                                                audioBuffer.removeAll()
                                                isSpeaking = false  // Reset speaking state

                                                // Clear audio buffer immediately after TTS
                                                audioBuffer.removeAll()

                                                // Wait for cooldown to complete with much longer delay
                                                // This ensures TTS audio has fully cleared from hardware buffers
                                                var cooldownIterations = 0
                                                while await stateManager.state == .cooldown && cooldownIterations < 30 {  // Up to 3 seconds
                                                    // Keep clearing buffer during cooldown
                                                    audioBuffer.removeAll()
                                                    try await Task.sleep(nanoseconds: 100_000_000)  // Check every 100ms
                                                    cooldownIterations += 1
                                                }

                                                // Add substantial extra delay before resuming VAD
                                                try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 second extra delay

                                                // Final buffer clear before resuming
                                                audioBuffer.removeAll()

                                                // Resume VAD after all delays
                                                await vadComponent?.resume()
                                                print("🎤 VAD resumed after extended cooldown (total ~5s), ready for next input")
                                            } else {
                                                // No LLM, just transition back to idle
                                                await stateManager.transition(to: .idle)
                                            }
                                        } else {
                                            print("⚠️ Empty transcript, skipping")
                                            await stateManager.transition(to: .idle)
                                        }
                                    } else {
                                        // Audio too short, return to idle
                                        print("Audio too short for transcription")
                                        await stateManager.transition(to: .idle)
                                    }

                                    // Clear buffer after processing
                                    audioBuffer = []
                                } else {
                                    // No STT component, return to idle
                                    await stateManager.transition(to: .idle)
                                }
                            }
                        } else {
                            // No VAD, treat all audio as speech
                            speechDetected = true
                        }

                        // Accumulate audio if we're currently in a speech segment
                        if isSpeaking {
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
