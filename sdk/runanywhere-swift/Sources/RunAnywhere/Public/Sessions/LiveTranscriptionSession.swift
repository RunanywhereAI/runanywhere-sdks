//
//  LiveTranscriptionSession.swift
//  RunAnywhere SDK
//
//  High-level API for live/streaming transcription.
//  Combines audio capture and streaming transcription into a single abstraction.
//

import Combine
import Foundation

// MARK: - Live Transcription Session

/// A session for live/streaming speech-to-text transcription.
///
/// This provides a high-level API that combines audio capture and streaming
/// transcription, handling all the complexity internally.
///
/// ## Usage
///
/// ```swift
/// // Start live transcription
/// let session = try await RunAnywhere.startLiveTranscription()
///
/// // Listen for transcription updates
/// for await text in session.transcriptions {
///     print("Partial: \(text)")
/// }
///
/// // Or use callback style
/// let session = try await RunAnywhere.startLiveTranscription { text in
///     print("Partial: \(text)")
/// }
///
/// // Stop when done
/// await session.stop()
/// ```
@MainActor
public final class LiveTranscriptionSession: ObservableObject, @unchecked Sendable {
    private let logger = SDKLogger(category: "LiveTranscription")

    // MARK: - Published State

    /// Current transcription text (updates in real-time)
    @Published public private(set) var currentText: String = ""

    /// Whether the session is actively transcribing
    @Published public private(set) var isActive: Bool = false

    /// Current audio level (0.0 - 1.0) for visualization
    @Published public private(set) var audioLevel: Float = 0.0

    /// Error if transcription failed
    @Published public private(set) var error: Error?

    // MARK: - Private Properties

    private let audioCapture: AudioCaptureManager
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var transcriptionTask: Task<Void, Never>?
    private var audioLevelCancellable: AnyCancellable?
    private let options: STTOptions

    // Callback for partial transcriptions
    private var onPartialCallback: ((String) -> Void)?

    // MARK: - Transcription Stream

    /// Async stream of transcription text updates
    public var transcriptions: AsyncStream<String> {
        AsyncStream { [weak self] continuation in
            Task { @MainActor in
                self?.onPartialCallback = { text in
                    continuation.yield(text)
                }
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.onPartialCallback = nil
                }
            }
        }
    }

    // MARK: - Initialization

    /// Create a new live transcription session
    /// - Parameter options: STT options (language, etc.)
    public init(options: STTOptions = STTOptions()) {
        self.audioCapture = AudioCaptureManager()
        self.options = options
    }

    // MARK: - Public Methods

    /// Start live transcription
    /// - Parameter onPartial: Optional callback for each partial transcription update
    /// - Throws: `LiveTranscriptionError.alreadyActive` if session is already running,
    ///           `LiveTranscriptionError.microphonePermissionDenied` if mic access denied
    public func start(onPartial: ((String) -> Void)? = nil) async throws {
        guard !isActive else {
            throw LiveTranscriptionError.alreadyActive
        }

        // Request microphone permission
        let granted = await audioCapture.requestPermission()
        guard granted else {
            throw LiveTranscriptionError.microphonePermissionDenied
        }

        // Store callback
        if let callback = onPartial {
            self.onPartialCallback = callback
        }

        // Subscribe to audio level updates
        audioLevelCancellable = audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }

        isActive = true
        error = nil
        currentText = ""

        // Start streaming transcription with callbacks
        do {
            try await RunAnywhere.startStreamingTranscription(
                options: options,
                onPartialResult: { [weak self] result in
                    Task { @MainActor in
                        guard let self = self, !Task.isCancelled else { return }
                        self.currentText = result.transcript
                        self.onPartialCallback?(result.transcript)
                    }
                },
                onFinalResult: { [weak self] output in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.currentText = output.text
                        self.onPartialCallback?(output.text)
                        self.logger.info("Final transcription: \(output.text)")
                    }
                },
                onError: { [weak self] err in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.error = err
                        self.logger.error("Transcription error: \(err.localizedDescription)")
                    }
                }
            )
        } catch {
            isActive = false
            throw error
        }

        // Start audio capture that feeds into the streaming transcription
        try audioCapture.startRecording { [weak self] audioData in
            Task {
                guard let self = self else { return }
                // Convert Data to [Float] for streaming
                let samples = audioData.withUnsafeBytes { buffer in
                    Array(buffer.bindMemory(to: Float.self))
                }
                do {
                    try await RunAnywhere.processStreamingAudio(samples)
                } catch {
                    Task { @MainActor in
                        self.error = error
                    }
                }
            }
        }

        logger.info("Live transcription started")
    }

    /// Stop live transcription
    public func stop() async {
        guard isActive else { return }

        logger.info("Stopping live transcription")

        // Stop streaming transcription
        await RunAnywhere.stopStreamingTranscription()

        // Cancel transcription task
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Stop audio capture
        audioCapture.stopRecording()

        // Finish audio stream
        audioContinuation?.finish()
        audioContinuation = nil

        // Clean up subscriptions
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil

        isActive = false
        audioLevel = 0.0

        logger.info("Live transcription stopped")
    }

    /// Get the final transcription text
    public var finalText: String {
        currentText
    }
}

// MARK: - Errors

/// Errors specific to live transcription
public enum LiveTranscriptionError: LocalizedError {
    case microphonePermissionDenied
    case alreadyActive
    case notActive

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required for live transcription"
        case .alreadyActive:
            return "Live transcription session is already active"
        case .notActive:
            return "Live transcription session is not active"
        }
    }
}

// MARK: - RunAnywhere Extension

public extension RunAnywhere {

    /// Start a new live transcription session
    ///
    /// This provides a high-level API for real-time speech-to-text that handles
    /// audio capture internally.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let session = try await RunAnywhere.startLiveTranscription()
    ///
    /// // Listen for updates
    /// for await text in session.transcriptions {
    ///     print(text)
    /// }
    ///
    /// // Or use the session's published properties
    /// session.$currentText.sink { text in
    ///     self.transcriptionLabel.text = text
    /// }
    ///
    /// // Stop when done
    /// await session.stop()
    /// ```
    ///
    /// - Parameters:
    ///   - options: STT options (language, etc.)
    ///   - onPartial: Optional callback for each partial transcription
    /// - Returns: A live transcription session
    /// - Throws: If SDK is not initialized or microphone access is denied
    @MainActor
    static func startLiveTranscription(
        options: STTOptions = STTOptions(),
        onPartial: ((String) -> Void)? = nil
    ) async throws -> LiveTranscriptionSession {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let session = LiveTranscriptionSession(options: options)
        try await session.start(onPartial: onPartial)
        return session
    }
}
