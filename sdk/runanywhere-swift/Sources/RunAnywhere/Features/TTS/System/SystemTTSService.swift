//
//  SystemTTSService.swift
//  RunAnywhere SDK
//
//  System TTS Service implementation using AVSpeechSynthesizer
//  Uses Swift 6 concurrency with actor-based state management
//

import AVFoundation
import Foundation

// MARK: - Speech State (Thread-safe for AVSpeechSynthesizer delegate callbacks)

/// Thread-safe state for speech synthesis using lock
private final class SpeechState: @unchecked Sendable {
    private let lock = NSLock()
    private var _continuation: CheckedContinuation<Data, Error>?
    private var _isSpeaking = false

    var isSpeaking: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSpeaking
    }

    func setContinuation(_ cont: CheckedContinuation<Data, Error>?) {
        lock.lock()
        _continuation = cont
        _isSpeaking = cont != nil
        lock.unlock()
    }

    func complete(with result: Result<Data, Error>) {
        lock.lock()
        let continuation = _continuation
        _continuation = nil
        _isSpeaking = false
        lock.unlock()

        guard let continuation = continuation else { return }

        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - System TTS Service

/// System TTS Service implementation using AVSpeechSynthesizer
///
/// This is the default TTS service that uses Apple's built-in speech synthesis.
/// It supports all iOS/macOS system voices and provides real-time speech playback.
///
/// **Note:** System TTS plays audio directly through speakers. The returned `Data`
/// is a placeholder - use ONNX Piper TTS if you need actual audio data for custom playback.
public final class SystemTTSService: NSObject, TTSService, @unchecked Sendable {

    // MARK: - Framework Identification

    public let inferenceFramework: InferenceFramework = .systemTTS

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = SDKLogger(category: "SystemTTS")
    private let state = SpeechState()

    // MARK: - Initialization

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTSService Protocol

    public func initialize() async throws {
        logger.info("System TTS initialized (direct playback mode)")
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        logger.info("Speaking: '\(text.prefix(50))...'")

        let utterance = createUtterance(text: text, options: options)

        // Use withCheckedThrowingContinuation properly with MainActor dispatch
        return try await withCheckedThrowingContinuation { continuation in
            // Dispatch to main thread synchronously to set state and speak
            DispatchQueue.main.async { [self] in
                state.setContinuation(continuation)
                synthesizer.speak(utterance)
            }
        }
    }

    public func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        // System TTS doesn't support streaming - synthesize and signal completion
        _ = try await synthesize(text: text, options: options)
        onChunk(Data())
    }

    public func stop() {
        DispatchQueue.main.async { [self] in
            synthesizer.stopSpeaking(at: .immediate)
            state.complete(with: .success(Data()))
        }
    }

    public var isSynthesizing: Bool {
        // Synchronous approximation using synthesizer state
        synthesizer.isSpeaking
    }

    public var availableVoices: [String] {
        AVSpeechSynthesisVoice.speechVoices().map { $0.identifier }
    }

    public func cleanup() async {
        stop()
    }

    // MARK: - Private Helpers

    private func createUtterance(text: String, options: TTSOptions) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)

        // Configure voice
        utterance.voice = resolveVoice(options: options)

        // Configure speech parameters
        utterance.rate = options.rate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = options.pitch
        utterance.volume = options.volume
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.0

        return utterance
    }

    private func resolveVoice(options: TTSOptions) -> AVSpeechSynthesisVoice? {
        guard let voiceId = options.voice,
              voiceId != "system" && voiceId != "system-tts" else {
            return AVSpeechSynthesisVoice(language: options.language)
        }

        return AVSpeechSynthesisVoice(identifier: voiceId)
            ?? AVSpeechSynthesisVoice(language: voiceId)
            ?? AVSpeechSynthesisVoice(language: options.language)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: AVSpeechSynthesizerDelegate {

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        logger.info("Speech playback completed")
        // Delegate is called on main thread, access state directly
        state.complete(with: .success(Data()))
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        logger.info("Speech playback cancelled")
        state.complete(with: .failure(CancellationError()))
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        logger.debug("Speech playback started")
    }
}
