//
//  SimpleEnergyVADService.swift
//  RunAnywhere SDK
//
//  Thin Swift wrapper over rac_energy_vad_* C API.
//  All business logic is in the C++ layer; this is just a Swift interface.
//
//  ⚠️ WARNING: This is a direct wrapper. Do NOT add custom logic here.
//  The C++ layer (runanywhere-commons) is the source of truth.
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation
import os

/// Energy-based Voice Activity Detection service.
/// This is a thin wrapper over the C++ rac_energy_vad API.
public final class SimpleEnergyVADService: VADService, @unchecked Sendable {
    public let serviceName = "SimpleEnergyVAD"
    public let inferenceFramework: InferenceFramework = .builtIn

    // MARK: - State

    /// Handle to the C++ energy VAD
    private var handle: rac_energy_vad_handle_t?

    /// Whether VAD is currently running
    private var isRunning = false

    /// Lock for thread safety (Swift 6 compatible)
    private let lock = OSAllocatedUnfairLock()

    // MARK: - Configuration

    public let sampleRate: Int
    public let frameLengthSamples: Int

    public var frameLength: Float {
        Float(frameLengthSamples) / Float(sampleRate)
    }

    public var energyThreshold: Float {
        get {
            lock.withLock {
                guard let handle = handle else { return 0.005 }
                var threshold: Float = 0
                rac_energy_vad_get_threshold(handle, &threshold)
                return threshold
            }
        }
        set {
            lock.withLock {
                guard let handle = handle else { return }
                rac_energy_vad_set_threshold(handle, newValue)
            }
        }
    }

    // MARK: - Callbacks

    public var onSpeechActivity: ((SpeechActivityEvent) -> Void)?
    public var onAudioBuffer: ((Data) -> Void)?

    // MARK: - Initialization

    public init(
        sampleRate: Int = 16000,
        frameLength: Double = 0.1,
        energyThreshold: Float = 0.005
    ) {
        self.sampleRate = sampleRate
        self.frameLengthSamples = Int(Double(sampleRate) * frameLength)

        // Create C config
        var config = rac_energy_vad_config_t()
        config.sample_rate = Int32(sampleRate)
        config.frame_length = Float(frameLength)
        config.energy_threshold = energyThreshold

        // Create handle
        var newHandle: rac_energy_vad_handle_t?
        let result = rac_energy_vad_create(&config, &newHandle)
        if result == RAC_SUCCESS {
            handle = newHandle
        }
    }

    deinit {
        if let handle = handle {
            rac_energy_vad_destroy(handle)
        }
    }

    // MARK: - VADService Protocol

    public func initialize() async throws {
        let result: rac_result_t = lock.withLock {
            guard let handle = handle else { return RAC_ERROR_NULL_POINTER }
            return rac_energy_vad_initialize(handle)
        }

        guard result == RAC_SUCCESS else {
            if result == RAC_ERROR_NULL_POINTER {
                throw SDKError.vad(.initializationFailed, "VAD handle not created")
            }
            throw SDKError.vad(.initializationFailed, "VAD initialization failed: \(result)")
        }
    }

    public var isSpeechActive: Bool {
        lock.withLock {
            guard let handle = handle else { return false }
            var active: rac_bool_t = RAC_FALSE
            rac_energy_vad_is_speech_active(handle, &active)
            return active == RAC_TRUE
        }
    }

    public func start() {
        lock.withLock {
            guard let handle = handle else { return }

            let result = rac_energy_vad_start(handle)
            guard result == RAC_SUCCESS else { return }

            isRunning = true

            // Set up speech activity callback
            if let onSpeechActivity = onSpeechActivity {
                let context = VADActivityContext(callback: onSpeechActivity)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                rac_energy_vad_set_speech_callback(
                    handle,
                    { event, userData in
                        guard let userData = userData else { return }
                        let ctx = Unmanaged<VADActivityContext>.fromOpaque(userData).takeUnretainedValue()
                        let swiftEvent: SpeechActivityEvent = event == RAC_SPEECH_ACTIVITY_STARTED ? .started : .ended
                        ctx.callback(swiftEvent)
                    },
                    contextPtr
                )
            }
        }
    }

    public func stop() {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_stop(handle)
            isRunning = false
        }
    }

    public func reset() {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_reset(handle)
        }
    }

    public func pause() {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_pause(handle)
        }
    }

    public func resume() {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_resume(handle)
        }
    }

    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert buffer to float array
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        _ = processAudioData(samples)
    }

    @discardableResult
    public func processAudioData(_ audioData: [Float]) -> Bool {
        return lock.withLock {
            guard let handle = handle else { return false }

            var hasVoice: rac_bool_t = RAC_FALSE
            let result = audioData.withUnsafeBufferPointer { buffer in
                rac_energy_vad_process_audio(
                    handle,
                    buffer.baseAddress,
                    buffer.count,
                    &hasVoice
                )
            }

            guard result == RAC_SUCCESS else { return false }

            // Forward to audio buffer callback if set
            if let onAudioBuffer = onAudioBuffer {
                // Convert float array to Data
                let data = audioData.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else { return Data() }
                    return Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Float>.size)
                }
                onAudioBuffer(data)
            }

            return hasVoice == RAC_TRUE
        }
    }

    // MARK: - Calibration

    /// Start automatic calibration
    public func startCalibration() {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_start_calibration(handle)
        }
    }

    /// Check if calibration is in progress
    public var isCalibrating: Bool {
        return lock.withLock {
            guard let handle = handle else { return false }
            var calibrating: rac_bool_t = RAC_FALSE
            rac_energy_vad_is_calibrating(handle, &calibrating)
            return calibrating == RAC_TRUE
        }
    }

    /// Set calibration multiplier
    public func setCalibrationParameters(multiplier: Float) {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_set_calibration_multiplier(handle, multiplier)
        }
    }

    // MARK: - TTS Feedback Prevention

    /// Notify VAD that TTS is about to start
    public func notifyTTSWillStart() {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_notify_tts_start(handle)
        }
    }

    /// Notify VAD that TTS has finished
    public func notifyTTSDidFinish() {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_notify_tts_finish(handle)
        }
    }

    /// Set TTS threshold multiplier
    public func setTTSThresholdMultiplier(_ multiplier: Float) {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_set_tts_multiplier(handle, multiplier)
        }
    }

    // MARK: - Statistics

    public func getStatistics() -> VADStatistics {
        return lock.withLock {
            guard let handle = handle else {
                return VADStatistics(current: 0, threshold: 0, ambient: 0, recentAvg: 0, recentMax: 0)
            }

            var stats = rac_energy_vad_stats_t()
            let result = rac_energy_vad_get_statistics(handle, &stats)

            guard result == RAC_SUCCESS else {
                return VADStatistics(current: 0, threshold: 0, ambient: 0, recentAvg: 0, recentMax: 0)
            }

            return VADStatistics(
                current: stats.current,
                threshold: stats.threshold,
                ambient: stats.ambient,
                recentAvg: stats.recent_avg,
                recentMax: stats.recent_max
            )
        }
    }

    public func setEnergyThreshold(_ threshold: Float) {
        lock.withLock {
            guard let handle = handle else { return }
            rac_energy_vad_set_threshold(handle, threshold)
        }
    }
}

// MARK: - VAD Activity Context

private final class VADActivityContext: @unchecked Sendable {
    let callback: (SpeechActivityEvent) -> Void

    init(callback: @escaping (SpeechActivityEvent) -> Void) {
        self.callback = callback
    }
}
