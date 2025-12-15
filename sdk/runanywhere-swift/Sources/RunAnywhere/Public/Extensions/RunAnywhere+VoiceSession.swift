//
//  RunAnywhere+VoiceSession.swift
//  RunAnywhere SDK
//
//  High-level voice session API for simplified voice assistant integration.
//  Handles audio capture, VAD, and processing internally.
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

// MARK: - Voice Session Events

/// Events emitted during a voice session
public enum VoiceSessionEvent: Sendable {
    /// Session started and ready
    case started

    /// Listening for speech with current audio level (0.0 - 1.0)
    case listening(audioLevel: Float)

    /// Speech detected, started accumulating audio
    case speechStarted

    /// Speech ended, processing audio
    case processing

    /// Got transcription from STT
    case transcribed(text: String)

    /// Got response from LLM
    case responded(text: String)

    /// Playing TTS audio
    case speaking

    /// Complete turn result
    case turnCompleted(transcript: String, response: String, audio: Data?)

    /// Session stopped
    case stopped

    /// Error occurred
    case error(String)
}

// MARK: - Voice Session Configuration

/// Configuration for voice session behavior
public struct VoiceSessionConfig: Sendable {
    /// Silence duration (seconds) before processing speech
    public var silenceDuration: TimeInterval

    /// Minimum audio level to detect speech (0.0 - 1.0)
    public var speechThreshold: Float

    /// Whether to auto-play TTS response
    public var autoPlayTTS: Bool

    /// Whether to auto-resume listening after TTS playback
    public var continuousMode: Bool

    public init(
        silenceDuration: TimeInterval = 1.5,
        speechThreshold: Float = 0.1,
        autoPlayTTS: Bool = true,
        continuousMode: Bool = true
    ) {
        self.silenceDuration = silenceDuration
        self.speechThreshold = speechThreshold
        self.autoPlayTTS = autoPlayTTS
        self.continuousMode = continuousMode
    }

    /// Default configuration
    public static let `default` = VoiceSessionConfig()
}

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

        do {
            let result = try await RunAnywhere.processVoiceTurn(audio)

            guard result.speechDetected else {
                logger.info("No speech detected")
                if config.continuousMode && isRunning {
                    try? await startListening()
                }
                return
            }

            // Emit intermediate results
            if let transcript = result.transcription {
                emit(.transcribed(text: transcript))
            }

            if let response = result.response {
                emit(.responded(text: response))
            }

            // Play TTS if enabled
            if config.autoPlayTTS, let ttsAudio = result.synthesizedAudio, !ttsAudio.isEmpty {
                emit(.speaking)
                try await audioPlayback.play(ttsAudio)
            }

            // Emit complete result
            emit(.turnCompleted(
                transcript: result.transcription ?? "",
                response: result.response ?? "",
                audio: result.synthesizedAudio
            ))

        } catch {
            logger.error("Processing failed: \(error)")
            emit(.error(error.localizedDescription))
        }

        // Resume listening if continuous mode
        if config.continuousMode && isRunning {
            try? await startListening()
        }
    }
}

// MARK: - Voice Session Errors

public enum VoiceSessionError: LocalizedError {
    case microphonePermissionDenied
    case notReady
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .notReady:
            return "Voice agent not ready. Load STT, LLM, and TTS models first."
        case .alreadyRunning:
            return "Voice session already running"
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
