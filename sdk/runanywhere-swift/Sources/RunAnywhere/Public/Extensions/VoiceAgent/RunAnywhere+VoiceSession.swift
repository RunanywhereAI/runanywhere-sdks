//
//  RunAnywhere+VoiceSession.swift
//  RunAnywhere SDK
//
//  High-level voice session API for simplified voice assistant integration.
//  Handles audio capture, VAD, and processing internally.
//
//  Types are defined in VoiceAgentTypes.swift
//
//  Usage:
//  ```swift
//  // Start a voice session
//  let session = try await RunAnywhere.startVoiceSession()
//
//  // Consume events in your UI
//  for await event in session.events {
//      switch event {
//      case .listening(let level): updateAudioMeter(level)
//      case .processing: showProcessingIndicator()
//      case .result(let transcript, let response): updateUI(transcript, response)
//      case .speaking: showSpeakingIndicator()
//      case .error(let msg): showError(msg)
//      }
//  }
//
//  // Or use callbacks
//  try await RunAnywhere.startVoiceSession { event in
//      // Handle event
//  }
//  ```
//

import AVFoundation
import Foundation

// MARK: - Voice Session Handle

/// Handle to control an active voice session
public actor VoiceSessionHandle {
    private let logger = SDKLogger(category: "VoiceSession")
    private let config: VoiceSessionConfig

    private let audioCapture = AudioCaptureManager()
    private let audioPlayback = AudioPlaybackManager()

    private var isRunning = false
    private var audioBuffer = Data()
    private var lastSpeechTime: Date?
    private var isSpeechActive = false

    private var eventContinuation: AsyncStream<VoiceSessionEvent>.Continuation?

    /// Stream of session events (nonisolated for easy consumption)
    public nonisolated let events: AsyncStream<VoiceSessionEvent>

    init(config: VoiceSessionConfig) {
        self.config = config

        var continuation: AsyncStream<VoiceSessionEvent>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    /// Start the voice session
    func start() async throws {
        guard !isRunning else { return }

        // Verify voice agent is ready, or try to initialize
        let isReady = await RunAnywhere.isVoiceAgentReady
        if !isReady {
            do {
                try await RunAnywhere.initializeVoiceAgentWithLoadedModels()
            } catch {
                emit(.error("Voice agent not ready: \(error.localizedDescription)"))
                throw error
            }
        }

        // Request mic permission
        let hasPermission = await audioCapture.requestPermission()
        guard hasPermission else {
            emit(.error("Microphone permission denied"))
            throw VoiceSessionError.microphonePermissionDenied
        }

        isRunning = true
        emit(.started)

        // Start audio capture loop
        try await startListening()
    }

    /// Stop the voice session
    public func stop() {
        guard isRunning else { return }

        isRunning = false
        audioCapture.stopRecording()
        audioPlayback.stop()

        audioBuffer = Data()
        isSpeechActive = false
        lastSpeechTime = nil

        emit(.stopped)
        eventContinuation?.finish()
    }

    public func interruptPlayback() {
        audioPlayback.stop()
    }

    /// Force process current audio (push-to-talk)
    public func sendNow() async {
        guard isRunning else { return }
        isSpeechActive = false
        await processCurrentAudio()
    }

    // MARK: - Private

    private func emit(_ event: VoiceSessionEvent) {
        eventContinuation?.yield(event)
    }

    private func startListening() async throws {
        audioBuffer = Data()
        lastSpeechTime = nil
        isSpeechActive = false

        try audioCapture.startRecording { [weak self] data in
            guard let self = self else { return }
            Task {
                await self.handleAudioData(data)
            }
        }

        // Start audio level monitoring task
        startAudioLevelMonitoring()
    }

    private func startAudioLevelMonitoring() {
        Task { [weak self] in
            guard let self = self else { return }
            while await self.isRunning {
                // Get audio level on main actor since AudioCaptureManager is ObservableObject
                let level = await self.getAudioLevel()
                await self.checkSpeechState(level: level)
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    private func getAudioLevel() async -> Float {
        await MainActor.run { audioCapture.audioLevel }
    }

    private func handleAudioData(_ data: Data) {
        guard isRunning else { return }
        audioBuffer.append(data)
    }

    private func checkSpeechState(level: Float) async {
        guard isRunning else { return }

        emit(.listening(audioLevel: level))

        if level > config.speechThreshold {
            if !isSpeechActive {
                logger.debug("Speech started")
                isSpeechActive = true
                emit(.speechStarted)
            }
            lastSpeechTime = Date()
        } else if isSpeechActive {
            if let last = lastSpeechTime, Date().timeIntervalSince(last) > config.silenceDuration {
                logger.debug("Speech ended")
                isSpeechActive = false

                // Only process if we have enough audio
                if audioBuffer.count > 16000 { // ~0.5s at 16kHz
                    await processCurrentAudio()
                } else {
                    audioBuffer = Data()
                }
            }
        }
    }

    private func processCurrentAudio() async {
        let audio = audioBuffer
        audioBuffer = Data()

        guard !audio.isEmpty, isRunning else { return }

        // Stop listening during processing
        audioCapture.stopRecording()

        emit(.processing)

        var transcription = ""
        var cleanedResponse = ""
        var thinkingContent: String?
        var synthesizedAudio: Data?

        do {
            // Step 1: Transcribe audio
            transcription = try await RunAnywhere.voiceAgentTranscribe(audio)

            guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                logger.info("No speech detected (empty transcription)")
                emit(.turnCompleted(transcript: "", response: "", thinkingContent: nil, audio: nil))
                if config.continuousMode && isRunning {
                    try? await startListening()
                }
                return
            }

            emit(.transcribed(text: transcription))

            // Step 2: Generate LLM response (apply /no_think prefix if needed)
            let effectivePrompt: String
            if !config.thinkingModeEnabled {
                effectivePrompt = "/no_think\n\(transcription)"
            } else {
                effectivePrompt = transcription
            }

            let rawResponse = try await RunAnywhere.voiceAgentGenerateResponse(effectivePrompt)

            // Step 3: Parse out <think> tags from response before TTS
            let parsed = ThinkingContentParser.extract(from: rawResponse)
            cleanedResponse = parsed.text
            thinkingContent = parsed.thinking

            emit(.responded(text: cleanedResponse, thinkingContent: thinkingContent))

            // Step 4: Synthesize speech from cleaned response (no think tags spoken)
            if config.autoPlayTTS, !cleanedResponse.isEmpty {
                let ttsAudio = try await RunAnywhere.voiceAgentSynthesizeSpeech(cleanedResponse)
                synthesizedAudio = ttsAudio

                if !ttsAudio.isEmpty {
                    emit(.speaking)
                    do {
                        try await audioPlayback.play(ttsAudio)
                    } catch is AudioPlaybackError {
                        logger.info("TTS playback interrupted by user")
                    }
                }
            }
        } catch {
            logger.error("Processing failed: \(error)")
            emit(.error(error.localizedDescription))
        }

        emit(.turnCompleted(
            transcript: transcription,
            response: cleanedResponse,
            thinkingContent: thinkingContent,
            audio: synthesizedAudio
        ))

        // Resume listening if continuous mode
        if config.continuousMode && isRunning {
            try? await startListening()
        }
    }
}

// MARK: - RunAnywhere Extension

public extension RunAnywhere {

    /// Start a voice session with async stream of events
    ///
    /// This is the simplest way to integrate voice assistant.
    /// The session handles audio capture, VAD, and processing internally.
    ///
    /// Example:
    /// ```swift
    /// let session = try await RunAnywhere.startVoiceSession()
    ///
    /// // Consume events
    /// for await event in session.events {
    ///     switch event {
    ///     case .listening(let level):
    ///         audioMeter = level
    ///     case .processing:
    ///         status = "Processing..."
    ///     case .turnCompleted(let transcript, let response, _):
    ///         userText = transcript
    ///         assistantText = response
    ///     case .stopped:
    ///         break
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter config: Session configuration (optional)
    /// - Returns: Session handle with events stream
    static func startVoiceSession(
        config: VoiceSessionConfig = .default
    ) async throws -> VoiceSessionHandle {
        let session = VoiceSessionHandle(config: config)
        try await session.start()
        return session
    }

    /// Start a voice session with callback-based event handling
    ///
    /// Alternative API using callbacks instead of async stream.
    ///
    /// Example:
    /// ```swift
    /// let session = try await RunAnywhere.startVoiceSession { event in
    ///     switch event {
    ///     case .listening(let level):
    ///         DispatchQueue.main.async { self.audioLevel = level }
    ///     case .turnCompleted(let transcript, let response, _):
    ///         DispatchQueue.main.async {
    ///             self.userText = transcript
    ///             self.assistantText = response
    ///         }
    ///     default:
    ///         break
    ///     }
    /// }
    ///
    /// // Later...
    /// await session.stop()
    /// ```
    ///
    /// - Parameters:
    ///   - config: Session configuration
    ///   - onEvent: Callback for each event
    /// - Returns: Session handle for control
    static func startVoiceSession(
        config: VoiceSessionConfig = .default,
        onEvent: @escaping @Sendable (VoiceSessionEvent) -> Void
    ) async throws -> VoiceSessionHandle {
        let session = VoiceSessionHandle(config: config)

        // Forward events to callback
        Task {
            for await event in session.events {
                onEvent(event)
            }
        }

        try await session.start()
        return session
    }
}
