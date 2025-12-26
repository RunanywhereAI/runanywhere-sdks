//
//  STTConstants.swift
//  RunAnywhere SDK
//
//  Constants for Speech-to-Text capability.
//  Centralizes hardcoded values with documentation.
//

import Foundation

// MARK: - STT Constants

/// Constants for Speech-to-Text capability.
///
/// These values are derived from industry standards and model requirements:
/// - Whisper models expect 16kHz audio
/// - Most STT models use 16-bit PCM format
/// - Confidence scores range from 0.0 to 1.0
public enum STTConstants {

    // MARK: - Audio Format

    /// Standard sample rate for STT models (16kHz).
    ///
    /// This is the expected input format for most STT models including:
    /// - OpenAI Whisper (all sizes)
    /// - Sherpa-ONNX Whisper
    ///
    /// Audio at different sample rates should be resampled to 16kHz before processing.
    public static let defaultSampleRate: Int = 16000

    /// Maximum supported sample rate (48kHz).
    ///
    /// Audio above this rate is typically downsampled before processing.
    public static let maxSampleRate: Int = 48000

    /// Minimum supported sample rate (8kHz).
    ///
    /// Audio below this rate may produce poor transcription quality.
    public static let minSampleRate: Int = 8000

    /// Bytes per sample for 16-bit PCM audio.
    ///
    /// STT models typically expect 16-bit (2 bytes) mono PCM audio.
    public static let bytesPerSample: Int = 2

    /// Number of audio channels (mono).
    ///
    /// STT models expect mono audio. Stereo audio should be mixed to mono.
    public static let channels: Int = 1

    // MARK: - Confidence Scores

    /// Default confidence score when not provided by the model.
    ///
    /// Used as a fallback when the underlying STT service doesn't provide
    /// confidence scores. Value of 0.9 indicates high confidence.
    public static let defaultConfidence: Float = 0.9

    /// Minimum acceptable confidence score for reliable transcription.
    ///
    /// Transcriptions below this threshold may need review or re-transcription.
    public static let minAcceptableConfidence: Float = 0.5

    // MARK: - Streaming

    /// Default chunk duration for streaming transcription (milliseconds).
    ///
    /// Audio is processed in chunks of this duration for real-time transcription.
    /// Shorter chunks = lower latency, longer chunks = better accuracy.
    public static let defaultStreamingChunkMs: Int = 100

    /// Minimum chunk duration for streaming (milliseconds).
    public static let minStreamingChunkMs: Int = 50

    /// Maximum chunk duration for streaming (milliseconds).
    public static let maxStreamingChunkMs: Int = 1000

    // MARK: - Language

    /// Default language code for transcription.
    ///
    /// English is the default; models may support auto-detection.
    public static let defaultLanguage: String = "en"

    // MARK: - Audio Duration Estimation

    /// Estimate audio duration from data size.
    ///
    /// Formula: `duration = (bytes / bytesPerSample) / sampleRate`
    ///
    /// - Parameters:
    ///   - dataSize: Size of audio data in bytes
    ///   - sampleRate: Sample rate in Hz (defaults to 16kHz)
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
    ///   - sampleRate: Sample rate in Hz (defaults to 16kHz)
    /// - Returns: Estimated duration in milliseconds
    public static func estimateAudioDurationMs(
        dataSize: Int,
        sampleRate: Int = defaultSampleRate
    ) -> Double {
        return estimateAudioDuration(dataSize: dataSize, sampleRate: sampleRate) * 1000
    }
}
