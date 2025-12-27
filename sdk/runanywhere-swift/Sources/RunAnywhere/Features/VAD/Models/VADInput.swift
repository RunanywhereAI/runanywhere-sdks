//
//  VADInput.swift
//  RunAnywhere SDK
//
//  Input model for Voice Activity Detection processing
//

@preconcurrency import AVFoundation
import Foundation

/// Input for Voice Activity Detection processing
public struct VADInput: ComponentInput {

    /// Audio buffer to process (mutually exclusive with audioSamples)
    public let buffer: AVAudioPCMBuffer?

    /// Audio samples as float array (mutually exclusive with buffer)
    public let audioSamples: [Float]?

    /// Optional override for energy threshold
    public let energyThresholdOverride: Float?

    // MARK: - Initializers

    /// Initialize with audio buffer
    /// - Parameter buffer: AVAudioPCMBuffer containing audio data
    public init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
        self.audioSamples = nil
        self.energyThresholdOverride = nil
    }

    /// Initialize with audio samples
    /// - Parameters:
    ///   - audioSamples: Array of Float audio samples
    ///   - energyThresholdOverride: Optional threshold override for this input
    public init(audioSamples: [Float], energyThresholdOverride: Float? = nil) {
        self.buffer = nil
        self.audioSamples = audioSamples
        self.energyThresholdOverride = energyThresholdOverride
    }

    // MARK: - ComponentInput Conformance

    /// Validate the input
    public func validate() throws {
        // Must have either buffer or audioSamples
        if buffer == nil && audioSamples == nil {
            throw SDKError.vad(
                .invalidInput,
                "VADInput must contain either buffer or audioSamples"
            )
        }

        // Both cannot be provided
        if buffer != nil && audioSamples != nil {
            throw SDKError.vad(
                .invalidInput,
                "VADInput cannot contain both buffer and audioSamples"
            )
        }

        // Validate threshold override if provided
        if let threshold = energyThresholdOverride {
            guard threshold >= 0 && threshold <= 1.0 else {
                throw SDKError.vad(
                    .invalidInput,
                    "Energy threshold override must be between 0 and 1.0"
                )
            }
        }

        // Validate audio samples are not empty
        if let samples = audioSamples, samples.isEmpty {
            throw SDKError.vad(.emptyAudioBuffer, "Audio buffer is empty")
        }

        // Validate buffer is not empty
        if let buf = buffer, buf.frameLength == 0 {
            throw SDKError.vad(.emptyAudioBuffer, "Audio buffer is empty")
        }
    }
}
