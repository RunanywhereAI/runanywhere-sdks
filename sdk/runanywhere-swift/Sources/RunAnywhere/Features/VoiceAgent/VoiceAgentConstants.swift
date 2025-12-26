//
//  VoiceAgentConstants.swift
//  RunAnywhere SDK
//
//  Constants for Voice Agent capability.
//  Centralizes hardcoded values with documentation.
//

import Foundation

// MARK: - Voice Agent Constants

/// Constants for Voice Agent capability.
///
/// Voice Agent combines STT, LLM, and TTS into a conversational pipeline.
/// These constants define the audio and timing parameters for the pipeline.
public enum VoiceAgentConstants {

    // MARK: - Audio Input (for STT)

    /// Standard sample rate for voice input (16kHz).
    ///
    /// Voice agent captures audio at this rate for STT processing.
    /// Matches the requirements of most speech recognition models.
    public static let inputSampleRate: Int = 16000

    /// Bytes per sample for 16-bit PCM audio input.
    public static let inputBytesPerSample: Int = 2

    /// Number of input channels (mono).
    public static let inputChannels: Int = 1

    // MARK: - Audio Output (from TTS)

    /// Standard sample rate for voice output (22.05kHz).
    ///
    /// TTS typically outputs at this rate for natural-sounding speech.
    public static let outputSampleRate: Int = 22050

    /// Bytes per sample for 16-bit PCM audio output.
    public static let outputBytesPerSample: Int = 2

    /// Number of output channels (mono).
    public static let outputChannels: Int = 1

    // MARK: - Timing

    /// Default timeout for waiting for speech input (seconds).
    ///
    /// How long to wait for user to start speaking before timing out.
    public static let defaultSpeechTimeoutSec: Double = 10.0

    /// Default maximum recording duration (seconds).
    ///
    /// Maximum time to record user speech before auto-stopping.
    public static let defaultMaxRecordingDurationSec: Double = 30.0

    /// Default pause duration to end recording (seconds).
    ///
    /// How long of a pause triggers end of speech detection.
    public static let defaultEndOfSpeechPauseSec: Double = 1.5

    // MARK: - Audio Chunk Processing

    /// Default chunk size for streaming audio (bytes).
    ///
    /// Audio is streamed in chunks of approximately this size
    /// for real-time processing.
    public static let defaultChunkSizeBytes: Int = 4096

    /// Default chunk duration for audio processing (milliseconds).
    ///
    /// Audio chunks are processed at this interval.
    public static let defaultChunkDurationMs: Int = 100

    // MARK: - Pipeline Timing

    /// Maximum time to wait for LLM response (seconds).
    public static let llmResponseTimeoutSec: Double = 30.0

    /// Maximum time to wait for TTS synthesis (seconds).
    public static let ttsResponseTimeoutSec: Double = 15.0
}
