//
//  AudioTypes.swift
//  RunAnywhere SDK
//
//  Audio-related type definitions used across audio components (STT, TTS, VAD, etc.)
//
//  🟢 BRIDGE: Maps to C++ rac_audio_format_enum_t
//  C++ Source: include/rac/features/stt/rac_stt_types.h
//

import CRACommons
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

    // MARK: - C++ Bridge (rac_audio_format_enum_t)

    /// Convert Swift AudioFormat to C++ rac_audio_format_enum_t
    public func toCFormat() -> rac_audio_format_enum_t {
        switch self {
        case .pcm: return RAC_AUDIO_FORMAT_PCM
        case .wav: return RAC_AUDIO_FORMAT_WAV
        case .mp3: return RAC_AUDIO_FORMAT_MP3
        case .opus: return RAC_AUDIO_FORMAT_OPUS
        case .aac: return RAC_AUDIO_FORMAT_AAC
        case .flac: return RAC_AUDIO_FORMAT_FLAC
        }
    }

    /// Initialize from C++ rac_audio_format_enum_t
    public init(from cFormat: rac_audio_format_enum_t) {
        switch cFormat {
        case RAC_AUDIO_FORMAT_PCM: self = .pcm
        case RAC_AUDIO_FORMAT_WAV: self = .wav
        case RAC_AUDIO_FORMAT_MP3: self = .mp3
        case RAC_AUDIO_FORMAT_OPUS: self = .opus
        case RAC_AUDIO_FORMAT_AAC: self = .aac
        case RAC_AUDIO_FORMAT_FLAC: self = .flac
        default: self = .pcm
        }
    }
}
