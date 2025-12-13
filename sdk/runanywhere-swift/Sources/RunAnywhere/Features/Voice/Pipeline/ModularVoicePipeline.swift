// swiftlint:disable file_length
import AVFoundation
import Foundation

// MARK: - Modular Voice Pipeline

/// Modular voice pipeline that orchestrates individual components
public class ModularVoicePipeline: NSObject, AVAudioPlayerDelegate { // swiftlint:disable:this type_body_length
    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var llmComponent: LLMComponent?
    private var ttsComponent: TTSComponent?
    private var speakerDiarizationService: SpeakerDiarizationService?

    private let config: ModularPipelineConfig
    public weak var delegate: ModularPipelineDelegate?

    // State management for feedback prevention
    private let stateManager = AudioPipelineStateManager()

    // Diarization state
    private var enableDiarization = false
    private var enableContinuousMode = false

    // Audio playback for Piper/ONNX TTS (which returns audio data instead of playing directly)
    private var audioPlayer: AVAudioPlayer?
    private var audioPlaybackContinuation: CheckedContinuation<Void, Error>?
    private let logger: SDKLogger

    public init(
        config: ModularPipelineConfig,
        speakerDiarization: SpeakerDiarizationService? = nil
    ) async throws {
        self.config = config
        self.logger = SDKLogger(category: "ModularVoicePipeline")
        super.init()

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
            speakerDiarizationService = diarization
        } else if config.components.contains(.speakerDiarization) {
            // Create default speaker diarization service
            let defaultService = DefaultSpeakerDiarizationService()
            try await defaultService.initialize()
            speakerDiarizationService = defaultService
        }
    }

    // MARK: - TTS Audio Playback

    /// Play TTS audio data using AVAudioPlayer
    /// For Piper/ONNX TTS models that return audio data instead of playing directly
    private func playTTSAudio(_ audioData: Data) async throws {
        guard !audioData.isEmpty else {
            // System TTS returns empty data - audio already played via AVSpeechSynthesizer
            logger.info("Empty audio data - System TTS already played audio directly")
            return
        }

        logger.info("Playing Piper/ONNX TTS audio: \(audioData.count) bytes")

        // Configure audio session for playback
        #if os(iOS) || os(tvOS) || os(watchOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            logger.error("Failed to configure audio session for TTS playback: \(error)")
        }
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            do {
                // Create audio player from WAV data
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()

                // Store continuation to resume when playback completes
                audioPlaybackContinuation = continuation

                // Start playback
                if audioPlayer?.play() == true {
                    logger.info("TTS audio playback started")
                } else {
                    audioPlaybackContinuation = nil
                    continuation.resume(throwing: RunAnywhereError.generationFailed("Failed to start TTS audio playback"))
                }
            } catch {
                logger.error("Failed to create audio player: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Guard against stale callbacks from replaced players
        guard player === audioPlayer else { return }
        logger.info("TTS audio playback finished (success: \(flag))")
        audioPlayer = nil

        if flag {
            audioPlaybackContinuation?.resume()
        } else {
            audioPlaybackContinuation?.resume(throwing: RunAnywhereError.generationFailed("TTS audio playback failed"))
        }
        audioPlaybackContinuation = nil
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        // Guard against stale callbacks from replaced players
        guard player === audioPlayer else { return }
        logger.error("TTS audio decode error: \(error?.localizedDescription ?? "unknown")")
        audioPlayer = nil
        audioPlaybackContinuation?.resume(throwing: error ?? RunAnywhereError.generationFailed("TTS audio decode error"))
        audioPlaybackContinuation = nil
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
                    if let diarization = speakerDiarizationService {
                        continuation.yield(.componentInitializing("SpeakerDiarization"))
                        try await diarization.initialize()
                        continuation.yield(.componentInitialized("SpeakerDiarization"))
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
    /// Uses silence detection to automatically trigger STT -> LLM -> TTS flow
    public func process(audioStream: AsyncStream<VoiceAudioChunk>) -> PipelineEventStream { // swiftlint:disable:this function_body_length cyclomatic_complexity
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentSpeaker: SpeakerDiarizationSpeakerInfo?
                    var audioBuffer: [Float] = []  // Accumulate audio samples
                    var isSpeaking = false

                    // Silence detection for live conversational mode
                    // When user pauses speaking for ~0.5-0.8 seconds, we process
                    var silenceFrameCount = 0
                    let silenceThresholdFrames = 5  // 5 frames x 100ms = 0.5 seconds of silence
                    let silenceEnergyThreshold: Float = 0.05  // Audio level below this is "silence"
                    var hasRecordedSpeech = false  // Track if we've recorded any real speech
                    var speechFrameCount = 0  // Track how many frames of actual speech we've recorded
                    let minimumSpeechFrames = 3  // Require at least ~0.3 seconds of speech before processing

                    // Garbage transcript patterns to filter out (STT artifacts when no real speech)
                    let garbagePatterns = [
                        "[BLANK_AUDIO]", "[BLANK_", "[ Silence ]", "[Silence]", "(buzzer)",
                        "(mumbling)", "(clicking)", "(typing)", "(noise)", "(static)",
                        "(inaudible)", "(music)", "[MUSIC]", "(background)", "(breathing)"
                    ]

                    for await voiceChunk in audioStream {
                        // Extract float samples from VoiceAudioChunk
                        let floatSamples = voiceChunk.samples
                        let audioChunk = voiceChunk.data

                        // Check if we can process audio based on state
                        let currentState = await stateManager.state

                        // Block audio during TTS, generation, AND cooldown to prevent feedback
                        if currentState == .playingTTS || currentState == .generatingResponse || currentState == .cooldown {
                            // Clear buffer during these critical states
                            audioBuffer.removeAll()
                            silenceFrameCount = 0
                            hasRecordedSpeech = false
                            if currentState == .cooldown {
                                print("🛡️ Blocking audio during cooldown - preventing feedback")
                            } else {
                                print("🚫 Blocking audio - state: \(currentState), buffer cleared")
                            }
                            continue
                        }

                        // Calculate audio level for visualization (RMS energy)
                        let audioLevel = Self.calculateAudioLevel(floatSamples)
                        continuation.yield(.vadAudioLevel(audioLevel))

                        // Process through VAD if available, otherwise use silence-based detection
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

                                // Now transcribe the accumulated audio - NO minimum threshold
                                if let stt = sttComponent, !audioBuffer.isEmpty {
                                    print("📤 Sending \(audioBuffer.count) samples to STT")
                                    // Convert Float32 samples to Int16 PCM (what STT expects)
                                    let accumulatedData = Self.convertFloatToInt16PCM(audioBuffer)

                                    // Use proper STTOptions - AudioCapture outputs 16kHz audio
                                    let sttOptions = STTOptions(
                                        language: "en",
                                        enablePunctuation: true,
                                        audioFormat: .pcm,
                                        sampleRate: 16000  // AudioCapture already resamples to 16kHz
                                    )
                                    let transcript = try await stt.transcribe(accumulatedData, options: sttOptions)

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
                                            await vadComponent?.pause()

                                            print("🤖 Sending to LLM: '\(transcript.text)'")
                                            continuation.yield(.llmThinking)

                                            // Use streaming for better UX
                                            var fullResponse = ""
                                            var lastYieldTime = Date()
                                            let yieldInterval: TimeInterval = 0.1

                                            for try await token in await llm.streamGenerate(transcript.text) {
                                                fullResponse += token

                                                let now = Date()
                                                if now.timeIntervalSince(lastYieldTime) >= yieldInterval {
                                                    continuation.yield(.llmPartialResponse(fullResponse))
                                                    lastYieldTime = now
                                                }
                                            }

                                            print("💬 LLM Response: '\(fullResponse)'")
                                            continuation.yield(.llmFinalResponse(fullResponse))

                                            // Process through TTS if available
                                            if let tts = ttsComponent {
                                                if let vad = await vadComponent?.service as? SimpleEnergyVADService {
                                                    vad.notifyTTSWillStart()
                                                }

                                                // PAUSE RECORDING before TTS - prevents feedback loop
                                                print("⏸️ Pausing recording for TTS playback")
                                                continuation.yield(.audioControlPauseRecording)

                                                try await Task.sleep(nanoseconds: 50_000_000) // 50ms buffer before TTS

                                                let transitionedToPlaying = await stateManager.transition(to: .playingTTS)

                                                if transitionedToPlaying {
                                                    print("🔊 Starting TTS for: '\(fullResponse.prefix(50))...'")
                                                    continuation.yield(.ttsStarted)

                                                    do {
                                                        // Generate TTS audio
                                                        let ttsOutput = try await tts.synthesize(fullResponse)

                                                        // Play audio - handles both System TTS (empty data) and Piper TTS (WAV data)
                                                        try await self.playTTSAudio(ttsOutput.audioData)

                                                        print("✅ TTS completed")
                                                        continuation.yield(.ttsCompleted)

                                                        let currentState = await stateManager.state
                                                        if currentState == .playingTTS {
                                                            await stateManager.transition(to: .cooldown)
                                                        }
                                                    } catch {
                                                        print("⚠️ TTS synthesis failed: \(error)")
                                                        let currentState = await stateManager.state
                                                        if currentState == .playingTTS {
                                                            await stateManager.transition(to: .cooldown)
                                                        }
                                                    }
                                                }

                                                // Wait for audio system to settle after TTS
                                                #if os(iOS) || os(tvOS) || os(watchOS)
                                                try await Task.sleep(nanoseconds: 300_000_000) // 300ms post-TTS cooldown
                                                #endif
                                            }

                                            // Notify VAD that TTS finished
                                            if let vad = await vadComponent?.service as? SimpleEnergyVADService {
                                                vad.notifyTTSDidFinish()
                                            }

                                            // Clear buffer and wait for cooldown
                                            audioBuffer.removeAll()
                                            isSpeaking = false

                                            while await stateManager.state == .cooldown {
                                                try await Task.sleep(nanoseconds: 50_000_000)
                                            }

                                            // Additional delay to let echo/reverb dissipate
                                            try await Task.sleep(nanoseconds: 200_000_000) // 200ms extra

                                            // RESUME RECORDING after cooldown complete
                                            print("▶️ Resuming recording after TTS")
                                            continuation.yield(.audioControlResumeRecording)

                                            audioBuffer.removeAll()
                                            await vadComponent?.resume()
                                            print("🎤 VAD resumed, ready for next input")
                                        } else {
                                            await stateManager.transition(to: .idle)
                                        }
                                    } else {
                                        print("⚠️ Empty transcript, skipping")
                                        await stateManager.transition(to: .idle)
                                    }

                                    audioBuffer = []
                                } else {
                                    await stateManager.transition(to: .idle)
                                }
                            }
                        } else {
                            // No VAD - Live conversational mode with silence detection
                            // Automatically detect when user stops speaking and process

                            // Start recording on first chunk
                            if !isSpeaking {
                                await stateManager.transition(to: .listening)
                                print("🎙️ Live mode: Recording started (silence detection active)")
                                continuation.yield(.vadSpeechStart)
                                isSpeaking = true
                                silenceFrameCount = 0
                                hasRecordedSpeech = false
                            }

                            // Detect if this is speech or silence based on audio level
                            if audioLevel > silenceEnergyThreshold {
                                // User is speaking
                                silenceFrameCount = 0
                                hasRecordedSpeech = true
                                speechFrameCount += 1
                                speechDetected = true
                            } else if hasRecordedSpeech {
                                // Silence detected after user spoke
                                silenceFrameCount += 1

                                if silenceFrameCount >= silenceThresholdFrames {
                                    // User paused for ~0.5 seconds
                                    // Only process if we have enough actual speech (not just noise/silence)
                                    if speechFrameCount < minimumSpeechFrames {
                                        print("⚠️ Not enough speech (\(speechFrameCount) frames) - ignoring, need at least \(minimumSpeechFrames)")
                                        // Reset and continue listening
                                        audioBuffer.removeAll()
                                        silenceFrameCount = 0
                                        speechFrameCount = 0
                                        hasRecordedSpeech = false
                                        continue
                                    }

                                    print("🔇 Silence detected (\(silenceFrameCount) frames, \(speechFrameCount) speech frames) - processing speech")
                                    await stateManager.transition(to: .processingSpeech)
                                    continuation.yield(.vadSpeechEnd)
                                    isSpeaking = false

                                    // Process through STT -> LLM -> TTS
                                    if let stt = sttComponent, !audioBuffer.isEmpty {
                                        print("📤 Sending \(audioBuffer.count) samples to STT")
                                        let accumulatedData = Self.convertFloatToInt16PCM(audioBuffer)

                                        // Use proper STTOptions - AudioCapture outputs 16kHz audio
                                        let sttOptions = STTOptions(
                                            language: "en",
                                            enablePunctuation: true,
                                            audioFormat: .pcm,
                                            sampleRate: 16000  // AudioCapture already resamples to 16kHz
                                        )

                                        do {
                                            let transcript = try await stt.transcribe(accumulatedData, options: sttOptions)

                                            // Check for garbage/artifact transcripts
                                            let trimmedText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                            let isGarbage = garbagePatterns.contains { pattern in
                                                trimmedText.localizedCaseInsensitiveContains(pattern) ||
                                                trimmedText.hasPrefix("[") || trimmedText.hasPrefix("(")
                                            }

                                            if isGarbage {
                                                print("🗑️ Filtered garbage transcript: '\(transcript.text)' - resuming listening")
                                                // Reset and continue listening
                                                audioBuffer.removeAll()
                                                silenceFrameCount = 0
                                                speechFrameCount = 0
                                                hasRecordedSpeech = false
                                                isSpeaking = true
                                                await stateManager.transition(to: .listening)
                                                continuation.yield(.vadSpeechStart)
                                                continue
                                            }

                                            if !transcript.text.isEmpty {
                                                print("📝 Got transcript: '\(transcript.text)'")

                                                if enableDiarization, let speaker = currentSpeaker {
                                                    continuation.yield(.sttFinalTranscriptWithSpeaker(transcript.text, speaker))
                                                } else {
                                                    continuation.yield(.sttFinalTranscript(transcript.text))
                                                }

                                                // Process through LLM if available
                                                if let llm = llmComponent {
                                                    await stateManager.transition(to: .generatingResponse)
                                                    print("🤖 Sending to LLM: '\(transcript.text)'")
                                                    continuation.yield(.llmThinking)

                                                    var fullResponse = ""
                                                    var lastYieldTime = Date()
                                                    let yieldInterval: TimeInterval = 0.1

                                                    for try await token in await llm.streamGenerate(transcript.text) {
                                                        fullResponse += token
                                                        let now = Date()
                                                        if now.timeIntervalSince(lastYieldTime) >= yieldInterval {
                                                            continuation.yield(.llmPartialResponse(fullResponse))
                                                            lastYieldTime = now
                                                        }
                                                    }

                                                    print("💬 LLM Response: '\(fullResponse)'")
                                                    continuation.yield(.llmFinalResponse(fullResponse))

                                                    // Process through TTS if available
                                                    if let tts = ttsComponent {
                                                        // PAUSE RECORDING before TTS - prevents feedback loop
                                                        print("⏸️ Pausing recording for TTS playback")
                                                        continuation.yield(.audioControlPauseRecording)

                                                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms buffer before TTS

                                                        let transitionedToPlaying = await stateManager.transition(to: .playingTTS)
                                                        if transitionedToPlaying {
                                                            print("🔊 Starting TTS")
                                                            continuation.yield(.ttsStarted)

                                                            do {
                                                                // Generate TTS audio
                                                                let ttsOutput = try await tts.synthesize(fullResponse)

                                                                // Play audio - handles both System TTS (empty data) and Piper TTS (WAV data)
                                                                try await self.playTTSAudio(ttsOutput.audioData)

                                                                print("✅ TTS completed")
                                                                continuation.yield(.ttsCompleted)
                                                                await stateManager.transition(to: .cooldown)
                                                            } catch {
                                                                print("⚠️ TTS failed: \(error)")
                                                                await stateManager.transition(to: .cooldown)
                                                            }
                                                        }

                                                        // Wait for audio system to settle after TTS
                                                        #if os(iOS) || os(tvOS) || os(watchOS)
                                                        try await Task.sleep(nanoseconds: 300_000_000) // 300ms post-TTS cooldown
                                                        #endif
                                                    }

                                                    // Wait for cooldown, then resume listening
                                                    while await stateManager.state == .cooldown {
                                                        try await Task.sleep(nanoseconds: 50_000_000)
                                                    }

                                                    // Additional delay to let echo/reverb dissipate
                                                    try await Task.sleep(nanoseconds: 200_000_000) // 200ms extra

                                                    // Resume listening for next turn - CLEAR ALL STATE
                                                    audioBuffer.removeAll()
                                                    silenceFrameCount = 0
                                                    speechFrameCount = 0  // Reset speech frame count
                                                    hasRecordedSpeech = false
                                                    isSpeaking = false

                                                    // RESUME RECORDING after cooldown complete
                                                    print("▶️ Resuming recording after TTS")
                                                    continuation.yield(.audioControlResumeRecording)

                                                    // Start listening again automatically
                                                    await stateManager.transition(to: .listening)
                                                    print("🎤 Ready for next input")
                                                    continuation.yield(.vadSpeechStart)
                                                    isSpeaking = true
                                                } else {
                                                    await stateManager.transition(to: .idle)
                                                }
                                            } else {
                                                print("⚠️ Empty transcript, resuming listening")
                                                // Resume listening
                                                audioBuffer.removeAll()
                                                silenceFrameCount = 0
                                                speechFrameCount = 0
                                                hasRecordedSpeech = false
                                                await stateManager.transition(to: .listening)
                                                continuation.yield(.vadSpeechStart)
                                                isSpeaking = true
                                            }
                                        } catch {
                                            print("⚠️ STT failed: \(error), resuming listening")
                                            audioBuffer.removeAll()
                                            silenceFrameCount = 0
                                            speechFrameCount = 0
                                            hasRecordedSpeech = false
                                            await stateManager.transition(to: .listening)
                                            continuation.yield(.vadSpeechStart)
                                            isSpeaking = true
                                        }
                                    }

                                    audioBuffer = []
                                }
                            }
                            speechDetected = true
                        }

                        // Accumulate audio if we're currently in a speech segment
                        if isSpeaking {
                            audioBuffer.append(contentsOf: floatSamples)
                        }

                        // Process speaker diarization if enabled
                        var detectedSpeaker: SpeakerDiarizationSpeakerInfo?
                        if enableDiarization {
                            if let diarization = speakerDiarizationService {
                                detectedSpeaker = diarization.processAudio(floatSamples)
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

                    // Stream ended - process any remaining accumulated audio
                    // This handles the case when user manually stops the stream
                    if vadComponent == nil && !audioBuffer.isEmpty {
                        print("🎙️ Stream ended with \(audioBuffer.count) samples")
                        continuation.yield(.vadSpeechEnd)

                        // Process accumulated audio through STT - NO minimum threshold
                        if let stt = sttComponent {
                            print("📤 Sending \(audioBuffer.count) samples to STT")
                            let accumulatedData = Self.convertFloatToInt16PCM(audioBuffer)

                            // Use proper STTOptions - AudioCapture outputs 16kHz audio
                            let sttOptions = STTOptions(
                                language: "en",
                                enablePunctuation: true,
                                audioFormat: .pcm,
                                sampleRate: 16000  // AudioCapture already resamples to 16kHz
                            )

                            do {
                                let transcript = try await stt.transcribe(accumulatedData, options: sttOptions)
                                if !transcript.text.isEmpty {
                                    print("📝 Got transcript: '\(transcript.text)'")
                                    continuation.yield(.sttFinalTranscript(transcript.text))

                                    // Process through LLM if available
                                    if let llm = llmComponent {
                                        await stateManager.transition(to: .generatingResponse)
                                        print("🤖 Sending to LLM: '\(transcript.text)'")
                                        continuation.yield(.llmThinking)

                                        var fullResponse = ""
                                        for try await token in await llm.streamGenerate(transcript.text) {
                                            fullResponse += token
                                        }

                                        print("💬 LLM Response: '\(fullResponse)'")
                                        continuation.yield(.llmFinalResponse(fullResponse))

                                        // Process through TTS if available
                                        if let tts = ttsComponent {
                                            await stateManager.transition(to: .playingTTS)
                                            print("🔊 Starting TTS")
                                            continuation.yield(.ttsStarted)

                                            do {
                                                // Generate TTS audio
                                                let ttsOutput = try await tts.synthesize(fullResponse)

                                                // Play audio - handles both System TTS (empty data) and Piper TTS (WAV data)
                                                try await self.playTTSAudio(ttsOutput.audioData)

                                                print("✅ TTS completed")
                                                continuation.yield(.ttsCompleted)
                                            } catch {
                                                print("⚠️ TTS synthesis failed: \(error)")
                                            }
                                        }
                                    }
                                }
                            } catch {
                                print("⚠️ STT transcription failed: \(error)")
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

    /// Calculate audio level (RMS) for visualization - returns 0.0 to 1.0
    private static func calculateAudioLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        var sum: Float = 0.0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(samples.count))
        // Convert RMS to dB and normalize to 0-1 range
        let dbLevel = 20 * log10(rms + 0.0001)
        return max(0, min(1, (dbLevel + 60) / 60))
    }

    /// Convert Float32 audio samples to Int16 PCM Data (what STT expects)
    /// This matches the conversion done in the working STT view
    private static func convertFloatToInt16PCM(_ floatSamples: [Float]) -> Data {
        var int16Samples: [Int16] = []
        int16Samples.reserveCapacity(floatSamples.count)

        for sample in floatSamples {
            // Clamp to [-1.0, 1.0] and convert to Int16 range
            let clampedSample = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clampedSample * Float(Int16.max))
            int16Samples.append(int16Sample)
        }

        return int16Samples.withUnsafeBytes { bytes in
            Data(bytes)
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
