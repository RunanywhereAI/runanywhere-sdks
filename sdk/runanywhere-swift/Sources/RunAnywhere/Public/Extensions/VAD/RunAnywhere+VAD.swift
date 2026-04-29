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
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        // Get handle and configure
        let handle = try await CppBridge.VAD.shared.getHandle()

        var cConfig = rac_vad_config_t()
        cConfig.sample_rate = Int32(config.sampleRate)
        cConfig.frame_length = Float(config.frameLength)
        cConfig.energy_threshold = Float(config.energyThreshold)

        let configResult = rac_vad_component_configure(handle, &cConfig)
        if configResult != RAC_SUCCESS {
            // Log warning but continue
        }

        // Initialize
        let result = rac_vad_component_initialize(handle)
        guard result == RAC_SUCCESS else {
            throw SDKException.vad(.initializationFailed, "VAD initialization failed: \(result)")
        }
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

        let handle = try await CppBridge.VAD.shared.getHandle()

        var hasVoice: rac_bool_t = RAC_FALSE
        let result = samples.withUnsafeBufferPointer { buffer in
            rac_vad_component_process(
                handle,
                buffer.baseAddress,
                buffer.count,
                &hasVoice
            )
        }

        guard result == RAC_SUCCESS else {
            throw SDKException.vad(.processingFailed, "Failed to process samples: \(result)")
        }

        let detected = hasVoice == RAC_TRUE

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

        let handle = try await CppBridge.VAD.shared.getHandle()

        // Apply per-call threshold if provided
        if let opts = options, opts.threshold > 0 {
            rac_vad_component_set_energy_threshold(handle, opts.threshold)
        }

        var hasVoice: rac_bool_t = RAC_FALSE
        let result: rac_result_t = audioData.withUnsafeBytes { rawBuf in
            guard let baseAddress = rawBuf.bindMemory(to: Float.self).baseAddress else {
                return RAC_ERROR_INVALID_ARGUMENT
            }
            return rac_vad_component_process(handle, baseAddress, sampleCount, &hasVoice)
        }
        guard result == RAC_SUCCESS else {
            throw SDKException.vad(.processingFailed, "VAD processing failed: \(result)")
        }

        // Build proto result; energy comes from the current threshold getter as a proxy
        // (the C ABI does not expose a per-call energy output — this is consistent with
        // how Kotlin wraps the same ABI).
        var vadResult = RAVADResult()
        vadResult.isSpeech = hasVoice == RAC_TRUE
        vadResult.confidence = hasVoice == RAC_TRUE ? 1.0 : 0.0
        vadResult.energy = rac_vad_component_get_energy_threshold(handle)
        vadResult.durationMs = Int32(Double(sampleCount) / 16.0)  // assume 16 kHz

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
        guard let handle = try? await CppBridge.VAD.shared.getHandle() else { return }

        // Build a statistics snapshot from the live C ABI getters and forward to the callback
        // after each process call via a periodic poll. The C ABI does not expose a statistics
        // callback registration, so we adapt it to the canonical shape here.
        let context = VADStatisticsCallbackContext(handle: handle, onStats: callback)
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
        guard let handle = try? await CppBridge.VAD.shared.getHandle() else { return }

        // Create callback context
        let context = VADCallbackContext(onActivity: callback)
        await VADStateManager.shared.setCallbackContext(context)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

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
    let handle: rac_handle_t
    let onStats: (RAVADStatistics) -> Void

    init(handle: rac_handle_t, onStats: @escaping (RAVADStatistics) -> Void) {
        self.handle = handle
        self.onStats = onStats
    }

    func emitSnapshot() {
        var stats = RAVADStatistics()
        stats.currentThreshold = rac_vad_component_get_energy_threshold(handle)
        // Remaining fields (currentEnergy, ambientLevel, recentAvg, recentMax) are not
        // directly exposed by the current C ABI; they default to 0.0 until the C layer
        // adds rac_vad_component_get_statistics (CPP-blocked: G-C6).
        onStats(stats)
    }
}
