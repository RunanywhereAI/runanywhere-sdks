//
//  TTSConstants.swift
//  RunAnywhere SDK
//
//  Constants for Text-to-Speech capability.
//  Centralizes hardcoded values with documentation.
//

import Foundation

// MARK: - TTS Constants

/// Constants for Text-to-Speech capability.
///
/// These values are derived from industry standards and model requirements:
/// - Most TTS models output 22.05kHz or 24kHz audio
/// - Output is typically 16-bit PCM or compressed formats
public enum TTSConstants {

    // MARK: - Audio Format

    /// Standard sample rate for TTS output (22.05kHz).
    ///
    /// This is the common output format for most TTS models including:
    /// - Piper TTS
    /// - VITS-based models
    /// - Most neural TTS systems
    ///
    /// Some high-quality models may output at 24kHz or 44.1kHz.
    public static let defaultSampleRate: Int = 22050

    /// High-quality sample rate (24kHz).
    ///
    /// Used by some higher-quality TTS models for improved audio fidelity.
    public static let highQualitySampleRate: Int = 24000

    /// CD-quality sample rate (44.1kHz).
    ///
    /// Used for high-fidelity audio output, typically for music or
    /// premium voice synthesis.
    public static let cdQualitySampleRate: Int = 44100

    /// Maximum supported sample rate (48kHz).
    public static let maxSampleRate: Int = 48000

    /// Bytes per sample for 16-bit PCM audio.
    ///
    /// TTS models typically output 16-bit (2 bytes) mono PCM audio.
    public static let bytesPerSample: Int = 2

    /// Number of audio channels (mono).
    ///
    /// Most TTS models output mono audio. Stereo output is less common.
    public static let channels: Int = 1

    // MARK: - Performance Metrics

    /// Default speaking rate multiplier.
    ///
    /// 1.0 = normal speed, < 1.0 = slower, > 1.0 = faster.
    public static let defaultSpeakingRate: Float = 1.0

    /// Minimum speaking rate multiplier.
    public static let minSpeakingRate: Float = 0.5

    /// Maximum speaking rate multiplier.
    public static let maxSpeakingRate: Float = 2.0

    // MARK: - Streaming

    /// Default chunk size for streaming synthesis (bytes).
    ///
    /// Audio is generated and streamed in chunks of approximately this size.
    public static let defaultStreamingChunkBytes: Int = 4096

    // MARK: - Audio Duration Estimation

    /// Estimate audio duration from data size.
    ///
    /// Formula: `duration = (bytes / bytesPerSample) / sampleRate`
    ///
    /// - Parameters:
    ///   - dataSize: Size of audio data in bytes
    ///   - sampleRate: Sample rate in Hz (defaults to 22.05kHz)
    /// - Returns: Estimated duration in seconds
    public static func estimateAudioDuration(
        dataSize: Int,
        sampleRate: Int = defaultSampleRate
    ) -> TimeInterval {
        let totalSamples = dataSize / bytesPerSample
        return TimeInterval(totalSamples) / TimeInterval(sampleRate)
    }

    /// Estimate audio duration in milliseconds.
    ///
    /// - Parameters:
    ///   - dataSize: Size of audio data in bytes
    ///   - sampleRate: Sample rate in Hz (defaults to 22.05kHz)
    /// - Returns: Estimated duration in milliseconds
    public static func estimateAudioDurationMs(
        dataSize: Int,
        sampleRate: Int = defaultSampleRate
    ) -> Double {
        return estimateAudioDuration(dataSize: dataSize, sampleRate: sampleRate) * 1000
    }

    /// Estimate characters per second from synthesis metrics.
    ///
    /// - Parameters:
    ///   - characterCount: Number of characters synthesized
    ///   - durationMs: Time taken in milliseconds
    /// - Returns: Characters per second
    public static func calculateCharactersPerSecond(
        characterCount: Int,
        durationMs: Double
    ) -> Double {
        guard durationMs > 0 else { return 0 }
        return Double(characterCount) / (durationMs / 1000)
    }
}
