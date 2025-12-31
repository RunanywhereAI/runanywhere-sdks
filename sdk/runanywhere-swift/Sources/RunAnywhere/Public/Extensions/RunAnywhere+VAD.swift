//
//  RunAnywhere+VAD.swift
//  RunAnywhere SDK
//
//  Public API for Voice Activity Detection operations.
//  Calls C++ directly via CapabilityManager for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation

// MARK: - VAD State Storage

/// Internal actor for managing VAD-specific state that can't be in CapabilityManager
private actor VADStateManager {
    static let shared = VADStateManager()

    var onSpeechActivity: ((SpeechActivityEvent) -> Void)?
    var onAudioBuffer: (([Float]) -> Void)?
    var callbackContext: VADCallbackContext?

    func setOnSpeechActivity(_ callback: ((SpeechActivityEvent) -> Void)?) {
        onSpeechActivity = callback
    }

    func setOnAudioBuffer(_ callback: (([Float]) -> Void)?) {
        onAudioBuffer = callback
    }

    func setCallbackContext(_ context: VADCallbackContext?) {
        callbackContext = context
    }

    func getAudioBufferCallback() -> (([Float]) -> Void)? {
        onAudioBuffer
    }
}

// MARK: - VAD Operations

public extension RunAnywhere {

    // MARK: - Initialization

    /// Initialize VAD with default configuration
    static func initializeVAD() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await CapabilityManager.shared.initializeVAD(sampleRate: 16000, channels: 1)
    }

    /// Initialize VAD with configuration
    /// - Parameter config: VAD configuration
    static func initializeVAD(_ config: VADConfiguration) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Get handle and configure
        let handle = try await CapabilityManager.shared.getVADHandle()

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
            throw SDKError.vad(.initializationFailed, "VAD initialization failed: \(result)")
        }
    }

    /// Check if VAD is ready
    static var isVADReady: Bool {
        get async {
            await CapabilityManager.shared.isVADInitialized
        }
    }

    // MARK: - Detection

    /// Detect speech in audio buffer
    /// - Parameter buffer: Audio buffer to analyze
    /// - Returns: Whether speech was detected
    static func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> Bool {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Convert AVAudioPCMBuffer to [Float]
        guard let channelData = buffer.floatChannelData else {
            throw SDKError.vad(.emptyAudioBuffer, "Audio buffer has no channel data")
        }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        return try await detectSpeech(in: samples)
    }

    /// Detect speech in audio samples
    /// - Parameter samples: Float array of audio samples
    /// - Returns: Whether speech was detected
    static func detectSpeech(in samples: [Float]) async throws -> Bool {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CapabilityManager.shared.getVADHandle()

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
            throw SDKError.vad(.processingFailed, "Failed to process samples: \(result)")
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
        let handle = try await CapabilityManager.shared.getVADHandle()
        let result = rac_vad_component_start(handle)
        guard result == RAC_SUCCESS else {
            throw SDKError.vad(.startFailed, "Failed to start VAD: \(result)")
        }
    }

    /// Stop VAD processing
    static func stopVAD() async throws {
        let handle = try await CapabilityManager.shared.getVADHandle()
        let result = rac_vad_component_stop(handle)
        if result != RAC_SUCCESS {
            // Log warning but don't throw
        }
    }

    // MARK: - Callbacks

    /// Set VAD speech activity callback
    /// - Parameter callback: Callback invoked when speech state changes
    static func setVADSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) async {
        await VADStateManager.shared.setOnSpeechActivity(callback)

        guard let handle = try? await CapabilityManager.shared.getVADHandle() else { return }

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
        await CapabilityManager.shared.cleanupVAD()
        await VADStateManager.shared.setOnSpeechActivity(nil)
        await VADStateManager.shared.setOnAudioBuffer(nil)
        await VADStateManager.shared.setCallbackContext(nil)
    }
}

// MARK: - Callback Context

private final class VADCallbackContext: @unchecked Sendable {
    let onActivity: (SpeechActivityEvent) -> Void

    init(onActivity: @escaping (SpeechActivityEvent) -> Void) {
        self.onActivity = onActivity
    }
}
