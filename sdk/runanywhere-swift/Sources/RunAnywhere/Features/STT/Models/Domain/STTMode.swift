//
//  STTMode.swift
//  RunAnywhere SDK
//
//  Transcription mode for speech-to-text
//

import Foundation

// MARK: - STT Mode

/// Transcription mode for speech-to-text
public enum STTMode: String, CaseIterable, Sendable {
    /// Batch mode: Record all audio first, then transcribe everything at once
    /// Best for: Short recordings, offline processing, higher accuracy
    case batch

    /// Live/Streaming mode: Transcribe audio in real-time as it's recorded
    /// Best for: Live captions, real-time feedback, long recordings
    case live

    public var displayName: String {
        switch self {
        case .batch: return "Batch"
        case .live: return "Live"
        }
    }

    public var description: String {
        switch self {
        case .batch:
            return "Record audio, then transcribe all at once"
        case .live:
            return "Real-time transcription as you speak"
        }
    }

    public var icon: String {
        switch self {
        case .batch: return "waveform.badge.mic"
        case .live: return "waveform"
        }
    }
}
