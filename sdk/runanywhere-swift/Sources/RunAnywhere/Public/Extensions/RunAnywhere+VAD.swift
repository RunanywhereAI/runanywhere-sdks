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

        try await serviceContainer.vadCapability.initialize(config)
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
    /// - Returns: VAD output with detection result
    static func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> VADOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        return try await serviceContainer.vadCapability.detectSpeech(in: buffer)
    }

    /// Detect speech in audio samples
    /// - Parameter samples: Float array of audio samples
    /// - Returns: VAD output with detection result
    static func detectSpeech(in samples: [Float]) async throws -> VADOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        return try await serviceContainer.vadCapability.detectSpeech(in: samples)
    }

    // MARK: - Control

    /// Start VAD processing
    static func startVAD() async {
        await serviceContainer.vadCapability.start()
    }

    /// Stop VAD processing
    static func stopVAD() async {
        await serviceContainer.vadCapability.stop()
    }

    /// Reset VAD state
    static func resetVAD() async {
        await serviceContainer.vadCapability.reset()
    }

    // MARK: - Configuration

    /// Set VAD energy threshold
    /// - Parameter threshold: Energy threshold (0.0 to 1.0)
    static func setVADEnergyThreshold(_ threshold: Float) async {
        await serviceContainer.vadCapability.setEnergyThreshold(threshold)
    }

    /// Set VAD speech activity callback
    /// - Parameter callback: Callback invoked when speech state changes
    static func setVADSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) async {
        await serviceContainer.vadCapability.setSpeechActivityCallback(callback)
    }

    // MARK: - Cleanup

    /// Cleanup VAD resources
    static func cleanupVAD() async {
        await serviceContainer.vadCapability.cleanup()
    }
}
