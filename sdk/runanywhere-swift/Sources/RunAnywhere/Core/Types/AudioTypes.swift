//
//  AudioTypes.swift
//  RunAnywhere SDK
//
//  Audio-related type definitions used across audio components (STT, TTS, VAD, etc.)
//

import Foundation

// MARK: - Audio Format

/// Audio format options for audio processing
public enum AudioFormat: String, Sendable, CaseIterable {
    case pcm
    case wav
    case mp3
    case opus
    case aac
    case flac

    /// File extension for this format
    public var fileExtension: String {
        rawValue
    }

    /// MIME type for this format
    public var mimeType: String {
        switch self {
        case .pcm: return "audio/pcm"
        case .wav: return "audio/wav"
        case .mp3: return "audio/mpeg"
        case .opus: return "audio/opus"
        case .aac: return "audio/aac"
        case .flac: return "audio/flac"
        }
    }
}
