//
//  RunAnywhere+VAD.swift
//  RunAnywhere SDK
//
//  Public API for Voice Activity Detection operations.
//  Calls C++ directly via CppBridge.VAD for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation

// MARK: - VAD State Storage

/// Internal actor for managing VAD-specific state for callbacks
private actor VADStateManager {
    static let shared = VADStateManager()

    var onAudioBuffer: (([Float]) -> Void)?
    // periphery:ignore - Retained to prevent deallocation while C callback is active
    var callbackContext: VADCallbackContext?
    // periphery:ignore - Retained to prevent deallocation
    var statisticsContext: VADStatisticsCallbackContext?

    func setOnAudioBuffer(_ callback: (([Float]) -> Void)?) {
        onAudioBuffer = callback
    }

    func setCallbackContext(_ context: VADCallbackContext?) {
        callbackContext = context
    }

    func setStatisticsContext(_ context: VADStatisticsCallbackContext?) {
        statisticsContext = context
    }

    func getAudioBufferCallback() -> (([Float]) -> Void)? {
        onAudioBuffer
    }

    func getStatisticsContext() -> VADStatisticsCallbackContext? {
        statisticsContext
    }
}

// MARK: - VAD Operations

public extension RunAnywhere {

    // MARK: - Initialization

    /// Initialize VAD with default configuration
    static func initializeVAD() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await CppBridge.VAD.shared.initialize()
    }

    /// Initialize VAD with configuration
    /// - Parameter config: VAD configuration
    static func initializeVAD(_ config: VADConfiguration) async throws {
        try await initializeVAD(config.toRAVADConfiguration())
    }

    /// Initialize and configure VAD through the generated-proto C++ ABI.
    static func initializeVAD(_ config: RAVADConfiguration) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await CppBridge.VAD.shared.initialize()
        try await CppBridge.VAD.shared.configure(config)
    }

    /// Check if VAD is ready
    static var isVADReady: Bool {
        get async {
            await CppBridge.VAD.shared.isInitialized
        }
    }

    // MARK: - Detection

    /// Detect speech in audio buffer
    /// - Parameter buffer: Audio buffer to analyze
    /// - Returns: Whether speech was detected
    static func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> Bool {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        // Convert AVAudioPCMBuffer to [Float]
        guard let channelData = buffer.floatChannelData else {
            throw SDKException.vad(.emptyAudioBuffer, "Audio buffer has no channel data")
        }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        return try await detectSpeech(in: samples)
    }

    /// Detect speech in audio samples
    /// - Parameter samples: Float array of audio samples
    /// - Returns: Whether speech was detected
    static func detectSpeech(in samples: [Float]) async throws -> Bool {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let audioData = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let detected = try await detectVoiceActivity(audioData).isSpeech

        // Forward to audio buffer callback if set
        if let callback = await VADStateManager.shared.getAudioBufferCallback() {
            callback(samples)
        }

        return detected
    }

    // MARK: - Control

    /// Start VAD processing
    static func startVAD() async throws {
        try await CppBridge.VAD.shared.start()
    }

    /// Stop VAD processing
    static func stopVAD() async throws {
        try await CppBridge.VAD.shared.stop()
    }

    // MARK: - Canonical §6 Methods

    /// Detect voice activity in a raw PCM audio buffer.
    ///
    /// Returns a `RAVADResult` proto containing `isSpeech`, `confidence`, `energy`,
    /// and `durationMs`. Prefer this over the legacy `detectSpeech(in:)` which
    /// returns only a `Bool`.
    ///
    /// - Parameters:
    ///   - audioData: Raw IEEE-754 single-precision PCM samples as `Data` (4 bytes/sample).
    ///   - options: Optional per-call VAD options (threshold override, duration parameters).
    /// - Returns: `RAVADResult` with speech detection details.
    static func detectVoiceActivity(_ audioData: Data, options: RAVADOptions? = nil) async throws -> RAVADResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let sampleCount = audioData.count / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            throw SDKException.vad(.emptyAudioBuffer, "Audio data is empty")
        }

        let samples: [Float] = audioData.withUnsafeBytes { rawBuf in
            Array(rawBuf.bindMemory(to: Float.self).prefix(sampleCount))
        }
        let vadResult = try await CppBridge.VAD.shared.process(
            samples: samples,
            options: options ?? RAVADOptions()
        )

        // Notify statistics subscriber if registered
        if let statsCtx = await VADStateManager.shared.getStatisticsContext() {
            statsCtx.emitSnapshot()
        }

        return vadResult
    }

    /// Stream VAD results over a sequence of raw PCM audio chunks.
    ///
    /// Each element in `audio` must be `Data` holding IEEE-754 single-precision
    /// PCM samples at 16 kHz mono. The returned `AsyncStream` yields one
    /// `RAVADResult` per input chunk.
    ///
    /// Cancellation: break out of the `for await` loop to stop processing.
    static func streamVAD(audio: AsyncStream<Data>) -> AsyncStream<RAVADResult> {
        AsyncStream<RAVADResult> { continuation in
            let task = Task {
                for await chunk in audio {
                    guard !Task.isCancelled else { break }
                    if let vadResult = try? await detectVoiceActivity(chunk) {
                        continuation.yield(vadResult)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Set a callback that fires whenever the VAD updates its internal statistics.
    ///
    /// The callback is invoked from a background thread. The `RAVADStatistics` proto
    /// includes `currentEnergy`, `currentThreshold`, `ambientLevel`, `recentAvg`,
    /// and `recentMax`.
    ///
    /// - Parameter callback: Closure receiving `RAVADStatistics` on each VAD frame.
    static func setVADStatisticsCallback(_ callback: @escaping (RAVADStatistics) -> Void) async {
        let context = VADStatisticsCallbackContext(onStats: callback)
        await VADStateManager.shared.setStatisticsContext(context)
    }

    /// Reset VAD internal state.
    ///
    /// Clears adaptive threshold history, speech-segment counters, and timing accumulators.
    /// Use when switching between audio streams or after a long pause.
    static func resetVAD() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.VAD.shared.reset()
    }

    // MARK: - Callbacks

    /// Set VAD speech activity callback
    /// - Parameter callback: Callback invoked when speech state changes
    static func setVADSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) async {
        if (try? await CppBridge.VAD.shared.setActivityCallbackProto({ event in
            switch event.eventType {
            case .speechStarted:
                callback(.started)
            case .speechEnded:
                callback(.ended)
            default:
                break
            }
        })) != nil {
            return
        }

        let context = VADCallbackContext(onActivity: callback)
        await VADStateManager.shared.setCallbackContext(context)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        guard let handle = try? await CppBridge.VAD.shared.getHandle() else { return }
        rac_vad_component_set_activity_callback(
            handle,
            { activity, userData in
                guard let userData = userData else { return }
                let ctx = Unmanaged<VADCallbackContext>.fromOpaque(userData).takeUnretainedValue()
                let event: SpeechActivityEvent = activity == RAC_SPEECH_STARTED ? .started : .ended
                ctx.onActivity(event)
            },
            contextPtr
        )
    }

    /// Set VAD audio buffer callback
    /// - Parameter callback: Callback invoked with audio samples
    static func setVADAudioBufferCallback(_ callback: @escaping ([Float]) -> Void) async {
        await VADStateManager.shared.setOnAudioBuffer(callback)
    }

    // MARK: - Cleanup

    /// Cleanup VAD resources
    static func cleanupVAD() async {
        await CppBridge.VAD.shared.cleanup()
        await VADStateManager.shared.setOnAudioBuffer(nil)
        await VADStateManager.shared.setCallbackContext(nil)
    }
}

// MARK: - Callback Contexts

private final class VADCallbackContext: @unchecked Sendable {
    let onActivity: (SpeechActivityEvent) -> Void

    init(onActivity: @escaping (SpeechActivityEvent) -> Void) {
        self.onActivity = onActivity
    }
}

/// Holds the statistics callback and the VAD handle needed to poll C ABI getters.
/// The C ABI does not expose a statistics callback registration; we build a snapshot
/// from live getters and forward it each time `detectVoiceActivity` is called.
private final class VADStatisticsCallbackContext: @unchecked Sendable {
    let onStats: (RAVADStatistics) -> Void

    init(onStats: @escaping (RAVADStatistics) -> Void) {
        self.onStats = onStats
    }

    func emitSnapshot() {
        Task {
            if let stats = try? await CppBridge.VAD.shared.statisticsProto() {
                onStats(stats)
            }
        }
    }
}
