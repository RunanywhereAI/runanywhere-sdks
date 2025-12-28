//
//  RunAnywhere+VAD.swift
//  RunAnywhere SDK
//
//  Public API for Voice Activity Detection operations
//

@preconcurrency import AVFoundation
import Foundation

// MARK: - VAD Operations

public extension RunAnywhere {

    // MARK: - Initialization

    /// Initialize VAD with default configuration
    static func initializeVAD() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await serviceContainer.vadCapability.initialize()
    }

    /// Initialize VAD with configuration
    /// - Parameter config: VAD configuration
    static func initializeVAD(_ config: VADConfiguration) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Configure and then initialize
        await serviceContainer.vadCapability.configure(config)
        try await serviceContainer.vadCapability.initialize()
    }

    /// Check if VAD is ready
    static var isVADReady: Bool {
        get async {
            await serviceContainer.vadCapability.isReady
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

        return try await serviceContainer.vadCapability.processSamples(samples)
    }

    /// Detect speech in audio samples
    /// - Parameter samples: Float array of audio samples
    /// - Returns: Whether speech was detected
    static func detectSpeech(in samples: [Float]) async throws -> Bool {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        return try await serviceContainer.vadCapability.processSamples(samples)
    }

    // MARK: - Control

    /// Start VAD processing
    static func startVAD() async throws {
        try await serviceContainer.vadCapability.start()
    }

    /// Stop VAD processing
    static func stopVAD() async throws {
        try await serviceContainer.vadCapability.stop()
    }

    // MARK: - Callbacks

    /// Set VAD speech activity callback
    /// - Parameter callback: Callback invoked when speech state changes
    static func setVADSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) async {
        await serviceContainer.vadCapability.setOnSpeechActivity(callback)
    }

    /// Set VAD audio buffer callback
    /// - Parameter callback: Callback invoked with audio samples
    static func setVADAudioBufferCallback(_ callback: @escaping ([Float]) -> Void) async {
        await serviceContainer.vadCapability.setOnAudioBuffer(callback)
    }

    // MARK: - Cleanup

    /// Cleanup VAD resources
    static func cleanupVAD() async {
        await serviceContainer.vadCapability.cleanup()
    }
}
